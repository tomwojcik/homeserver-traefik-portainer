# Jellyfin

## Compose / template

| Setting | Value | Why |
|---|---|---|
| image | `lscr.io/linuxserver/jellyfin:12.0ubu2604-ls48` | Pinned. LinuxServer's root-init + `PUID`/`PGID` model (no documented non-root mode for this image). |
| capabilities | `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID`, `KILL`; rest dropped | What the init needs to fix ownership and drop to `abc`. |
| mounts | `/config`; `data/movies` at `/data/movies` **ro**; `data/tv` at `/data/tv` **ro**; `jellyfin-cache` at `/config/cache` | Library read-only (Radarr/Sonarr own the files). Cache and transcode segments on the dedicated host dir, matching the existing `TranscodingTempPath`. |
| devices | `JELLYFIN_RENDER_DEVICE` (`/dev/dri/renderD128`) | Only the render node; `card0` (DRM master) is not passed. The init fixes the node's permissions inside the container. |
| `JELLYFIN_PublishedServerUrl` | `https://jellyfin.<domain>` | Advertised to clients. |
| healthcheck | `GET /health`, 3 min start period | Answers while startup tasks still run. |
| memory limit | 4 GB | ffmpeg being OOM-killed mid-playback beats a NAS-wide OOM. |
| router | `jellyfin.<domain>`, `media-headers` | Not published outside the LAN today. No rate limit: streams issue many range requests. |

## Set once in the UI

| Where | Expected |
|---|---|
| Dashboard > Libraries | `Movies` (type Movies) with the single folder `/data/movies`; `Shows` (type Shows) with `/data/tv`. Nothing pointing at `/data` or a torrents folder. |
| Library options | Metadata savers / "Save artwork into media folders" / NFO off; trickplay "save next to media" off. The library is read-only; anything that writes next to the media fails. Real-time monitoring on is fine. |
| Dashboard > Playback > Transcoding | Hardware acceleration `Intel QuickSync (QSV)`, device `/dev/dri/renderD128`, hardware decoding for H264, HEVC, VC1 (plus 10-bit HEVC/VP9), hardware encoding on, HEVC encoding off, tone mapping off, Transcoding path `/config/cache/transcodes` (default). This is what `encoding.xml` holds today; leave it. |
| Dashboard > Networking | Known proxies: the `homeserver` subnet (e.g. `172.22.0.0/16`, a CIDR, not the hostname `traefik`); LAN networks: your LAN CIDR; Published server URL `https://jellyfin.<domain>`; Base URL empty; UPnP off; Remote access can stay enabled (Traefik is the only way in). |
| Users | Your admin user with a password. Optional: a `Kids` user with library access limited to a kids library and a parental rating cap (see the note below). |
| Dashboard > Plugins | Optional: OpenSubtitles for on-demand fetches. Bazarr does the automatic work. |

Kids profile (optional): put kids content in its own tree (`data/kids/movies`, `data/kids/tv`
as extra Radarr/Sonarr root folders, mounted read-only here), add a `Kids` library on it,
and a `Kids` user restricted to that library with a max parental rating. Combine with a
Google TV kids profile on the Chromecast.

## Left at defaults on purpose

* Scheduled tasks (library scan, chapter images, trickplay) and their intervals.
* Metadata providers (TMDb/TVDb) and image fetchers.
* Transcoding quality (CRF 23/28, preset auto), throttling off, segment deletion off.
* No SSL in Jellyfin: TLS terminates at Traefik.

## Verify

```sh
docker logs jellyfin 2>&1 | grep -i "permissions for /dev/dri"          # "... are good"
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/vainfo | head -8           # Intel iHD driver, VAProfile list
docker exec jellyfin grep -oE "<(HardwareAccelerationType|VaapiDevice|TranscodingTempPath)>[^<]*" /config/encoding.xml
docker exec jellyfin touch /data/movies/x 2>&1 | grep -q "Read-only" && echo "library is read-only"
```
Play something that must transcode (force a low bitrate in the client): Dashboard shows the
stream as transcoding with "(HW)", and `docker logs jellyfin` shows an ffmpeg line with `qsv`.

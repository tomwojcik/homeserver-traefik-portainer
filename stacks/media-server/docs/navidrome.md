# Navidrome (music streaming)

Serves `/data/music` over the Subsonic API and its own web UI. Use a Subsonic client app
(Symfonium, Substreamer, Feishin, DSub) pointed at `https://navidrome.<domain>`.

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `user` / `read_only` / `cap_drop` | `PUID:PGID`, read-only, ALL dropped | Navidrome needs no root and no capabilities; `/tmp` is a tmpfs. |
| mounts | `navidrome/` at `/data`; `data/music` at `/music:ro` | `/data` is Navidrome's own database and cache (not the media `/data`). The library is read-only: Navidrome never writes tags. |
| `ND_SCANSCHEDULE` | `1h` | New Lidarr imports show up within the hour; trigger a scan from the UI for immediate results. |
| healthcheck | `GET /ping` | |
| router | `navidrome.<domain>`, `media-headers` | |
| image | `0.64.2` | Pinned. |
| host dir | `/volume1/docker/media-server/navidrome` owned by `PUID:PGID` | Create it before the first deploy. |

## Set once in the UI

| Where | Expected |
|---|---|
| First visit | Create the admin user immediately after the first deploy: until then anyone who can reach the URL can claim it. |
| Personal > Settings | Per user: language/theme as you like. Other users via Settings > Users. |
| Subsonic apps | Server URL `https://navidrome.<domain>` (public URL: apps run outside the Docker network), user and password. |

## Same library in Jellyfin

Jellyfin mounts the same `data/music` read-only (library type `Music`, see [jellyfin.md](jellyfin.md)).
Navidrome is for Subsonic apps; Jellyfin is the one to use for Chromecast / Google TV playback.
Both only read the files, so running both costs nothing but an extra scan.

## Left at defaults on purpose

* Transcoding stays on the defaults (clients request what they need).
* No scrobbling (Last.fm/ListenBrainz) configured; per-user opt-in in the UI.

## Verify

```sh
docker exec navidrome wget -qO- http://localhost:4533/ping      # pong
```
In the UI: the library shows the artists Lidarr imported; Settings > Users has only the users you created.

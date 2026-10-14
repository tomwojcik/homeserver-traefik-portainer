# Lidarr (music)

Identical model to Radarr; only the differences are spelled out.

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `user` / `read_only` / `cap_drop` | `PUID:PGID`, read-only, ALL dropped | LinuxServer non-root + read-only modes. |
| mounts | `/config`; `data` at `/data` | Staging (`/data/torrents`) and library (`/data/music`) on ONE mount so imports are hardlinks. |
| healthcheck | `GET /ping` | Anonymous readiness endpoint. |
| router | `lidarr.<domain>`, `media-headers` | |
| image | `3.1.0.4875-ls43` | Pinned. |

## Set once in the UI: Media Management

| Setting | Value | Why |
|---|---|---|
| Media Management > Rename Tracks | on | Consistent file names on import. |
| Media Management > Standard Track Format | `{Album Title} ({Release Year})/{Artist Name} - {Album Title} - {track:00} - {Track Title}` | Readable; Navidrome reads the tags, not the names. |
| Media Management > Artist Folder Format | `{Artist Name}` | |
| Media Management > Recycling Bin | `/data/recycle/music`, cleanup 14 days | Safety net for upgrades and deletions. |
| Media Management > Use Hardlinks | on | Zero-copy import. |
| Media Management > Import Extra Files | on, `lrc,cue,jpg,png` | Keep lyrics, cue sheets and cover art. |
| Media Management > Delete empty folders | on | Clean staging after import moves. |
| Metadata Profiles | Standard (Album); drop Singles/EPs/Live/Compilation types you do not want | Otherwise every artist pulls in hundreds of releases. |
| Root folder | Settings > Media Management > Root Folders > Add: path `/data/music`, name `Music`, your default quality and metadata profiles | Not created automatically. Until it exists, Add Artist fails with "Invalid Path" / "Root folder '' does not exist". The folder must exist on the host and be owned by `PUID:PGID`. |

## Set once in the UI: the rest

| Where | Expected |
|---|---|
| Settings > General > Security | Authentication `Forms`, Authentication Required **`Enabled`**; the password and its confirmation must match or the form is rejected. |
| Settings > Download Clients | qBittorrent: host **`gluetun`**, port `8080`, WebUI credentials, category `lidarr`, Remove Completed on. **No** Remote Path Mapping. |
| Settings > Indexers | Only what Prowlarr pushes (Prowlarr > Settings > Apps > add Lidarr). |
| Settings > Profiles | Defaults, quality profile of your choice (e.g. FLAC preferred, MP3 320 accepted). |
| Artists | Every artist path under `/data/music/<Artist>`; none under `/data/torrents`. |

## Left at defaults on purpose

* Metadata comes from Lidarr's hosted metadata server (MusicBrainz based); it is occasionally
  slow or down, which looks like failing artist searches. Retry later; nothing to fix here.
* Backups: weekly to `/config/Backups`.
* Lists: none. Tag writing: Lidarr writes tags on import; files are not re-tagged afterwards.

## Verify

```sh
docker exec lidarr curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8686/ping      # 200
```
In the UI: System > Status has no warnings; Settings > Download Clients > Test green.

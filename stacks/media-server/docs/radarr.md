# Radarr (movies)

Identical model to Sonarr; only the differences are spelled out.

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `user` / `read_only` / `cap_drop` | `PUID:PGID`, read-only, ALL dropped | LinuxServer non-root + read-only modes. |
| mounts | `/config`; `data` at `/data` | Staging (`/data/torrents`) and library (`/data/movies`) on ONE mount so imports are hardlinks. |
| healthcheck | `GET /ping` | Anonymous readiness endpoint. |
| router | `radarr.<domain>`, `media-lan-only` + `media-headers` | LAN only. |
| image | `6.3.0.10514-ls315` | Pinned. |

## Versioned (apply script) — `config/radarr.json`

| Setting | Value | Why |
|---|---|---|
| Naming > Rename Movies | on | Files get a consistent name on import; existing files only when you run Rename. |
| Naming > Standard Movie Format | `{Movie Title} ({Release Year}) {Quality Full}` | Readable, quality visible. |
| Naming > Movie Folder Format | `{Movie Title} ({Release Year})` | Matches the existing folders. |
| Naming > Colon Replacement | `smart` | `Mission: Impossible` -> `Mission - Impossible`. |
| Media Management > Recycling Bin | `/data/recycle/movies`, cleanup 14 days | Safety net for upgrades and deletions. |
| Media Management > Use Hardlinks | on | Zero-copy import. |
| Media Management > Import Extra Files | on, `srt,sub,idx` | Keep shipped subtitles. |
| Media Management > Delete empty folders | on | Clean staging after import moves. |
| Media Management > Rename folders automatically | off | Folder names stay stable for Jellyfin. |
| Root folder | `/data/movies` | Created if missing. |

## Set once in the UI

| Where | Expected |
|---|---|
| Settings > General > Security | Authentication `Forms`, Authentication Required **`Enabled`**. |
| Settings > Download Clients | qBittorrent: host **`gluetun`**, port `8080`, WebUI credentials, category `radarr`, Remove Completed on. **No** Remote Path Mapping. |
| Settings > Indexers | Only what Prowlarr pushes. |
| Settings > Profiles | Defaults (Recyclarr declined for now). |
| Adding movies (and Seerr's Radarr settings) | Minimum Availability `Released`: Radarr does not search before the release date, which otherwise looks like "requested but nothing happens". |
| Movies | Every movie path under `/data/movies/<Movie Title (Year)>`; none under `/data/torrents`. |

## Left at defaults on purpose

* Quality definitions and profiles.
* Backups: weekly to `/config/Backups`.
* Lists: none.

## Verify

```sh
docker exec radarr curl -s -o /dev/null -w '%{http_code}\n' http://localhost:7878/ping      # 200
make apply-media-config-dry   # every radarr line reads "up to date"
```
In the UI: System > Health has no warnings; Settings > Download Clients > Test green; Movies
filtered by "Missing" contains only titles that are genuinely not on disk.

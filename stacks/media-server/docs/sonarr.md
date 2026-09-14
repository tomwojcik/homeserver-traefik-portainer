# Sonarr (TV)

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `user` / `read_only` / `cap_drop` | `PUID:PGID`, read-only, ALL dropped | LinuxServer non-root + read-only modes. |
| mounts | `/config`; `data` at `/data` | Staging (`/data/torrents`) and library (`/data/tv`) on ONE mount so imports are hardlinks. |
| healthcheck | `GET /ping` | Anonymous readiness endpoint. |
| router | `sonarr.<domain>`, `media-headers` | |
| image | `4.0.19.2979-ls323` | Includes the reverse-proxy authentication-bypass fix (>= 4.0.16). |

## Set once in the UI: Media Management and Naming

| Setting | Value | Why |
|---|---|---|
| Naming > Rename Episodes | on | Files get a consistent name on import. Existing files are only renamed when you run Rename in the UI. |
| Naming > Standard / Daily / Anime format | `{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}` (daily uses `{Air-Date}`) | Readable, sortable, quality visible. |
| Naming > Series Folder / Season Folder / Specials | `{Series Title}` / `Season {season}` / `Specials` | Matches the folders that already exist; changing the season format would split seasons across `Season 1` and `Season 01`. |
| Naming > Multi-Episode Style | `5` (Prefixed Range) | `S01E01-E02`. |
| Media Management > Recycling Bin | `/data/recycle/tv`, cleanup 14 days | Upgrades and deletions go here first: a safety net against losing a file. |
| Media Management > Use Hardlinks | on | Zero-copy import; the seeding copy stays in `/data/torrents`. |
| Media Management > Import Extra Files | on, `srt,sub,idx` | Subtitles shipped with a release are kept; Bazarr fills the gaps. |
| Media Management > Delete empty folders | on | Emptied torrent folders vanish after an import move. |
| Media Management > Propers and Repacks | `preferAndUpgrade` (existing default) | Kept as it was. |
| Root folder | `/data/tv` | Created if missing. |
| Season folders | on for every series | Per-season directories. |

## Set once in the UI: the rest

| Where | Expected |
|---|---|
| Settings > General > Security | Authentication `Forms`, Authentication Required **`Enabled`** (never "Disabled for Local Addresses": behind Traefik every request looks local). |
| Settings > Download Clients | One qBittorrent entry: host **`gluetun`**, port `8080`, username/password of the WebUI, category `tv-sonarr`, Remove Completed on (default). **No** Remote Path Mapping: both sides see `/data/torrents`. |
| Settings > Indexers | Empty apart from what Prowlarr pushes (they show "(Prowlarr)"). |
| Settings > Profiles | Defaults, unless you build your own. The community TRaSH profiles via Recyclarr were considered and declined for now. |
| Series | Every series path under `/data/tv/<Series Title>`; nothing under `/data/torrents`. |

## Left at defaults on purpose

* Quality definitions and profiles (see above).
* Backups: weekly to `/config/Backups`, 28 retained. Covered by the stack-level backup.
* Analytics/Sentry on: writes under `/config/Sentry`, harmless in non-root mode.
* `setPermissionsLinux` off: ownership is handled by the containers running as `PUID:PGID`.

## Verify

```sh
docker exec sonarr curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8989/ping      # 200
```
In the UI: System > Health has no warnings; Settings > Download Clients > Test is green; a
series page shows a `Season N` folder layout under `/data/tv`.

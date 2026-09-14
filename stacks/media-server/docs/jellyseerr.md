# Seerr (formerly Jellyseerr)

The request front-end. The container is still named `jellyseerr` and served at
`jellyseerr.<domain>` so nothing had to change for users; the image is
`ghcr.io/seerr-team/seerr`, the maintained successor of `fallenbagel/jellyseerr`.

## Compose / template

| Setting | Value | Why |
|---|---|---|
| image | `ghcr.io/seerr-team/seerr:v3.4.1` | The old image stopped at 2.7.3 (Aug 2025) and ran as root. |
| `user` | `PUID:PGID` (the image's own `node` user is uid 1000) | `/app/config` on the host must be owned by that uid; the old image left root-owned files, hence the chown in the migration. |
| `init: true` | | The new image ships no init process. |
| `cap_drop` | ALL | Nothing needed. |
| mounts | `jellyseerr` at `/app/config` | Unchanged path: the database migrates in place on first start (one way). |
| healthcheck | `GET /api/v1/status` via wget | The image has no healthcheck and no curl. |
| router | `jellyseerr.<domain>`, `media-headers` + `media-ratelimit` | Not published outside the LAN today. The rate limit is a per-IP flood backstop, not a brute-force limiter. If it is ever exposed: key the limit on `Cf-Connecting-IP` and put Cloudflare Access in front. |

## Set once in the UI

| Where | Expected |
|---|---|
| Settings > Jellyfin | Hostname `jellyfin`, port `8096`, SSL off, external URL `https://jellyfin.<domain>`. Libraries `Movies` and `Shows` enabled for sync. |
| Settings > Services > Radarr | One server, default, hostname `radarr`, port `7878`, SSL off, Radarr's API key, Quality Profile of your choice, **Root Folder `/data/movies`**, Minimum Availability `Released`, "Enable Scan" on. |
| Settings > Services > Sonarr | One server, default, hostname `sonarr`, port `8989`, Sonarr's API key, Quality Profile, **Root Folder `/data/tv`**, Season Folders on, "Enable Scan" on. |
| Settings > Users | Your own user with auto-approve; other users (family) with request limits as you see fit. |

Container names everywhere. A public hostname here would loop through Traefik for no
benefit.

## Left at defaults on purpose

* Jellyfin sync interval and "recently added" scan.
* Notifications: none configured.
* Application URL / base path: empty (served at the root of its hostname).

## Verify

```sh
docker exec jellyseerr wget -qO- http://localhost:5055/api/v1/status      # JSON with the version
docker logs jellyseerr 2>&1 | grep -E "Server ready|EACCES"               # ready; no permission errors
docker exec jellyseerr id -u                                              # 1000
```
In the UI: Settings > Jellyfin, Radarr and Sonarr each "Test" green; a request for a
released movie appears in Radarr under `/data/movies` and in qBittorrent within minutes.

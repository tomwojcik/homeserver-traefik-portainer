# Complete Media Server with VPN

One Portainer stack: VPN-protected torrenting, automated TV/movie management, subtitles,
streaming and requests. LAN-only behind Traefik.

## Services

| Service | Role | URL | Notes |
|---|---|---|---|
| gluetun | WireGuard VPN with kill switch | (none) | qBittorrent runs inside its network namespace |
| qbittorrent | Torrent client | `qbittorrent.<domain>` | Router lives on gluetun; only `/data/torrents` mounted |
| deunhealth | Watchdog | (none) | Restarts qbittorrent when it loses gluetun's network |
| flaresolverr | Cloudflare-challenge solver for Prowlarr | (none, API only) | Stack-private network |
| prowlarr | Indexer manager | `prowlarr.<domain>` | Syncs indexers to Sonarr/Radarr |
| sonarr | TV shows | `sonarr.<domain>` | Root folder `/data/tv` |
| radarr | Movies | `radarr.<domain>` | Root folder `/data/movies` |
| bazarr | Subtitles | `bazarr.<domain>` | English + Polish (see manual_migration.md) |
| jellyfin | Streaming | `jellyfin.<domain>` | Libraries `/data/movies`, `/data/tv` read-only; Intel QSV transcoding |
| jellyseerr | Requests (Seerr) | `jellyseerr.<domain>` | Container name kept from Jellyseerr |

Every UI keeps its own login. Traefik additionally restricts all of them to `LAN_CIDR`
(private ranges by default) and adds security headers.

## Data layout

All host paths live under `/volume1/docker/media-server/` and are bind mounts (nothing is
created by Docker; see the prerequisites below).

| Host | Container path | Purpose |
|---|---|---|
| `data/torrents/{movies,tv,incomplete}` | `/data/torrents/...` | qBittorrent staging, per category |
| `data/movies/<Movie (Year)>/` | `/data/movies` | Radarr library, Jellyfin "Movies" |
| `data/tv/<Series>/Season N/` | `/data/tv` | Sonarr library, Jellyfin "Shows" |
| `data/recycle/{movies,tv}` | `/data/recycle/...` | Sonarr/Radarr recycle bin, 14 days |
| `<app>/` | `/config` | Per-app state (`jellyseerr/` -> `/app/config`) |
| `gluetun/config`, `gluetun/secrets` | `/gluetun`, `/run/secrets` | Server list; optional WireGuard key file |
| `jellyfin-cache/` | `/config/cache` | Jellyfin cache and transcode segments |

Sonarr and Radarr see torrents and library on ONE mount, so imports are hardlinks
(instant, no extra space) and the seeding copy stays in `data/torrents`.

## Prerequisites (Synology, as root)

1. Boot task (DSM Task Scheduler, root, on boot-up AND every 5 minutes) with the script in
   `known-issues.md`: loads the TUN module and starts qbittorrent once gluetun is healthy.
2. `chown -R 1000:1000 /volume1/docker/media-server` (use your PUID:PGID). The apps run as
   that user and cannot fix ownership themselves.
3. Optional: put the WireGuard private key in
   `/volume1/docker/media-server/gluetun/secrets/wireguard_private_key` (directory `root:root`,
   `chmod 700`) and leave `WIREGUARD_PRIVATE_KEY` empty in the form. The file takes precedence
   over the form field; to rotate the key, change the file.
4. Jellyfin hardware transcoding needs `/dev/dri/renderD128` (or set `JELLYFIN_RENDER_DEVICE`).
   On a model without an iGPU, delete the `devices:` block from the jellyfin service.
5. Fresh install (no existing data): create the tree and own it before the first start, then
   set a permanent qBittorrent password (a temporary one is printed to `docker logs qbittorrent`
   until you do) and finish the *arr authentication wizards:
   ```sh
   cd /volume1/docker/media-server
   mkdir -p data/torrents/{movies,tv,incomplete} data/movies data/tv data/recycle/{movies,tv} gluetun/config jellyfin-cache
   chown -R 1000:1000 .
   ```
6. Backups: snapshot or tar `/volume1/docker/media-server` excluding `data/torrents` and
   `jellyfin-cache` on a schedule (DSM Snapshot Replication or the Duplicati stack). App
   databases migrate forward only, so snapshot before every image bump.

Upgrading an existing deployment from the old layout: follow `manual_migration.md`.
Expected configuration of every service, in and out of the compose file: [`docs/`](docs/README.md).

## Template variables

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_DOMAIN` | | Your domain |
| `VPN_SERVICE_PROVIDER` | `surfshark` | Gluetun provider (WireGuard-capable only) |
| `WIREGUARD_PRIVATE_KEY` | | Leave empty if you use the key file |
| `WIREGUARD_ADDRESSES` | | e.g. `10.14.0.2/16` |
| `SERVER_COUNTRIES` | `Switzerland,Iceland` | Server pool (gluetun spelling) |
| `GLUETUN_IMAGE` | pinned digest | Exact gluetun build; bump deliberately |
| `LAN_CIDR` | `192.168.0.0/16,10.0.0.0/8` | Who may open the UIs. Never add `172.16.0.0/12` (Docker bridge) |
| `JELLYFIN_RENDER_DEVICE` | `/dev/dri/renderD128` | GPU render node |
| `PUID` / `PGID` | `1000` | Owner of all data |
| `TZ` | `UTC` | Timezone |

## In-app configuration

Versioned in `config/*.json` and pushed with `make apply-media-config` (see
`scripts/apply_media_config.py` for the required environment variables). Covers qBittorrent
paths/categories/`tun0` binding/WebUI hardening, Sonarr and Radarr naming, recycle bin,
hardlinks, season folders, and Prowlarr's app URLs.

Everything else is set once in each UI (full per-service reference in [`docs/`](docs/README.md)):

* **Sonarr / Radarr**: download client host `gluetun`, port `8080`, no remote path mapping;
  Authentication Required = Enabled.
* **Prowlarr**: Apps `http://sonarr:8989`, `http://radarr:7878`, Prowlarr server
  `http://prowlarr:9696`; FlareSolverr proxy `http://flaresolverr:8191`, tagged on the
  indexers that need it; Authentication Required = Enabled.
* **Bazarr**: Sonarr `sonarr:8989`, Radarr `radarr:7878`, no path mappings; languages profile
  en+pl; providers napiprojekt, podnapisi, opensubtitles.com.
* **Jellyfin**: libraries `/data/movies`, `/data/tv` (read-only: keep "save artwork/NFO into
  media folders" and trickplay-next-to-media off, do not delete media from Jellyfin); Known
  proxies = the `homeserver` subnet (`docker network inspect homeserver`); UPnP off;
  Playback > Transcoding = Intel QuickSync.
* **Seerr**: Jellyfin `jellyfin:8096`, Sonarr `sonarr:8989`, Radarr `radarr:7878`, root folders
  `/data/tv` and `/data/movies`.

Containers always address each other by container name. The public hostnames are for
browsers; app-to-app requests through them hairpin via Traefik from a bridge address and are
rejected by the LAN gate.

## Security model

* Only torrent transfer is VPN'd (Gluetun firewall = kill switch; `docker stop gluetun` must
  stall qbittorrent). Prowlarr, FlareSolverr and the *arrs use the NAS IP.
* No host ports are published. Everything goes through Traefik with a wildcard certificate.
* LinuxServer apps (qbittorrent, prowlarr, sonarr, radarr, bazarr) run as `PUID:PGID`,
  read-only root filesystem, all capabilities dropped. Gluetun keeps `NET_ADMIN`, `NET_RAW`,
  `CHOWN`, `DAC_OVERRIDE`; its control server is bound to loopback. Jellyfin keeps the handful
  of capabilities its init needs. Seerr runs as uid 1000.
* Known limitation: every service still shares the flat `homeserver` bridge with the other
  stacks, so their ports are reachable at L3 from any container on it. That is why every app
  keeps its own login. See `known-issues.md` item 5.
* Images are pinned. Memory limits (the DSM kernel supports neither `cpus` nor `pids` limits), log rotation and health checks on every service.
* FlareSolverr is unauthenticated and drives a sandbox-less Chromium, so it is isolated on
  `media-internal` where only prowlarr can reach it.

## Troubleshooting

* `docker logs gluetun`: expect "Wireguard setup is complete" then a passing health check.
  `docker exec gluetun cat /tmp/gluetun/ip` shows the VPN address.
* qbittorrent unhealthy after a gluetun restart is normal for up to ~3 minutes; deunhealth
  restarts it. If it stays down after a NAS reboot, run the boot script by hand.
* Jellyfin transcoding: see `known-issues.md` item 3.
* A UI returns 403: your client is outside `LAN_CIDR`, or Traefik sees a bridge address
  (`docker logs traefik`, field `ClientAddr`).

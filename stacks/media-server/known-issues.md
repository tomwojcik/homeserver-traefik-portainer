1. `/dev/net/tun` does not exist after a reboot (gluetun fails with "cannot Unix Open TUN device file"). The module ships with DSM (`/lib/modules/tun.ko`) but is not loaded. Create this script and run it from DSM Task Scheduler as root, both on boot-up AND every 5 minutes (idempotent, safe to re-run). It also covers item 2:
```shell
#!/bin/bash
# 1. TUN device for gluetun
[ -f /lib/modules/tun.ko ] && { lsmod | grep -q '^tun' || insmod /lib/modules/tun.ko; }
mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200
chmod 600 /dev/net/tun

# 2. qBittorrent boot race: Docker restores containers without honouring depends_on. If
#    qbittorrent starts before gluetun's network namespace exists it fails to start and stays
#    stopped. Wait (up to 10 min) for gluetun to be healthy, then start qbittorrent (no-op if running).
nohup setsid bash -c '
  for _ in $(seq 1 60); do
    if [ "$(docker inspect -f "{{.State.Health.Status}}" gluetun 2>/dev/null)" = "healthy" ]; then
      docker start qbittorrent >/dev/null 2>&1
      break
    fi
    sleep 10
  done
' >/dev/null 2>&1 &
```
2. qBittorrent lost its network whenever gluetun restarted (it kept the old namespace) and failed to start after a NAS reboot or a Container Manager restart if gluetun was not up yet. The first case is now auto-healed: qbittorrent's healthcheck detects the dead namespace and the `deunhealth` container restarts it. The second case is handled by the script above (boot + every 5 minutes), because Docker never retries a container whose start failed. Recovery by hand: `docker start qbittorrent`. qbittorrent is bound to gluetun's container ID: only ever recreate gluetun through a stack redeploy (never "Recreate" it alone in Portainer), otherwise qbittorrent cannot start until the stack is redeployed. In Sonarr/Radarr the download client host is `gluetun`, port `8080` (the name `qbittorrent` does not resolve, it has no network of its own).
3. Jellyfin hardware acceleration: the compose passes only `/dev/dri/renderD128` (set `JELLYFIN_RENDER_DEVICE` if yours differs; `ls -l /dev/dri`). The LinuxServer image fixes the node's permissions inside the container at start, so the old host-side `chmod 666` boot script is no longer needed. Verify after a (re)start:
```shell
docker logs jellyfin 2>&1 | grep -i "permissions for /dev/dri"      # expect "... are good"
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/vainfo | head          # lists VAAPI profiles = GPU usable
```
Then Dashboard > Playback > Transcoding: Hardware acceleration `Intel QuickSync (QSV)` (or `VAAPI`), device `/dev/dri/renderD128`, Transcoding path `/config/cache/transcodes` (the default; the `jellyfin-cache` host dir is mounted there, leave it unchanged). If the log does NOT say the permissions are good, run `chmod 666 /dev/dri/renderD128` on the host as a fallback and restart jellyfin. A stream that is transcoding shows "(HW)" next to the video codec on the Dashboard's active streams, and the ffmpeg line in the log contains `qsv` or `vaapi`.

4. Every LinuxServer app (qbittorrent, prowlarr, sonarr, radarr, bazarr) logs a "read-only / non-root mode is not officially supported" banner at start. Expected: they run in LinuxServer's documented non-root + read-only modes on purpose. If one misbehaves after an image bump, drop `read_only: true` for that service first.
5. Known limitations that need the ROOT stack (out of this stack's scope): (a) all services share the flat `homeserver` bridge, so other stacks can reach sonarr:8989, radarr:7878, prowlarr:9696, bazarr:6767, jellyfin:8096, jellyseerr:5055 and gluetun:8080 at L3; every app therefore keeps its own login. Full isolation needs a dedicated network that root Traefik also joins. (b) Traefik's access log records `apikey=` query strings; set `--accesslog.fields.names.RequestPath=redact` in the root compose. (c) The Traefik dashboard router has no auth middleware; attach `media-lan-only` or basicAuth to it. (d) On Docker below 28, a LAN host with a static route to `172.22.0.0/16` can reach container ports directly (see manual_migration.md step 1.4).
6. No VPN-down alerting. gluetun's control server is bound to loopback because it is unauthenticated on this build (any container could stop the VPN). To monitor it from Uptime Kuma, first create `gluetun/config/auth/config.toml` with a read-only apikey role (gluetun wiki: "Control server > Authentication"), then set `HTTP_CONTROL_SERVER_ADDRESS` back to `:8000`.
7. Resource limits on DSM's Docker (24.0.2): `memory` works; `cpus` makes container creation FAIL ("NanoCPUs can not be set, as your kernel does not support CPU CFS scheduler", removed repo-wide in 082b57f); `pids` is silently discarded ("Your kernel does not support pids limit capabilities ... PIDs limit discarded", verified with `docker run --rm --pids-limit 64 alpine true`). Only `memory` is used in this stack.
8. No IP allow-list on the routers, on purpose. It was tried (Traefik `ipAllowList` of private ranges): Synology's Docker proxies LAN connections through the host, so Traefik sees every LAN client as the bridge gateway (`172.22.0.1` here; first column of `docker logs traefik`), which locked the owner out (verified 2026-09-14). Allowing the gateway as a `/32` "works" but then the list cannot tell LAN from a future port-forward or tunnel either, and its only remaining effect was to break app-to-app requests that used the public hostnames (Radarr -> Prowlarr got 403). Removed. Access control is each app's own login, security headers stay, and nothing is published outside the LAN. If something is ever exposed, use Cloudflare Access (or a VPN into the LAN), not an IP list.
9. Traefik v3.0 on this engine sometimes misses Docker events: after a stack redeploy a healthy container can have no router (its hostname answers `404 page not found`). `docker restart traefik` re-lists every container. Check the Traefik dashboard's router list after each redeploy. A newer Traefik in the root compose may fix it (untested).

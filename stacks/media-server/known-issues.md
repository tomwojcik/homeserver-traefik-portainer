1. `/dev/net/tun` does not exist after a reboot (gluetun fails with "cannot Unix Open TUN device file"). The module ships with DSM (`/lib/modules/tun.ko`) but is not loaded. Create this script and run it from DSM Task Scheduler as root on boot-up (idempotent, safe to re-run). It also covers item 2:
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
(
  for _ in $(seq 1 60); do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' gluetun 2>/dev/null)" = "healthy" ]; then
      docker start qbittorrent >/dev/null 2>&1
      break
    fi
    sleep 10
  done
) &
```
2. qBittorrent lost its network whenever gluetun restarted (it kept the old namespace) and failed to start after a NAS reboot if gluetun was not up yet. The first case is now auto-healed: qbittorrent's healthcheck detects the dead namespace and the `deunhealth` container restarts it. The second case is handled by the boot script above. In Sonarr/Radarr the download client host is `gluetun`, port `8080` (the name `qbittorrent` does not resolve, it has no network of its own).
3. Jellyfin hardware acceleration: the compose passes only `/dev/dri/renderD128` (set `JELLYFIN_RENDER_DEVICE` if yours differs; `ls -l /dev/dri`). The LinuxServer image fixes the node's permissions inside the container at start, so the old host-side `chmod 666` boot script is no longer needed. Verify after a (re)start:
```shell
docker logs jellyfin 2>&1 | grep -i "permissions for /dev/dri"      # expect "... are good"
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/vainfo | head          # lists VAAPI profiles = GPU usable
```
Then Dashboard > Playback > Transcoding: Hardware acceleration `Intel QuickSync (QSV)` (or `VAAPI`), device `/dev/dri/renderD128`, Transcoding path `/transcode`. A stream that is transcoding shows "(HW)" next to the video codec on the Dashboard's active streams, and the ffmpeg line in the log contains `qsv` or `vaapi`.

Some trackers require captcha solving (in prowlarr). If so, add flaresolverr as a proxy.
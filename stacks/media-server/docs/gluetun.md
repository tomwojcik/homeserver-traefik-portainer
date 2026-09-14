# gluetun (VPN gateway) and deunhealth (watchdog)

gluetun has no UI and no state worth editing by hand. Its entire configuration is the
environment in the compose file, so this page is mostly "why each value".

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `VPN_SERVICE_PROVIDER` | `surfshark` (form) | Must be a WireGuard-capable gluetun provider. ExpressVPN is OpenVPN-only in gluetun and will not start. |
| `VPN_TYPE` | `wireguard` (hard-coded) | OpenVPN credentials are not wired; the old form dropdown offered a default that was not selectable. |
| `WIREGUARD_ADDRESSES` | e.g. `10.14.0.2/16` (form) | Interface address from the provider's WireGuard config. |
| `WIREGUARD_PRIVATE_KEY` | form field | The key lives in the Portainer stack environment (closed LAN; accepted). Rotate by editing the stack. |
| `SERVER_COUNTRIES` | `Switzerland,Iceland` (form) | Random server from this pool per start instead of anywhere in the world. Spelling must match `docker run --rm qmcgaw/gluetun format-servers -surfshark`. |
| `UPDATER_PERIOD` | `720h` | Refreshes the embedded server list monthly (persisted in `/gluetun/servers.json`). |
| `FIREWALL` | `on` | The kill switch. `FIREWALL_OUTBOUND_SUBNETS` stays **unset**: adding the LAN would let the torrent client reach DSM. |
| `DNS_SERVER` | `on` | gluetun's DNS-over-TLS forwarder inside the tunnel; qBittorrent's DNS never leaks. |
| `BLOCK_MALICIOUS` | `on` | Default blocklist in that forwarder. |
| `DNS_KEEP_NAMESERVER` | `off` | Do not keep Docker's resolver alongside the tunnel one. |
| `HTTPPROXY`, `SHADOWSOCKS` | `off` | Were on (proxy unauthenticated, logging every URL); nothing used them. |
| `HTTP_CONTROL_SERVER_ADDRESS` | `127.0.0.1:8000` | The control API is unauthenticated on this build and a PUT can stop the VPN; bound to loopback so no container on the bridge can reach it. |
| `TZ` | form | Log timestamps only. |
| image | `GLUETUN_IMAGE`, a digest of the master build | The last tagged release (v3.41.3) is from 2024. Bump by pasting a new `qmcgaw/gluetun@sha256:...` into the form. |
| capabilities | `NET_ADMIN`, `NET_RAW`, `CHOWN`, `DAC_OVERRIDE`; everything else dropped | Routes/tun/WireGuard, iptables, chown of files it writes under `/gluetun`. |
| healthcheck | image's own (5 s), `start_period: 60s` | The previous custom 1-minute wget check made qBittorrent wait a minute at every boot. |
| ports | none published | The qBittorrent WebUI is reached by Traefik over the bridge; gluetun's firewall accepts the local Docker subnet. |

## Left at defaults on purpose

* `WIREGUARD_MTU` (1400). Lowering it (e.g. 1320) is the usual remedy if the log shows several
  server rotations with DNS-over-TLS "connection reset" at startup. Try only if that becomes
  a nuisance.
* `HEALTH_*` (target `cloudflare.com:443`, restart VPN after 6 s of failure). This is gluetun's
  own auto-heal, independent of the Docker healthcheck.
* `VPN_PORT_FORWARDING` off: Surfshark has no port forwarding in gluetun. qBittorrent is a
  passive node (no inbound peers).
* `PUBLICIP_PERIOD`, `DOT_*`, `LOG_LEVEL` (info).

## deunhealth

Restarts any container carrying `deunhealth.restart.on.unhealthy=true` when Docker marks it
unhealthy (Docker itself never restarts on a failed healthcheck). Only qBittorrent carries
the label. Runs as root with the Docker socket read-only, no network, read-only filesystem,
no capabilities, pinned by digest. It only acts on *running* containers; a container whose
start failed is handled by the boot script (`../known-issues.md` item 1).

## Verify

```sh
docker logs gluetun 2>&1 | grep -E "Wireguard setup is complete|healthy|Public IP"
docker exec gluetun cat /tmp/gluetun/ip                          # VPN address, not your ISP's
docker exec gluetun wget -qO- --timeout=3 http://127.0.0.1:8000/v1/vpn/status   # works from inside...
docker exec prowlarr curl -s -m 3 http://gluetun:8000/v1/vpn/status || echo "control server not on the bridge (expected)"
docker stop gluetun && docker exec qbittorrent curl -s -m 5 https://1.1.1.1 || echo "kill switch holds"; docker start gluetun
```
After `docker restart gluetun`, `docker ps` should show qbittorrent unhealthy within ~3 min
and healthy again shortly after (deunhealth log: "restarted successfully").

# qBittorrent

Runs inside gluetun's network namespace: no network of its own, reached as host `gluetun`
port `8080` by other containers, and at `https://qbittorrent.<domain>` (LAN only) by you.

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `network_mode` | `service:gluetun` | Everything it sends goes through the VPN or nowhere (kill switch). |
| `user` / `read_only` / `cap_drop` | `PUID:PGID`, read-only, ALL dropped | LinuxServer's documented non-root + read-only modes; `/run` and `/tmp` on tmpfs. `PUID`/`PGID` env are not set (ignored in this mode). |
| `WEBUI_PORT` | `8080` | Must equal the Traefik service port on gluetun's labels. |
| `TORRENTING_PORT` | `6881` | Fixed listen port. Not published on the host, not forwarded by the VPN: inbound peers cannot connect (expected with Surfshark). |
| mounts | `/config`; `data/torrents` at `/data/torrents`; the same dir at `/downloads` (legacy alias) | Only the staging tree; the library is not visible here. Remove the alias once no torrent has a `/downloads/...` save path. |
| healthcheck | `eth0` present + WebUI listening | Detects the lost namespace after a gluetun restart; deunhealth then restarts the container. |
| `stop_grace_period` | `5m` | libtorrent flushes resume data on stop; a 10 s kill causes rechecks after every redeploy. |

## Set once in the UI: preferences

| Preference | Value | Why |
|---|---|---|
| `save_path` | `/data/torrents` | Default for uncategorised torrents. |
| `temp_path` / `temp_path_enabled` | `/data/torrents/incomplete`, on | Incomplete downloads never sit in a category folder the *arrs watch. |
| `auto_tmm_enabled` + the three `*_tmm_enabled` | on | Category decides the save path (Automatic Torrent Management). |
| categories | `radarr` -> `/data/torrents/movies`, `tv-sonarr` -> `/data/torrents/tv` | Names match what Radarr/Sonarr are configured with; only the paths changed. |
| `listen_port` / `random_port` / `upnp` | `6881`, off, off | Fixed port; UPnP/NAT-PMP do nothing through a VPN. |
| `current_network_interface` | `tun0` | Second kill switch: if gluetun's firewall were ever wrong, qBittorrent still only uses the tunnel. |
| `encryption` | `0` (prefer) | Compatible with the most peers. |
| `anonymous_mode` | off | Public-tracker-friendly; turn on only if every tracker is public. Private trackers may reject anonymous mode. |
| `autorun_enabled`, `autorun_on_torrent_added_enabled` | off | "Run external program" is a remote-code-execution surface if the WebUI is ever reached. |
| `web_ui_host_header_validation_enabled` / `web_ui_domain_list` | on, `qbittorrent.<domain>;gluetun` | DNS-rebinding defence. `gluetun` must stay: Sonarr/Radarr send `Host: gluetun:8080`. |
| `web_ui_csrf_protection_enabled`, `web_ui_clickjacking_protection_enabled`, `web_ui_secure_cookie_enabled` | on | Behind HTTPS via Traefik. |
| `web_ui_reverse_proxy_enabled` / `web_ui_reverse_proxies_list` | on, the `homeserver` subnet (`172.22.0.0/16`) | Logs and bans use the real client IP from `X-Forwarded-For`, trusted only from Traefik's subnet. |
| `bypass_local_auth`, `bypass_auth_subnet_whitelist_enabled` | off | Behind Traefik every request looks local; a bypass would disable auth for everyone. |
| `web_ui_max_auth_fail_count` / `web_ui_ban_duration` / `web_ui_session_timeout` | 5 / 3600 / 3600 | Brute-force ban and session expiry. |

The keys above are the WebAPI names (Options dialog fields map one-to-one). Set them in
Options > Downloads / Connection / Advanced / WebUI; categories via the sidebar.

## Set once in the UI: the rest

* WebUI username and a permanent password (a temporary one is printed to
  `docker logs qbittorrent` on every start until you set one).
* Seeding limits (Options > BitTorrent > Seeding Limits): your choice; the *arrs remove a
  torrent after import only once qBittorrent reports its seeding goal reached.

## Left at defaults on purpose

* DHT, PeX, LSD on: harmless through the VPN; private trackers disable them per torrent.
* Connection limits, disk cache, pre-allocation: defaults are fine on a NAS.
* Alternative WebUI: none.

## Verify

```sh
docker exec qbittorrent cat /proc/net/dev | grep -c tun0                       # 1: tunnel interface present in the namespace
docker exec sonarr curl -s -o /dev/null -w '%{http_code}\n' http://gluetun:8080/api/v2/app/webapiVersion   # 403 = host accepted, auth required; 401 = Host header rejected
docker exec qbittorrent curl -s -m 5 https://ipinfo.io/ip                       # VPN address
```
In the WebUI: Options > Advanced > Network interface shows `tun0`; Options > Downloads shows
`/data/torrents`; categories `radarr` and `tv-sonarr` show their save paths.

# Media server: manual migration steps

Steps that cannot be done from the compose file. Do them in order, once, when deploying the
reworked stack from branch `media-server-rework`. Nothing here deletes media: every file
operation is a rename on the same volume, and the two optional cleanup steps only *move*
folders into a holding directory.

## Why

* Jellyfin has been scanning the torrent staging directory since 2026-01-18 (commit 55f0a46
  mounted `downloads` as Jellyfin's `/data`). It shows the raw torrent folder and the
  imported folder as two movies, and has no TV library at all.
* Every Radarr movie and Sonarr series has its path under `/downloads/...`, the original
  root folder was deleted, and Jellyseerr adds new requests under `/downloads`. Files that
  live in `media/movies` and `media/tv` (to become `data/movies`, `data/tv`) are invisible to Radarr and Sonarr, which is why
  requests for them never produce a download.
* `downloads` and `media` are two separate bind mounts, so hardlinks fail and every import
  is a full copy.

Target layout (host `media/` is renamed to `data/` and becomes the single `/data` root inside the containers; gluetun's state moves into the stack directory):

| Host | Container | Used by |
|---|---|---|
| `data/torrents/{movies,tv,incomplete}` | `/data/torrents/...` | qBittorrent (writes), Sonarr/Radarr (import from) |
| `data/movies/<Movie (Year)>/` | `/data/movies` | Radarr (writes), Bazarr, Jellyfin (read-only) |
| `data/tv/<Series>/Season N/` | `/data/tv` | Sonarr (writes), Bazarr, Jellyfin (read-only) |
| `data/recycle/{movies,tv}` | `/data/recycle/...` | Radarr/Sonarr recycle bin (14 days) |

Root folders `/data/movies` and `/data/tv` already exist in Radarr and Sonarr and do not change.

## 0. Before touching anything

1. Plan the backup: it is taken in section 2, **after the stack is stopped** (a tar of live
   SQLite databases is not a valid rollback point). Do NOT run `make create-volumes` or
   pre-create `data/` before section 3: the renames there must not find their targets.
2. Note the current Jellyfin watched/favourite state you care about. Library paths change, so
   Jellyfin will treat movies as new items (watched status resets). Media files are untouched.
3. Have ready: the WireGuard private key, qBittorrent WebUI user/password, Sonarr and Radarr API
   keys (Settings > General).

## 1. NAS prerequisites (SSH as root)

1. **Boot task**: DSM Control Panel > Task Scheduler, user `root`, with the script from
   `known-issues.md` item 1 (loads the TUN module, creates `/dev/net/tun`, starts qbittorrent
   once gluetun is healthy). Create it TWICE: as a Triggered Task (Boot-up) and as a Scheduled
   Task every 5 minutes. The recurring run covers the case where Container Manager restarts
   (DSM update, package update) and qbittorrent fails to start because gluetun was not up yet:
   Docker does not retry a failed start. Run it once now as well.
2. **Ownership**: the containers now run as your user instead of root.
   ```sh
   chown -R 1000:1000 /volume1/docker/media-server
   ```
   Metadata only; takes a few minutes on 1.5 TB.
3. **Docker version** (decides whether a LAN host could route straight to container IPs,
   bypassing Traefik; fixed in Docker 28):
   ```sh
   docker version --format '{{.Server.Version}}'; iptables -S FORWARD | head -1
   ```
   If the version is below 28 or the FORWARD policy is not DROP, add this line to the boot
   script (replace `eth0` with the NAS LAN interface):
   `iptables -I DOCKER-USER -i eth0 -m conntrack --ctstate NEW --ctorigdst 172.16.0.0/12 -j DROP`

## 2. Stop the stack and take the backup

Portainer > Stacks > media server > Stop. Confirm with `docker ps` that gluetun, qbittorrent,
flaresolverr, prowlarr, sonarr, radarr, bazarr, jellyfin and jellyseerr are all down. Then:
```sh
cd /volume1/docker/media-server
tar czf /volume1/docker/media-server-configs-$(date +%F).tgz qbittorrent sonarr radarr bazarr prowlarr jellyfin jellyseerr
```
(or a DSM snapshot of `/volume1/docker/media-server` now). This is the rollback point for the
one-way Seerr database migration and for every app setting changed below.

## 3. Build the data root (renames only, same volume, instant)

```sh
cd /volume1/docker/media-server
for t in data data/torrents gluetun/config; do [ -e "$t" ] && { echo "$t already exists - stop, do not nest"; exit 1; }; done
mv -T media data                                 # library root: data/movies, data/tv
mv -T downloads data/torrents                    # torrent staging joins the same root
mkdir -p data/torrents/movies data/torrents/tv data/torrents/incomplete data/recycle/movies data/recycle/tv
chown -R 1000:1000 data/torrents data/recycle
mkdir -p gluetun && mv -T /volume1/docker/gluetun/config gluetun/config   # gluetun state into the stack directory
rmdir /volume1/docker/gluetun 2>/dev/null || true                      # only if nothing else is left there
```

## 4. Find folders that exist in both places

Radarr will move its clean `Movie (Year)` folders from `torrents` into `movies` in step 8. If
the same folder name already exists in `movies`, Radarr merges into it. Check for overlaps first
and decide per title which copy to keep (move the other into a holding folder):

```sh
cd /volume1/docker/media-server/data
comm -12 <(ls torrents | sort) <(ls movies | sort)
comm -12 <(ls torrents | sort) <(ls tv | sort)
```
For each listed name, either delete nothing and move the `torrents` copy aside:
```sh
mkdir -p torrents/_duplicates && mv "torrents/<name>" torrents/_duplicates/
```
or keep the `torrents` copy and move the `movies`/`tv` one aside the same way.

## 5. Move raw torrent folders out of the library

`data/movies` also contains raw release folders (`www.UIndex.org - ...`, `The.Green.Mile.1999...`)
next to the clean ones. They would show up as duplicates in Jellyfin. Only 10 torrents exist in
qBittorrent and none point there, so these are leftovers. List them first:

```sh
cd /volume1/docker/media-server/data/movies
find . -maxdepth 1 -mindepth 1 -type d ! -regex '.* ([0-9][0-9][0-9][0-9])$'
```
Review the list (folders without a ` (Year)` suffix). Then move them aside, nothing is deleted:
```sh
mkdir -p ../torrents/_orphans
find . -maxdepth 1 -mindepth 1 -type d ! -regex '.* ([0-9][0-9][0-9][0-9])$' -exec mv {} ../torrents/_orphans/ \;
```
Also move Jellyfin's old collection folders (`<Name> [boxset]`, created by Jellyfin in what
used to be its library root) out of the way:
```sh
find ../torrents -maxdepth 1 -type d -name '*[[]boxset[]]' -exec mv {} ../torrents/_orphans/ \;
```

## 6. Redeploy the stack

1. Point the Portainer stack at branch `media-server-rework` (Stack > Editor / Git settings), or
   merge the branch to master first and redeploy.
2. Fill the new form fields: `SERVER_COUNTRIES` (default `Switzerland,Iceland`), `LAN_CIDR`
   (narrow to your LAN, e.g. `192.168.1.0/24`), leave `GLUETUN_IMAGE` at its default.
   `WIREGUARD_PRIVATE_KEY` stays as it is (the form is the only place the key lives).
3. Deploy. Expected: gluetun healthy within about a minute, then qbittorrent, then the rest.
4. **Lock-out check**: open `https://qbittorrent.<domain>` from a LAN browser. If Traefik
   returns 403, the NAS engine is presenting LAN clients with a bridge address. Check the
   client IP (first column of Traefik's access log):
   ```sh
   docker logs traefik --tail 20 2>&1 | awk '{print $1, $6, $7, $9}'
   ```
   If it shows a bridge address (typically the gateway `172.22.0.1`, also what IPv6 clients
   arrive as), add ONLY that address as a `/32` to `LAN_CIDR`, never a `/16`, and redeploy.
5. **Tunnel leftovers**: the root stack still runs `cloudflared`. In Cloudflare Zero Trust >
   Tunnels, delete every public hostname that points at a media service, or make sure each
   targets `https://traefik:443` (where the LAN gate rejects it). A hostname targeting
   `http://jellyseerr:5055` directly would bypass Traefik entirely.

## 7. qBittorrent and Prowlarr settings

Everything below is done in the UIs; the full expected state of each app is in `docs/`.

**qBittorrent** (`https://qbittorrent.<domain>`; see `docs/qbittorrent.md` for every value)
1. If prompted, set a permanent password (a temporary one is printed to
   `docker logs qbittorrent` on every start until you do).
2. Options > Downloads: Default Save Path `/data/torrents`; Automatic Torrent Management on,
   including "relocate on category/save-path change"; keep incomplete torrents in
   `/data/torrents/incomplete`.
3. Categories (left sidebar > right-click > Edit): `radarr` -> `/data/torrents/movies`,
   `tv-sonarr` -> `/data/torrents/tv`. Existing torrents: select all > Set Location
   `/data/torrents` if they still point at `/downloads`.
4. Options > Connection: listening port `6881`, UPnP/NAT-PMP off.
5. Options > Advanced: Network interface `tun0`.
6. Options > WebUI: Host header validation on with Server domains
   `qbittorrent.<domain>;gluetun` (**`gluetun` is mandatory**: Sonarr/Radarr reach it as
   `gluetun:8080` and would get 401 otherwise); CSRF and clickjacking protection on; reverse
   proxy support on with trusted proxies `172.22.0.0/16`; both "bypass authentication" options
   off.
7. Options > Downloads: "Run external program" off.

**Prowlarr** (`docs/prowlarr.md`)
1. Settings > Apps: Radarr `http://radarr:7878`, Sonarr `http://sonarr:8989`, and in each the
   Prowlarr Server `http://prowlarr:9696`. Container names, never the public `*.<domain>`
   hostnames: those loop through Traefik from a bridge address and are rejected by the
   LAN-only rule. Test both.
2. Settings > General > Security: Authentication Required = Enabled.

## 8. Re-point Radarr and Sonarr (two passes each)

Every movie and series record currently points at `/downloads/<Folder>`, a path the new
containers do not have. A mass edit with "Move Files" skips the move when the source folder
does not exist, so the paths must first be rewritten to where the files really are
(`/data/torrents/<Folder>`), and only then moved into the library.

**Radarr**
1. Settings > Media Management > Root Folders: add `/data/torrents` (temporary).
2. Movies > Select All > Edit > Root Folder `/data/torrents`, **Move Files: No** > Save.
   Paths now read `/data/torrents/<Movie (Year)>`, which exist (the old downloads dir).
3. Movies > Select All > Edit > Root Folder `/data/movies`, **Move Files: Yes** > Save.
   Radarr renames each folder into `/data/movies` (same mount, instant). Movies whose folder
   only exists in `/data/movies` already (the ones Radarr had lost) log a warning and simply
   get the right path.
4. Movies > Update All. Verify: no movie path starts with `/data/torrents`; movies that were
   "missing" before but had a folder under `data/movies` now show a file.
5. Remove the temporary `/data/torrents` root folder.

**Sonarr**: the same five steps with Series, root folder `/data/tv`.

Both apps, in the UI (see `docs/sonarr.md` and `docs/radarr.md` for every value):
* Settings > Media Management: Rename on; Recycling Bin `/data/recycle/tv` (`/data/recycle/movies`
  in Radarr), 14 days; Use Hardlinks on; Import Extra Files on (`srt,sub,idx`); Delete empty
  folders on. Sonarr: Season Folders on for every series (Series > Mass Edit).
* Settings > Download Clients > qBittorrent: host `gluetun`, port `8080`, **no** Remote Path
  Mapping (both sides see `/data/torrents`). Test must be green.
* Settings > General > Security: Authentication Required = **Enabled**. Never "Disabled for
  Local Addresses": behind Traefik every request looks local.

**Prowlarr**: Settings > General > Security: Authentication Required = **Enabled** as well.

The full expected state of every app, including the settings not touched by this guide, is
in `docs/` (one file per service).

## 9. qBittorrent leftovers

Existing torrents may carry a save path that does not exist inside the new container (in
the case that prompted this guide, a host-style `/volume1/docker/...` path). Open the WebUI
and check them: if
they show "Missing files", either right-click > Set Location `/data/torrents/movies` (or `/tv`)
followed by Force Recheck if the files are actually in the new tree, or remove the torrent
**without** deleting files. If every torrent turns out to use such paths, the legacy
`/downloads` alias in the compose protects nothing and can be removed right away.

## 10. Jellyfin

1. Dashboard > Libraries > Movies > Manage Library: add folder `/data/movies`, remove `/data`.
2. Add Library: Shows, folder `/data/tv`.
3. Scan All Libraries. Duplicates disappear; movies that were only in `data/movies` appear.
4. Dashboard > Networking: Known proxies `172.22.0.0/16`; LAN networks = your LAN CIDR; UPnP off.
5. The library is mounted read-only. Keep "save artwork/NFO into media folders" and
   "trickplay images next to media" OFF, and do not delete media from the Jellyfin UI
   (Radarr/Sonarr own the files).

## 11. Bazarr (one-time setup; it was never configured)

1. Settings > General > Security: Authentication Forms, set a username and password.
2. Settings > Languages: enable English and Polish. Create a Languages Profile "en+pl" with
   both (Polish first if you prefer it as default), and set it as the default profile for
   both Series and Movies.
3. Settings > Sonarr: enable, address `sonarr`, port `8989`, API key from Sonarr; Path
   Mappings empty. Settings > Radarr: enable, address `radarr`, port `7878`, API key; Path
   Mappings empty. Container names, not the public hostnames.
4. Settings > Providers: add `napiprojekt` (Polish, no account), `podnapisi` (no account), and
   `opensubtitles.com` (free account; best English coverage). Save.
5. Settings > Subtitles: enable "Upgrade previously downloaded subtitles"; leave hearing
   impaired off. Save.
6. Series and Movies pages: Bazarr lists everything it got from Sonarr/Radarr; it fetches
   missing subtitles on its schedule (or Mass Edit > Search on demand).

## 12. Jellyseerr (now Seerr)

The stack now runs `ghcr.io/seerr-team/seerr` instead of the abandoned `fallenbagel/jellyseerr`.
Same container name, hostname and config path; on first start it migrates the database in
place (one way, hence the backup in step 0 and the ownership fix in step 1). Watch
`docker logs jellyseerr` until "Server ready"; if it exits with `EACCES` on `/app/config`,
the chown in step 1 was skipped. Rollback, if ever needed: stop the container, restore
`jellyseerr/` from the section-2 tar, and set the image back to `fallenbagel/jellyseerr:2.7.3`.

Settings > Jellyfin: hostname `jellyfin`, port `8096`, no SSL. Settings > Radarr: hostname
`radarr`, port `7878`, Root Folder `/data/movies`. Settings > Sonarr: hostname `sonarr`, port
`8989`, Root Folder `/data/tv`, Season Folders on. Container names, not the public hostnames.
New requests now land in the library roots.

## 13. Later, at your leisure

* `data/torrents/_orphans` and `data/torrents/_duplicates`: review, then delete to reclaim
  space. Raw torrent folders in `data/torrents` whose torrent no longer exists in qBittorrent
  are also reclaimable.
* Remove the legacy `/downloads` alias from qbittorrent's volumes once no torrent shows a
  `/downloads/...` path (see section 9).
* `jellyfin/cache` on the host is now shadowed by the `jellyfin-cache` mount (Jellyfin writes
  cache and transcode segments there instead). The old directory only holds regenerable
  cache; delete it to reclaim space once the new stack has run for a while.
* Renaming existing files to the new naming scheme: Radarr/Sonarr > Rename Files (per movie or
  mass). Jellyfin will see renamed files as new items.

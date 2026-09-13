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

1. Take a DSM snapshot of `/volume1/docker/media-server` (Snapshot Replication) or at least:
   ```sh
   cd /volume1/docker/media-server
   tar czf /volume1/docker/media-server-configs-$(date +%F).tgz qbittorrent sonarr radarr bazarr prowlarr jellyfin jellyseerr
   ```
2. Note the current Jellyfin watched/favourite state you care about. Library paths change, so
   Jellyfin will treat movies as new items (watched status resets). Media files are untouched.
3. Have ready: the WireGuard private key, qBittorrent WebUI user/password, Sonarr and Radarr API
   keys (Settings > General).

## 1. NAS prerequisites (SSH as root)

1. **Boot task**: DSM Control Panel > Task Scheduler > Create > Triggered Task > Boot-up, user
   `root`, with the script from `known-issues.md` item 1 (loads the TUN module, creates
   `/dev/net/tun`, starts qbittorrent once gluetun is healthy). Run it once now as well.
2. **WireGuard key file** (optional but recommended; afterwards leave `WIREGUARD_PRIVATE_KEY`
   empty in the Portainer form). The directory lives inside the stack tree, which step 3 creates:
   ```sh
   mkdir -p /volume1/docker/media-server/gluetun/secrets
   printf '%s' 'YOUR_PRIVATE_KEY' > /volume1/docker/media-server/gluetun/secrets/wireguard_private_key
   chmod 700 /volume1/docker/media-server/gluetun/secrets && chmod 600 /volume1/docker/media-server/gluetun/secrets/*
   ```
3. **Ownership**: the containers now run as your user instead of root.
   ```sh
   chown -R 1000:1000 /volume1/docker/media-server
   ```
   Metadata only; takes a few minutes on 1.5 TB.

## 2. Stop the stack

Portainer > Stacks > media server > Stop. Confirm with `docker ps` that qbittorrent, sonarr,
radarr, bazarr, jellyfin and jellyseerr are down.

## 3. Build the data root (renames only, same volume, instant)

```sh
cd /volume1/docker/media-server
mv media data                                    # library root: data/movies, data/tv
mv downloads data/torrents                       # torrent staging joins the same root
mkdir -p data/torrents/movies data/torrents/tv data/torrents/incomplete data/recycle/movies data/recycle/tv
chown -R 1000:1000 data/torrents data/recycle
mkdir -p gluetun && mv /volume1/docker/gluetun/config gluetun/config   # gluetun state into the stack directory
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
Also move Jellyfin's old collection folders out of the way:
```sh
mv "../torrents/Atlantis Collection [boxset]" "../torrents/Knocked Up Collection [boxset]" "../torrents/Shrek Collection [boxset]" ../torrents/_orphans/ 2>/dev/null
```

## 6. Redeploy the stack

1. Point the Portainer stack at branch `media-server-rework` (Stack > Editor / Git settings), or
   merge the branch to master first and redeploy.
2. Fill the new form fields: `SERVER_COUNTRIES` (default `Switzerland,Iceland`), `LAN_CIDR`
   (narrow to your LAN, e.g. `192.168.1.0/24`), leave `GLUETUN_IMAGE` at its default, clear
   `WIREGUARD_PRIVATE_KEY` if you created the key file.
3. Deploy. Expected: gluetun healthy within about a minute, then qbittorrent, then the rest.
4. **Lock-out check**: open `https://qbittorrent.<domain>` from a LAN browser. If Traefik
   returns 403, the NAS engine is masquerading LAN clients as bridge addresses. Read
   `ClientAddr` in `docker logs traefik`; if it is `172.22.x`, set `LAN_CIDR` to include it as a
   stop-gap and re-deploy, then tell me: the durable fix is a separate Traefik entrypoint for
   the tunnel.

## 7. Push the versioned preferences

From a machine on the LAN, in this repo:
```sh
export SERVER_DOMAIN=<your domain> DOCKER_BRIDGE_CIDR=172.22.0.0/16
export QBIT_USER=... QBIT_PASS=... SONARR_API_KEY=... RADARR_API_KEY=... PROWLARR_API_KEY=...
make apply-media-config-dry     # review
make apply-media-config
```
This sets qBittorrent's save paths, categories, `tun0` binding, WebUI hardening; Sonarr/Radarr
renaming, recycle bin, hardlinks, season folders; and rewrites Prowlarr's Apps to the container
URLs (`http://radarr:7878`, `http://sonarr:8989`, `http://prowlarr:9696`). App-to-app traffic
must never use the public `*.<domain>` hostnames: those loop through Traefik from a bridge
address and are rejected by the LAN-only rule. Re-run any time after editing
`stacks/media-server/config/*.json`.

## 8. Re-point Radarr and Sonarr

**Radarr**: Movies > Select All > Edit > Root Folder `/data/movies`, **Move Files: Yes** > Save.
Radarr renames folders that are under `/data/torrents` into `/data/movies` (same mount, instant)
and logs a warning for movies whose folder is not there; those already live in `/data/movies`
and are picked up next. Then Movies > Update All. Verify: no movie path starts with
`/data/torrents`, and previously "missing" movies (Hot Fuzz, The Martian, ...) now show a file.

**Sonarr**: Series > Select All (Mass Edit) > Root Folder `/data/tv`, **Move Files: Yes**. Same
behaviour. Then Series > Update All.

Both apps: Settings > Download Clients > qBittorrent: host `gluetun`, port `8080`, and **no**
Remote Path Mapping (both sides see `/data/torrents`). Settings > General > Security:
Authentication Required = Enabled.

## 9. qBittorrent leftovers

The 10 existing torrents carry a `/volume1/docker/...` save path that does not exist inside the
container. Open the WebUI and check them: if they show "Missing files", either right-click >
Set Location `/data/torrents/movies` (or `/tv`) followed by Force Recheck if the files are
actually in the new tree, or remove the torrent **without** deleting files.

## 10. Jellyfin

1. Dashboard > Libraries > Movies > Manage Library: add folder `/data/movies`, remove `/data`.
2. Add Library: Shows, folder `/data/tv`.
3. Scan All Libraries. Duplicates disappear; movies that were only in `data/movies` appear.
4. Dashboard > Networking: Known proxies `172.22.0.0/16`; LAN networks = your LAN CIDR.

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
the chown in step 1 was skipped.

Settings > Jellyfin: hostname `jellyfin`, port `8096`, no SSL. Settings > Radarr: hostname
`radarr`, port `7878`, Root Folder `/data/movies`. Settings > Sonarr: hostname `sonarr`, port
`8989`, Root Folder `/data/tv`, Season Folders on. Container names, not the public hostnames.
New requests now land in the library roots.

## 13. Later, at your leisure

* `data/torrents/_orphans` and `data/torrents/_duplicates`: review, then delete to reclaim
  space. Raw torrent folders in `data/torrents` whose torrent no longer exists in qBittorrent
  are also reclaimable.
* Remove the legacy `/downloads` alias from qbittorrent's volumes once every torrent shows a
  `/data/torrents` path.
* `jellyfin/cache` on the host is now shadowed by the `jellyfin-cache` mount (Jellyfin writes
  cache and transcode segments there instead). The old directory only holds regenerable
  cache; delete it to reclaim space once the new stack has run for a while.
* Renaming existing files to the new naming scheme: Radarr/Sonarr > Rename Files (per movie or
  mass). Jellyfin will see renamed files as new items.

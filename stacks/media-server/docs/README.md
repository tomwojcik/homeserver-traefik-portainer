# Expected configuration, per service

One file per service. Each describes the state the service is expected to be in once deployed:

* **Compose / template** — set by `docker-compose.yml` and the Portainer form; nothing to do.
* **Set once in the UI** — settings the apps keep in their own databases. Expected values are
  listed; anything else is a drift worth fixing.
* **Left at defaults on purpose** — settings that were considered and deliberately not
  changed, with the reason, so nobody "fixes" them later.
* **Verify** — commands or UI checks that prove the service is in the expected state.

Conventions that apply everywhere:

* Containers address each other by container name (`http://sonarr:8989`, `gluetun:8080`),
  never by the public `*.<domain>` hostnames. Those hairpin through Traefik for no benefit
  and make every sync depend on DNS and certificates.
* Every UI keeps its own login enabled. That is the access control: there is no IP
  allow-list (`../known-issues.md` item 8).
* Paths are always the container-side `/data/...` paths. The host side is
  `/volume1/docker/media-server/data/...`.

| Service | File |
|---|---|
| gluetun (+ deunhealth) | [gluetun.md](gluetun.md) |
| qBittorrent | [qbittorrent.md](qbittorrent.md) |
| Prowlarr (+ FlareSolverr) | [prowlarr.md](prowlarr.md) |
| Sonarr | [sonarr.md](sonarr.md) |
| Radarr | [radarr.md](radarr.md) |
| Bazarr | [bazarr.md](bazarr.md) |
| Jellyfin | [jellyfin.md](jellyfin.md) |
| Seerr (Jellyseerr) | [jellyseerr.md](jellyseerr.md) |

Upgrading an existing deployment to this state: `../manual_migration.md`.

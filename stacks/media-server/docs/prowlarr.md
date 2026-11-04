# Prowlarr (indexer manager)

Prowlarr owns the indexer list and pushes it to Sonarr, Radarr and Lidarr. Never add indexers in
Sonarr or Radarr directly.

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `user` / `read_only` / `cap_drop` | `PUID:PGID`, read-only, ALL dropped | LinuxServer non-root + read-only modes. |
| networks | `homeserver` | For Traefik, Sonarr, Radarr. |
| healthcheck | `GET /ping` | Anonymous readiness endpoint. |
| router | `prowlarr.<domain>`, `media-headers` | |

## FlareSolverr: disabled

FlareSolverr is commented out in `docker-compose.yml`. Its Chromium lags Chrome stable and runs
with `--no-sandbox`: v3.5.2, the newest release, ships 152.0.7977.82, which lacks the fix for the
actively exploited CVE-2026-87491 (fixed in 153.0.8010.36). Without it, indexers behind a
Cloudflare challenge do not work.

To re-enable, first check the Chromium version of the new release. Then uncomment the service and
`media-internal` (under prowlarr and under networks), and add one Indexer Proxy in Prowlarr:
`FlareSolverr`, host `http://flaresolverr:8191`, request timeout 60 s, tag `flaresolverr`. Tag only
the indexers behind Cloudflare; every solve launches a browser. It is unauthenticated, so keep it
on `media-internal`, where only Prowlarr can reach it.

## Set once in the UI

| Where | Expected |
|---|---|
| Settings > General > Security | Authentication `Forms`, Authentication Required `Enabled`, a username and password. |
| Settings > Apps | One entry per app, Sync Level `Full Sync`, no tags (every indexer goes to every app). Radarr: Prowlarr Server `http://prowlarr:9696`, Radarr Server `http://radarr:7878`. Sonarr: Prowlarr Server `http://prowlarr:9696`, Sonarr Server `http://sonarr:8989`. Lidarr: Prowlarr Server `http://prowlarr:9696`, Lidarr Server `http://lidarr:8686`. Container names: the public hostnames would loop through Traefik for no benefit. |
| Settings > Indexers > Indexer Proxies | Empty. |
| Indexers | Your trackers. |

## Left at defaults on purpose

* RSS sync interval, search limits, history retention.
* No download clients in Prowlarr: Sonarr and Radarr grab releases themselves.
* No indexer priorities: Sonarr/Radarr score releases, Prowlarr only searches.

## Verify

```sh
docker exec prowlarr curl -s -o /dev/null -w '%{http_code}\n' http://localhost:9696/ping   # 200
docker ps -a --filter name=flaresolverr --format '{{.Names}}'                              # empty
```
In the UI: Settings > Apps > Test is green, Settings > Indexers > Indexer Proxies is empty;
System > Health shows no warnings.

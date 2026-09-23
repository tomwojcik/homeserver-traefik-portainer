# Prowlarr (indexer manager) and FlareSolverr (challenge solver)

Prowlarr owns the indexer list and pushes it to Sonarr and Radarr. Never add indexers in
Sonarr or Radarr directly.

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `user` / `read_only` / `cap_drop` | `PUID:PGID`, read-only, ALL dropped | LinuxServer non-root + read-only modes. |
| networks | `homeserver` + `media-internal` | `homeserver` for Traefik, Sonarr, Radarr; `media-internal` is the only way to reach FlareSolverr. |
| healthcheck | `GET /ping` | Anonymous readiness endpoint. |
| router | `prowlarr.<domain>`, `media-headers` | |

FlareSolverr: `v3.5.0`, only on `media-internal`, no router, `cap_drop ALL`, `/tmp` and
`/config` on tmpfs, 2 GB memory cap (each request launches a Chromium), `LOG_HTML=false`,
`CAPTCHA_SOLVER=none`. It is unauthenticated by design, which is why nothing but Prowlarr
can reach it.

## Set once in the UI

| Where | Expected |
|---|---|
| Settings > General > Security | Authentication `Forms`, Authentication Required `Enabled`, a username and password. |
| Settings > Apps | One entry per app, Sync Level `Full Sync`, no tags (every indexer goes to both apps). Radarr: Prowlarr Server `http://prowlarr:9696`, Radarr Server `http://radarr:7878`. Sonarr: Prowlarr Server `http://prowlarr:9696`, Sonarr Server `http://sonarr:8989`. Container names: the public hostnames would loop through Traefik for no benefit. |
| Settings > Indexers > Indexer Proxies | One `FlareSolverr` entry, host `http://flaresolverr:8191`, request timeout 60 s, tag `flaresolverr`. |
| Indexers | Your trackers. Add the `flaresolverr` tag only to the ones behind Cloudflare; every solve launches a browser. |

## Left at defaults on purpose

* RSS sync interval, search limits, history retention.
* No download clients in Prowlarr: Sonarr and Radarr grab releases themselves.
* No indexer priorities: Sonarr/Radarr score releases, Prowlarr only searches.

## Verify

```sh
docker exec prowlarr curl -s -o /dev/null -w '%{http_code}\n' http://flaresolverr:8191/health   # 200
docker exec sonarr   curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://flaresolverr:8191/health || echo "unreachable from the bridge (expected)"
```
In the UI: Settings > Apps > Test and Settings > Indexers > Indexer Proxies > Test are green;
System > Health shows no warnings.

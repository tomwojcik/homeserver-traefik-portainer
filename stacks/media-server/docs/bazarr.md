# Bazarr (subtitles)

Watches Sonarr and Radarr and fetches subtitles in the configured languages for every
episode and movie, then upgrades them when a better match appears. Jellyfin's own
subtitle download stays available as an on-demand fallback.

## Compose / template

| Setting | Value | Why |
|---|---|---|
| `user` / `read_only` / `cap_drop` | `PUID:PGID`, read-only, ALL dropped | LinuxServer non-root + read-only modes. |
| mounts | `/config`; `data/movies` at `/data/movies`; `data/tv` at `/data/tv` | Library only; the same container paths Sonarr and Radarr report, so no path mappings. |
| healthcheck | `GET /` | Liveness only; Bazarr has no anonymous readiness endpoint. |
| router | `bazarr.<domain>`, `media-headers` | |
| image | `v1.6.0-ls363` | Pinned. |

## Set once in the UI

| Where | Expected |
|---|---|
| Settings > General > Security | Authentication `Form`, username and password. Bazarr has no "authentication required" toggle like the *arrs; Form auth is the whole setting. |
| Settings > Languages | English and Polish enabled. One Languages Profile `en+pl` containing both, set as the default profile for Series and for Movies. |
| Settings > Sonarr | Enabled, address `sonarr`, port `8989`, base URL empty, Sonarr's API key, **Path Mappings empty**. |
| Settings > Radarr | Enabled, address `radarr`, port `7878`, Radarr's API key, **Path Mappings empty**. |
| Settings > Providers | `napiprojekt` (Polish, no account), `podnapisi` (no account), `opensubtitles.com` (free account; best English coverage). |
| Settings > Subtitles | "Upgrade previously downloaded subtitles" on; Hearing Impaired off. |

## Left at defaults on purpose

* Search frequency and upgrade window.
* Minimum score thresholds (raise them if you get mismatched subtitles).
* "Treat embedded subtitles as available" on: a release with embedded English is not
  re-fetched.
* Anti-captcha: none of the chosen providers needs it.
* Subtitle file naming: `<video name>.<lang>.srt`, which Jellyfin picks up automatically.

## Verify

In the UI: Settings > Sonarr > Test and Settings > Radarr > Test are green; the Series and
Movies pages list everything the *arrs know; System > Tasks shows the sync tasks running;
a recently added episode shows both languages as downloaded (or "missing" with a search
history entry explaining why).

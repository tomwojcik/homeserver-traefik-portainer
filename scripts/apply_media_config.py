#!/usr/bin/env python3
"""Push the versioned media-server preferences to the running apps.

Reads stacks/media-server/config/*.json and applies them through each app's API so the
settings that matter live in git instead of only inside the apps' own databases.

    make apply-media-config          # apply
    make apply-media-config-dry      # show what would change, touch nothing

Environment (nothing is read from files; keys are never committed):
    SERVER_DOMAIN       required unless every *_URL below is given (URLs default to https://<app>.$SERVER_DOMAIN)
    DOCKER_BRIDGE_CIDR  subnet of the `homeserver` Docker network, e.g. 172.22.0.0/16
                        (docker network inspect homeserver -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    QBIT_USER, QBIT_PASS            qBittorrent WebUI credentials
    SONARR_API_KEY, RADARR_API_KEY, PROWLARR_API_KEY  from Settings > General in each app
    QBIT_URL, SONARR_URL, RADARR_URL, PROWLARR_URL  optional overrides
    APPLY_ONLY          optional comma list to limit the run, e.g. APPLY_ONLY=qbittorrent

Run it from a machine on the LAN: the admin hostnames are LAN-only behind Traefik.
Standard library only; Python 3.8+.
"""
import http.cookiejar
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = os.path.join(ROOT, "stacks", "media-server", "config")
DRY = "--dry-run" in sys.argv


# ----------------------------------------------------------------------------- helpers
def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def env(name, default=None, required=False):
    v = os.environ.get(name, default)
    if required and not v:
        die(f"{name} is not set")
    return v


def substitute(obj):
    """Replace ${VAR} in every string with the environment value; fail on unknown vars."""
    if isinstance(obj, dict):
        return {k: substitute(v) for k, v in obj.items() if k != "_comment"}
    if isinstance(obj, list):
        return [substitute(v) for v in obj]
    if isinstance(obj, str):
        def repl(m):
            val = os.environ.get(m.group(1))
            if val is None:
                die(f"config references ${{{m.group(1)}}} but it is not set in the environment")
            return val
        return re.sub(r"\$\{([A-Z0-9_]+)\}", repl, obj)
    return obj


def load(name):
    path = os.path.join(CONFIG_DIR, f"{name}.json")
    with open(path, encoding="utf-8") as fh:
        return substitute(json.load(fh))


def diff(current, desired):
    """Keys whose desired value differs from the current one."""
    return {k: (current.get(k), v) for k, v in desired.items() if current.get(k) != v}


def show_diff(label, changes):
    if not changes:
        print(f"  {label}: up to date")
        return
    print(f"  {label}: {len(changes)} change(s)")
    for k, (old, new) in changes.items():
        print(f"    {k}: {old!r} -> {new!r}")


class Http:
    def __init__(self, base, headers=None):
        self.base = base.rstrip("/")
        self.headers = headers or {}
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, data=None, form=False):
        url = f"{self.base}{path}"
        body = None
        headers = dict(self.headers)
        if data is not None:
            if form:
                body = urllib.parse.urlencode(data).encode()
                headers["Content-Type"] = "application/x-www-form-urlencoded"
            else:
                body = json.dumps(data).encode()
                headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with self.opener.open(req, timeout=30) as resp:
                raw = resp.read().decode()
        except urllib.error.HTTPError as e:
            die(f"{method} {url} -> HTTP {e.code}: {e.read().decode()[:300]}")
        except urllib.error.URLError as e:
            die(f"{method} {url} -> {e.reason}")
        if not raw:
            return None
        try:
            return json.loads(raw)
        except ValueError:
            return raw


# ----------------------------------------------------------------------------- qbittorrent
def apply_qbittorrent(domain):
    cfg = load("qbittorrent")
    base = env("QBIT_URL") or f"https://qbittorrent.{domain}"
    api = Http(base, headers={"Referer": base})
    print(f"qbittorrent @ {base}")

    login = api.call("POST", "/api/v2/auth/login",
                     {"username": env("QBIT_USER", required=True),
                      "password": env("QBIT_PASS", required=True)}, form=True)
    if login != "Ok.":
        die(f"qbittorrent login failed: {login!r}")

    current = api.call("GET", "/api/v2/app/preferences")
    changes = diff(current, cfg["preferences"])
    show_diff("preferences", changes)
    if changes and not DRY:
        api.call("POST", "/api/v2/app/setPreferences",
                 {"json": json.dumps({k: v[1] for k, v in changes.items()})}, form=True)

    existing = api.call("GET", "/api/v2/torrents/categories") or {}
    for name, save_path in cfg.get("categories", {}).items():
        cur = existing.get(name, {}).get("savePath")
        if cur == save_path:
            print(f"  category {name}: up to date")
            continue
        action = "create" if name not in existing else "edit"
        print(f"  category {name}: {action} -> {save_path} (was {cur!r})")
        if not DRY:
            api.call("POST", f"/api/v2/torrents/{action}Category",
                     {"category": name, "savePath": save_path}, form=True)


# ----------------------------------------------------------------------------- sonarr / radarr
def apply_arr(name, domain, key_var, port_hint):
    cfg = load(name)
    base = env(f"{name.upper()}_URL") or f"https://{name}.{domain}"
    api = Http(base, headers={"X-Api-Key": env(key_var, required=True)})
    print(f"{name} @ {base}")

    for section in ("naming", "mediamanagement"):
        if section not in cfg:
            continue
        current = api.call("GET", f"/api/v3/config/{section}")
        changes = diff(current, cfg[section])
        show_diff(section, changes)
        if changes and not DRY:
            merged = dict(current)
            merged.update(cfg[section])
            api.call("PUT", f"/api/v3/config/{section}/{current['id']}", merged)

    existing = {rf["path"].rstrip("/") for rf in api.call("GET", "/api/v3/rootfolder") or []}
    for path in cfg.get("rootFolders", []):
        if path.rstrip("/") in existing:
            print(f"  root folder {path}: exists")
        else:
            print(f"  root folder {path}: add")
            if not DRY:
                api.call("POST", "/api/v3/rootfolder", {"path": path})

    if name == "sonarr" and cfg.get("seasonFolders"):
        series = api.call("GET", "/api/v3/series") or []
        todo = [s for s in series if not s.get("seasonFolder")]
        print(f"  season folders: {len(series) - len(todo)}/{len(series)} series already on")
        for s in todo:
            print(f"    enable for: {s['title']}")
            if not DRY:
                s["seasonFolder"] = True
                api.call("PUT", f"/api/v3/series/{s['id']}", s)


# ----------------------------------------------------------------------------- prowlarr
def apply_prowlarr(domain):
    """Point Prowlarr's Apps at container names so syncs do not loop through Traefik."""
    cfg = load("prowlarr")
    base = env("PROWLARR_URL") or f"https://prowlarr.{domain}"
    api = Http(base, headers={"X-Api-Key": env("PROWLARR_API_KEY", required=True)})
    print(f"prowlarr @ {base}")

    apps = api.call("GET", "/api/v1/applications") or []
    by_name = {a["name"].lower(): a for a in apps}
    for name, desired in cfg.get("applications", {}).items():
        app = by_name.get(name.lower())
        if not app:
            print(f"  app {name}: not configured in Prowlarr (skipped)")
            continue
        fields = {f["name"]: f for f in app.get("fields", [])}
        changes = {k: (fields[k].get("value"), v) for k, v in desired.items()
                   if k in fields and fields[k].get("value") != v}
        show_diff(f"app {name}", changes)
        if changes and not DRY:
            for k, (_, v) in changes.items():
                fields[k]["value"] = v
            api.call("PUT", f"/api/v1/applications/{app['id']}", app)


# ----------------------------------------------------------------------------- main
def main():
    only = {x.strip() for x in env("APPLY_ONLY", "").split(",") if x.strip()}
    domain = env("SERVER_DOMAIN")
    if not domain and not all(env(v) for v in ("QBIT_URL", "SONARR_URL", "RADARR_URL", "PROWLARR_URL")):
        die("SERVER_DOMAIN is not set (or set QBIT_URL/SONARR_URL/RADARR_URL/PROWLARR_URL)")
    if DRY:
        print("dry run: nothing will be changed\n")

    steps = {
        "qbittorrent": lambda: apply_qbittorrent(domain),
        "sonarr": lambda: apply_arr("sonarr", domain, "SONARR_API_KEY", 8989),
        "radarr": lambda: apply_arr("radarr", domain, "RADARR_API_KEY", 7878),
        "prowlarr": lambda: apply_prowlarr(domain),
    }
    for app, fn in steps.items():
        if only and app not in only:
            continue
        fn()
        print()


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# Bring the stacks running on this host in line with the compose files in this repo checkout.
#
#   git pull
#   scripts/sync-stacks.sh       # shows what will change, asks once, then applies (re-runs itself with sudo)
#   scripts/sync-stacks.sh -y    # applies without asking (skips stacks with blank variables)
#
# The repo's stacks are the root docker-compose.yml and stacks/*/docker-compose.yml. A stack counts
# as deployed when a container its compose file names (container_name) is running; the rest are
# left alone. The containers' compose labels say which project they belong to and which compose
# file started them.
#
# Stacks deployed by Portainer: their compose file is Portainer's own copy in its data volume.
# When it differs from the repo's, it gets the repo's version (the old one stays next to it as
# <file>.bak-<time>), so Portainer's editor shows the new file, and `docker compose up -d` runs
# with the stack's variables from Portainer's stack.env. Portainer stacks that already match the
# repo aren't touched.
#
# Stacks started by hand are only handled when they run from this checkout (the root stack); for
# those `docker compose up -d` runs after every `git pull`, with the .env next to the file.
#
# Services you stopped yourself stay stopped. Variables the new file uses without a default and
# that would be blank are shown in the plan; with -y those stacks are skipped. The first failed
# stack stops the run.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

die() { echo "error: $*" >&2; exit 1; }
label() { docker inspect --type container -f "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null || true; }
first_line() { printf '%s' "${1%%$'\n'*}"; }
# Variables a compose file uses as ${NAME}, with no default, outside comments
required_vars() {
  { sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' -e 's/^/ /' "$1" | grep -o '[^$]\${[A-Za-z_][A-Za-z0-9_]*}' || true; } \
    | sed 's/^.\${\(.*\)}$/\1/' | sort -u
}
# env_value <env file> <name>: the last value the file assigns to name, without surrounding quotes
env_value() {
  [ -f "$1" ] || return 0
  sed -n "s/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}$2[[:space:]]*=//p" "$1" | tail -n 1 \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

# Portainer's data volume (/volume1/@docker/volumes/...) is readable by root only. Without root its
# stack files look missing even when docker itself works for this user.
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "run this as root"
  exec sudo bash "${BASH_SOURCE[0]}" "$@"
fi

yes=0
case "${1:-}" in
  "") ;;
  -y) yes=1 ;;
  *) die "usage: $0 [-y]" ;;
esac

[ -f "$repo/docker-compose.yml" ] && [ -d "$repo/stacks" ] || die "$repo doesn't look like the homeserver repo"
docker info >/dev/null 2>&1 || die "can't reach Docker; run with sudo"
if docker compose version >/dev/null 2>&1; then compose=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then compose=(docker-compose)
else die "neither 'docker compose' nor 'docker-compose' is installed"; fi
host_compose=$("${compose[@]}" version --short 2>/dev/null || true)
host_compose=${host_compose#v}

# Portainer runs compose inside its own container, where its data volume is mounted at /data.
portainer=$(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /^portainer\/portainer-(ce|ee)/ {print $1}')
portainer=$(first_line "$portainer")
if [ -z "$portainer" ] && [ "$(docker inspect --type container -f '{{.State.Running}}' portainer 2>/dev/null)" = true ]; then
  portainer=portainer
fi
pdata=""
if [ -n "$portainer" ]; then
  pdata=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$portainer")
fi

# One entry per stack to update
S_NAME=() S_PROJECT=() S_OWNER=() S_WD=() S_CFG=() S_ENV=() S_NEW=() S_CHANGED=() S_DROP=()
S_BLANK=() S_STOPPED=() S_SVCS=() S_NOTE=()

# compose_for <i> <compose file> <compose args...>: run compose for stack i with only the stack's
# own variables (the caller's environment, e.g. sudo's TZ, would override them)
compose_for() {
  local i=$1 file=$2
  shift 2
  local args=(-p "${S_PROJECT[i]}" --project-directory "${S_WD[i]}" -f "$file")
  if [ -n "${S_ENV[i]}" ]; then args+=(--env-file "${S_ENV[i]}"); fi
  env -i PATH="$PATH" HOME="${HOME:-/root}" "${compose[@]}" "${args[@]}" "$@"
}

echo "Comparing the stacks running here with $repo"

declare -A seen=()
not_deployed=()
up_to_date=()
skipped=()
n=0
# The root stack goes last: it restarts Portainer and Traefik.
for new in "$repo"/stacks/*/docker-compose.yml "$repo/docker-compose.yml"; do
  if [ "$new" = "$repo/docker-compose.yml" ]; then name=root; else name=$(basename "$(dirname "$new")"); fi

  project=""
  mapfile -t names < <(sed -n "s/^[[:space:]]*container_name:[[:space:]]*[\"']\{0,1\}\([^\"' #]*\).*/\1/p" "$new")
  for c in ${names[@]+"${names[@]}"}; do
    project=$(label "$c" com.docker.compose.project)
    if [ -n "$project" ]; then break; fi
  done
  if [ -z "$project" ] && [ ${#names[@]} = 0 ]; then
    # No container_name in the file: look for a compose project named like the folder.
    for p in "$name" "${name//-/_}"; do
      if [ -n "$(docker ps -aq --filter "label=com.docker.compose.project=$p")" ]; then project=$p; break; fi
    done
  fi
  if [ -z "$project" ]; then not_deployed+=("$name"); continue; fi
  cid=$(first_line "$(docker ps -q --filter "label=com.docker.compose.project=$project")")
  if [ -z "$cid" ]; then skipped+=("$name: stopped, left alone"); continue; fi
  if [ -n "${seen[$project]:-}" ]; then skipped+=("$name: compose project '$project' is already handled as ${seen[$project]}"); continue; fi
  seen[$project]=$name

  wd=$(label "$cid" com.docker.compose.project.working_dir)
  cfg=$(label "$cid" com.docker.compose.project.config_files)
  case $cfg in *,*) skipped+=("$name: started from several compose files ($cfg), update it by hand"); continue ;; esac
  case $cfg in
    /data/compose/*)
      if [ -z "$pdata" ]; then skipped+=("$name: deployed by Portainer, but Portainer isn't running"); continue; fi
      cfg="$pdata${cfg#/data}"
      ;;
  esac
  case $wd in /data/compose/*) if [ -n "$pdata" ]; then wd="$pdata${wd#/data}"; fi ;; esac
  owner=hand
  if [ -n "$pdata" ] && [[ $cfg == "$pdata"/compose/* ]]; then owner=Portainer; fi
  if [ ! -f "$cfg" ]; then skipped+=("$name: its compose file $cfg doesn't exist or can't be read"); continue; fi
  if [ $owner = hand ] && ! [ "$cfg" -ef "$new" ]; then
    skipped+=("$name: started by hand from $cfg, not from this checkout; left alone")
    continue
  fi

  # Portainer keeps a stack's variables in <its folder>/stack.env (only if the stack has any).
  envf=""
  varsf="$wd/.env"
  if [ $owner = Portainer ]; then
    rel=${cfg#"$pdata"/compose/}
    if [ -f "$pdata/compose/${rel%%/*}/stack.env" ]; then
      envf="$pdata/compose/${rel%%/*}/stack.env"
      varsf=$envf
    fi
  fi
  changed=1
  if [ "$cfg" -ef "$new" ] || cmp -s "$cfg" "$new"; then changed=0; fi
  # Portainer saved the old Gluetun image as a stack variable; it would override the version pinned in the file.
  drop=""
  if [ "$name" = media-server ] && [ -n "$envf" ] && grep -q '^GLUETUN_IMAGE=' "$envf"; then drop=GLUETUN_IMAGE; fi
  if [ $owner = Portainer ] && [ $changed = 0 ] && [ -z "$drop" ]; then up_to_date+=("$name"); continue; fi

  S_NAME[n]=$name S_PROJECT[n]=$project S_OWNER[n]=$owner S_WD[n]=$wd S_CFG[n]=$cfg
  S_ENV[n]=$envf S_NEW[n]=$new S_CHANGED[n]=$changed S_DROP[n]=$drop
  if ! out=$(compose_for "$n" "$new" config -q 2>&1); then
    skipped+=("$name: the repo's compose file doesn't validate here: $(printf '%s' "$out" | tail -n 3)")
    continue
  fi

  blank=""
  for v in $(required_vars "$new"); do
    if [ -z "$(env_value "$varsf" "$v")" ]; then blank+="$v "; fi
  done
  S_BLANK[n]=${blank% }

  # Services with containers that are all stopped were stopped on purpose: leave them out of `up`.
  existing=$(docker ps -a --filter "label=com.docker.compose.project=$project" --format '{{.Label "com.docker.compose.service"}}' | sort -u)
  running=$(docker ps --filter "label=com.docker.compose.project=$project" --format '{{.Label "com.docker.compose.service"}}' | sort -u)
  stopped=$(comm -23 <(printf '%s\n' "$existing") <(printf '%s\n' "$running") | sed '/^$/d' | tr '\n' ' ')
  S_STOPPED[n]=${stopped% }
  S_SVCS[n]=""
  if [ -n "$stopped" ]; then
    all=$(compose_for "$n" "$new" config --services 2>/dev/null | sort -u || true)
    S_SVCS[n]=$(comm -23 <(printf '%s\n' "$all") <(printf '%s\n' $stopped | sort -u) | sed '/^$/d' | tr '\n' ' ')
  fi

  S_NOTE[n]=""
  created_by=$(label "$cid" com.docker.compose.version)
  if [ $owner = Portainer ] && [ -n "$host_compose" ] && [ -n "$created_by" ] && [ "${created_by#v}" != "$host_compose" ]; then
    S_NOTE[n]="Portainer created these containers with compose $created_by and this host runs $host_compose, so expect all of them to be recreated, not only the changed ones."
  fi
  n=$((n + 1))
done

echo
if [ ${#not_deployed[@]} -gt 0 ]; then echo "Not deployed here: ${not_deployed[*]}"; fi
if [ ${#up_to_date[@]} -gt 0 ]; then echo "Already match the repo: ${up_to_date[*]}"; fi
for s in ${skipped[@]+"${skipped[@]}"}; do echo "Skipped $s"; done
if [ $n = 0 ]; then echo "Nothing to update."; exit 0; fi

for ((i = 0; i < n; i++)); do
  echo
  echo "== ${S_NAME[i]}  (compose project '${S_PROJECT[i]}', deployed by ${S_OWNER[i]})"
  echo "   ${S_CFG[i]}"
  if [ "${S_CHANGED[i]}" = 0 ]; then
    echo "   The file matches the repo; up -d recreates containers that don't match it."
  elif command -v diff >/dev/null 2>&1; then
    { diff -u "${S_CFG[i]}" "${S_NEW[i]}" || true; } | tail -n +3 | sed 's/^/   /'
  else
    echo "   The file differs from the repo ('diff' isn't installed to show how)."
  fi
  if [ -n "${S_DROP[i]}" ]; then echo "   ${S_DROP[i]} is removed from ${S_ENV[i]}, so the version pinned in the file applies."; fi
  if [ -n "${S_STOPPED[i]}" ]; then echo "   Left stopped: ${S_STOPPED[i]}"; fi
  if [ -n "${S_NOTE[i]}" ]; then echo "   ${S_NOTE[i]}"; fi
  if [ -n "${S_BLANK[i]}" ]; then
    echo "   WARNING: ${S_BLANK[i]} would be blank (set in ${S_ENV[i]:-${S_WD[i]}/.env}).$([ $yes = 1 ] && echo ' Skipped because of -y.')"
  fi
done

if [ $yes = 0 ]; then
  { exec 3</dev/tty; } 2>/dev/null || die "no terminal to ask on; run with -y"
  echo
  printf 'Update these %d stack(s)? [y/N] ' "$n"
  read -r answer <&3 || answer=""
  case $answer in y|Y|yes) ;; *) echo "Nothing changed."; exit 0 ;; esac
fi

ts=$(date +%Y%m%d-%H%M%S)
restore=()
partial=""
on_exit() {
  if [ -n "$partial" ]; then rm -f "$partial"; fi
  if [ ${#restore[@]} -gt 0 ]; then
    echo
    echo "To roll a stack back, restore its files and redeploy it (Portainer: 'Update the stack'):"
    for r in "${restore[@]}"; do echo "  $r"; done
  fi
}
trap on_exit EXIT

ok=()
failed=""
for ((i = 0; i < n; i++)); do
  if [ $yes = 1 ] && [ -n "${S_BLANK[i]}" ]; then continue; fi
  echo
  echo "== ${S_NAME[i]}"
  if [ "${S_CHANGED[i]}" = 1 ]; then
    cfg=${S_CFG[i]}
    cp -p "$cfg" "$cfg.bak-$ts"
    restore+=("cp -p '$cfg.bak-$ts' '$cfg'")
    # Write next to the file, then rename over it: the old file stays whole if anything fails.
    partial="$cfg.sync-$ts"
    cp -p "$cfg" "$partial"
    cat "${S_NEW[i]}" >"$partial"
    mv -f "$partial" "$cfg"
    partial=""
  fi
  if [ -n "${S_DROP[i]}" ]; then
    cp -p "${S_ENV[i]}" "${S_ENV[i]}.bak-$ts"
    restore+=("cp -p '${S_ENV[i]}.bak-$ts' '${S_ENV[i]}'")
    sed -i "/^${S_DROP[i]}=/d" "${S_ENV[i]}"
  fi
  read -r -a svcs <<<"${S_SVCS[i]}"
  if compose_for "$i" "${S_CFG[i]}" up -d ${svcs[@]+"${svcs[@]}"}; then
    ok+=("${S_NAME[i]}")
  else
    failed=${S_NAME[i]}
  fi
  docker ps -a --filter "label=com.docker.compose.project=${S_PROJECT[i]}" --format '   {{.Names}}  {{.Image}}  {{.Status}}'
  if [ -n "$failed" ]; then break; fi
done

echo
echo "Updated: ${ok[*]:-none}"
if [ -n "$failed" ]; then
  echo "Failed: $failed (see the compose output above). Stopped there; the stacks after it weren't touched."
fi
for ((i = 0; i < n; i++)); do
  if [ -n "${S_DROP[i]}" ] && [ "${S_OWNER[i]}" = Portainer ]; then
    echo
    echo "Portainer rewrites stack.env from its saved variables whenever it starts or redeploys"
    echo "${S_NAME[i]}, which would bring the old ${S_DROP[i]} back. Remove ${S_DROP[i]} from the stack's"
    echo "environment variables in Portainer once."
  fi
done
if [ -n "$failed" ]; then exit 1; fi

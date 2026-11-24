#!/usr/bin/env bash
# Bring the stacks running on this host in line with the compose files in this repo checkout.
#
#   git pull
#   sudo bash scripts/sync-stacks.sh       # shows what will change, asks once, then applies
#   sudo bash scripts/sync-stacks.sh -y    # applies without asking
#
# The repo's stacks are the root docker-compose.yml and stacks/*/docker-compose.yml. A stack counts
# as deployed when a container its compose file names (container_name) is running; the rest are
# left alone. The containers' compose labels say which project they belong to and which compose
# file started them. That file gets the repo's version (the old one stays next to it as
# <file>.bak-<time>), then `docker compose up -d` runs for the project, which recreates only the
# containers whose configuration differs.
#
# Stacks deployed by Portainer: the file replaced is Portainer's own copy in its data volume, so
# Portainer's editor shows the new version. Variables come from the stack's stack.env (Portainer
# writes it from the stack's environment variables), then from Portainer's own environment.
# Stacks started by hand, like the root stack from this checkout, use the .env next to their
# compose file.
#
# A stack is skipped when the repo's compose file would leave one of its variables blank, so
# nothing gets started with an empty domain or token.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

die() { echo "error: $*" >&2; exit 1; }
label() { docker inspect --type container -f "{{index .Config.Labels \"$2\"}}" "$1" 2>/dev/null || true; }
in_git_checkout() {
  local d
  d=$(dirname "$1")
  while [ "$d" != / ]; do
    if [ -e "$d/.git" ]; then return 0; fi
    d=$(dirname "$d")
  done
  return 1
}

yes=0
case "${1:-}" in
  "") ;;
  -y) yes=1 ;;
  *) die "usage: sudo bash $0 [-y]" ;;
esac

[ -f "$repo/docker-compose.yml" ] && [ -d "$repo/stacks" ] || die "$repo doesn't look like the homeserver repo"
docker info >/dev/null 2>&1 || die "can't reach Docker; run with sudo"
if docker compose version >/dev/null 2>&1; then compose=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then compose=(docker-compose)
else die "neither 'docker compose' nor 'docker-compose' is installed"; fi

# Portainer runs compose inside its own container, where its data volume is mounted at /data.
pdata=""
portainer_env=()
portainer=$(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /^portainer\/portainer-(ce|ee)/ {print $1; exit}')
if [ -n "$portainer" ]; then
  pdata=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$portainer")
  while IFS= read -r kv; do
    case ${kv%%=*} in ''|PATH|HOME|HOSTNAME|TERM|PWD|SHLVL) ;; *) portainer_env+=("$kv") ;; esac
  done < <(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$portainer")
fi

# One entry per deployed stack
S_NAME=() S_PROJECT=() S_OWNER=() S_WD=() S_CFG=() S_ENV=() S_NEW=() S_CHANGED=() S_DROP=()

# compose_for <i> <compose file> <compose args...>: run compose for stack i with the stack's variables
compose_for() {
  local i=$1 file=$2 kv
  shift 2
  local args=(-p "${S_PROJECT[i]}" --project-directory "${S_WD[i]}" -f "$file")
  if [ -n "${S_ENV[i]}" ]; then args+=(--env-file "${S_ENV[i]}"); fi
  local extra=()
  if [ "${S_OWNER[i]}" = Portainer ]; then
    # Portainer's own variables, for the ones stack.env doesn't set
    for kv in ${portainer_env[@]+"${portainer_env[@]}"}; do
      if [ -n "${S_ENV[i]}" ] && grep -q "^${kv%%=*}=" "${S_ENV[i]}"; then continue; fi
      extra+=("$kv")
    done
  fi
  env ${extra[@]+"${extra[@]}"} "${compose[@]}" "${args[@]}" "$@"
}

echo "Comparing the stacks running here with $repo"

declare -A seen=()
not_deployed=()
skipped=()
n=0
# The root stack goes last: it restarts Portainer and Traefik.
for new in "$repo"/stacks/*/docker-compose.yml "$repo/docker-compose.yml"; do
  if [ "$new" = "$repo/docker-compose.yml" ]; then name=root; else name=$(basename "$(dirname "$new")"); fi

  project=""
  for c in $(sed -n "s/^[[:space:]]*container_name:[[:space:]]*[\"']\{0,1\}\([^\"' #]*\).*/\1/p" "$new"); do
    project=$(label "$c" com.docker.compose.project)
    if [ -n "$project" ]; then break; fi
  done
  if [ -z "$project" ] && ! grep -q '^[[:space:]]*container_name:' "$new"; then
    # No container_name in the file: look for a compose project named like the folder.
    for p in "$name" "${name//-/_}"; do
      if [ -n "$(docker ps -aq --filter "label=com.docker.compose.project=$p")" ]; then project=$p; break; fi
    done
  fi
  if [ -z "$project" ]; then not_deployed+=("$name"); continue; fi
  cid=$(docker ps -q --filter "label=com.docker.compose.project=$project" | head -n1)
  if [ -z "$cid" ]; then skipped+=("$name: stopped, left alone"); continue; fi
  if [ -n "${seen[$project]:-}" ]; then skipped+=("$name: compose project '$project' is already handled as ${seen[$project]}"); continue; fi
  seen[$project]=$name

  wd=$(label "$cid" com.docker.compose.project.working_dir)
  cfg=$(label "$cid" com.docker.compose.project.config_files)
  case $cfg in *,*) skipped+=("$name: started from several compose files ($cfg), update it by hand"); continue ;; esac
  case $wd in
    /data/compose/*)
      if [ -z "$pdata" ]; then skipped+=("$name: deployed by Portainer, but Portainer isn't running"); continue; fi
      wd="$pdata${wd#/data}"
      cfg="$pdata${cfg#/data}"
      ;;
  esac
  owner=hand
  if [ -n "$pdata" ] && [[ $wd == "$pdata"/compose/* ]]; then owner=Portainer; fi
  if [ ! -f "$cfg" ]; then skipped+=("$name: its compose file $cfg is missing"); continue; fi

  envf=""
  if [ $owner = Portainer ]; then
    for d in "$(dirname "$cfg")" "$wd"; do
      if [ -f "$d/stack.env" ]; then envf="$d/stack.env"; break; fi
    done
  fi
  changed=1
  if [ "$cfg" -ef "$new" ] || cmp -s "$cfg" "$new"; then changed=0; fi
  if [ $owner = hand ] && [ $changed = 1 ] && in_git_checkout "$cfg"; then
    skipped+=("$name: runs from $cfg, which is in another git checkout; update that one with git")
    continue
  fi
  # Portainer saved the old Gluetun image as a stack variable; it would override the version pinned in the file.
  drop=""
  if [ "$name" = media-server ] && [ -n "$envf" ] && grep -q '^GLUETUN_IMAGE=' "$envf"; then drop=GLUETUN_IMAGE; fi

  S_NAME[n]=$name S_PROJECT[n]=$project S_OWNER[n]=$owner S_WD[n]=$wd S_CFG[n]=$cfg
  S_ENV[n]=$envf S_NEW[n]=$new S_CHANGED[n]=$changed S_DROP[n]=$drop
  if ! out=$(compose_for "$n" "$new" config -q 2>&1); then
    skipped+=("$name: the repo's compose file doesn't validate here: $(printf '%s' "$out" | tail -n 3)")
    continue
  fi
  blank=$(printf '%s\n' "$out" | sed -n 's/.*The "\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)"\{0,1\} variable is not set.*/\1/p' | sort -u | tr '\n' ' ')
  if [ -n "$blank" ]; then
    skipped+=("$name: would leave ${blank% } blank; set it in ${envf:-$wd/.env}${envf:+ (or in Portainer)} and run this again")
    continue
  fi
  n=$((n + 1))
done

echo
if [ ${#not_deployed[@]} -gt 0 ]; then echo "Not deployed here: ${not_deployed[*]}"; fi
for s in ${skipped[@]+"${skipped[@]}"}; do echo "Skipped $s"; done
if [ $n = 0 ]; then echo "Nothing to update."; exit 0; fi

for ((i = 0; i < n; i++)); do
  echo
  echo "== ${S_NAME[i]}  (compose project '${S_PROJECT[i]}', deployed by ${S_OWNER[i]})"
  echo "   ${S_CFG[i]}"
  if [ "${S_CHANGED[i]}" = 0 ]; then
    echo "   The file already matches the repo; containers that don't match it are recreated."
  elif command -v diff >/dev/null 2>&1; then
    { diff -u "${S_CFG[i]}" "${S_NEW[i]}" || true; } | tail -n +3 | sed 's/^/   /'
  else
    echo "   The file differs from the repo ('diff' isn't installed to show how)."
  fi
  if [ -n "${S_DROP[i]}" ]; then
    echo "   ${S_DROP[i]} is removed from ${S_ENV[i]}, so the version pinned in the file applies."
  fi
done

if [ $yes = 0 ]; then
  echo
  printf 'Update these %d stack(s)? [y/N] ' "$n"
  read -r answer </dev/tty || die "no terminal to ask on; run with -y"
  case $answer in y|Y|yes) ;; *) echo "Nothing changed."; exit 0 ;; esac
fi

ts=$(date +%Y%m%d-%H%M%S)
ok=()
failed=()
restore=()
for ((i = 0; i < n; i++)); do
  echo
  echo "== ${S_NAME[i]}"
  if [ "${S_CHANGED[i]}" = 1 ]; then
    cp -p "${S_CFG[i]}" "${S_CFG[i]}.bak-$ts"
    cat "${S_NEW[i]}" >"${S_CFG[i]}"   # keeps the file's owner and mode
    restore+=("cp -p '${S_CFG[i]}.bak-$ts' '${S_CFG[i]}'")
  fi
  if [ -n "${S_DROP[i]}" ]; then
    cp -p "${S_ENV[i]}" "${S_ENV[i]}.bak-$ts"
    sed -i "/^${S_DROP[i]}=/d" "${S_ENV[i]}"
    restore+=("cp -p '${S_ENV[i]}.bak-$ts' '${S_ENV[i]}'")
  fi
  if compose_for "$i" "${S_CFG[i]}" up -d; then ok+=("${S_NAME[i]}"); else failed+=("${S_NAME[i]}"); fi
  docker ps -a --filter "label=com.docker.compose.project=${S_PROJECT[i]}" --format '   {{.Names}}  {{.Image}}  {{.Status}}'
done

echo
echo "Updated: ${ok[*]:-none}"
if [ ${#failed[@]} -gt 0 ]; then echo "Failed: ${failed[*]} (see the compose output above)"; fi
if [ ${#restore[@]} -gt 0 ]; then
  echo
  echo "To roll a stack back, restore its files and redeploy it (Portainer: 'Update the stack'):"
  for r in "${restore[@]}"; do echo "  $r"; done
fi
for ((i = 0; i < n; i++)); do
  if [ -n "${S_DROP[i]}" ] && [ "${S_OWNER[i]}" = Portainer ]; then
    echo
    echo "Portainer's saved variables for ${S_NAME[i]} still contain ${S_DROP[i]}. Delete it there"
    echo "before you next use 'Update the stack' in Portainer, or Portainer puts the old image back."
  fi
done
if [ ${#failed[@]} -gt 0 ]; then exit 1; fi

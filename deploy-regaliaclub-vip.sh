#!/usr/bin/env bash
# Deploy all 7 Regalia Club namecards to Hostinger Premium Web Hosting.
# Run from hPanel -> Advanced -> SSH Access (Browser SSH), then paste this whole script.
#
# Optional for private repos (yan-yuxuan-ecard, simone-tesse-ecard):
#   export GITHUB_TOKEN="ghp_your_token_here"
#
# Usage:
#   bash deploy-regaliaclub-vip.sh

set -euo pipefail

DOMAIN="regaliaclub.vip"
ORG="Xenovative"
WORKDIR="${HOME}/.regaliaclub-deploy"
CLONE_ROOT="${WORKDIR}/repos"

log() { printf '[regaliaclub] %s\n' "$1"; }
die() { printf '[regaliaclub] ERROR: %s\n' "$1" >&2; exit 1; }

find_public_html() {
  local candidates=(
    "${HOME}/domains/${DOMAIN}/public_html"
    "${HOME}/public_html/domains/${DOMAIN}/public_html"
    "${HOME}/public_html"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  die "Could not find public_html for ${DOMAIN}. Set WEB_ROOT manually: WEB_ROOT=/path bash $0"
}

WEB_ROOT="${WEB_ROOT:-$(find_public_html)}"
log "Web root: ${WEB_ROOT}"

ensure_command_exists() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command '$1'. Enable SSH/git on your Hostinger plan."
}

ensure_command_exists git
ensure_command_exists rsync

mkdir -p "$CLONE_ROOT"

clone_repo() {
  local repo="$1"
  local branch="$2"
  local dest="${CLONE_ROOT}/${repo}"

  if [[ -d "${dest}/.git" ]]; then
    log "Updating ${repo}..."
    git -C "$dest" fetch origin
    git -C "$dest" reset --hard "origin/${branch}" 2>/dev/null || git -C "$dest" reset --hard "origin/master"
    git -C "$dest" clean -fd
    return 0
  fi

  log "Cloning ${ORG}/${repo} (${branch})..."
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    git clone --depth 1 -b "$branch" \
      "https://x-access-token:${GITHUB_TOKEN}@github.com/${ORG}/${repo}.git" \
      "$dest"
  else
    git clone --depth 1 -b "$branch" \
      "https://github.com/${ORG}/${repo}.git" \
      "$dest" \
      || die "Clone failed for ${repo}. If it is private, export GITHUB_TOKEN first."
  fi
}

sync_stefano() {
  local src="${CLONE_ROOT}/StephenNameCard/Stephen"
  local dest="${WEB_ROOT}/stefano-qiu"
  mkdir -p "$dest"
  rsync -av --delete \
    --include='/index.html' \
    --include='/styles.css' \
    --include='/script.js' \
    --include='/stefano-qiu.vcf' \
    --include='/stefano-profile.png' \
    --include='/composite.png' \
    --include='/highlight-*.png' \
    --include='/layer_*.png' \
    --include='/gt-logo*.png' \
    --include='/goldenthrone-*.jpeg' \
    --include='/img/' \
    --include='/img/***' \
    --exclude='*' \
    "${src}/" "${dest}/"
}

sync_generic() {
  local src="$1"
  local dest="$2"
  shift 2
  local extra_excludes=("$@")

  mkdir -p "$dest"
  local args=(
    -av --delete
    --exclude '.git'
    --exclude '.github'
    --exclude '.gitignore'
    --exclude '.dockerignore'
    --exclude 'Dockerfile'
    --exclude 'docker-compose.yml'
    --exclude 'nginx.conf'
    --exclude 'README.md'
    --exclude '*.sh'
    --exclude '*.ps1'
    --exclude 'deploy*'
    --exclude 'fix-*'
    --exclude 'bootstrap*'
    --exclude 'hostinger*'
    --exclude 'step*'
    --exclude '*.psd'
    --exclude '*.pdf'
  )
  local item
  for item in "${extra_excludes[@]}"; do
    args+=(--exclude "$item")
  done
  rsync "${args[@]}" "${src}/" "${dest}/"
}

sync_landing_page() {
  local src="${CLONE_ROOT}/AndyLanding/regaliaclub-landing"
  [[ -d "$src" ]] || die "Missing ${src}. Pull latest Xenovative/AndyLanding."
  log "Syncing PSD landing page and assets"
  rsync -av \
    "${src}/index.html" \
    "${WEB_ROOT}/"
  rsync -av \
    "${src}/assets/" \
    "${WEB_ROOT}/assets/"
}

main() {
  log "Starting deploy to ${WEB_ROOT}"

  clone_repo "StephenNameCard" "main"
  clone_repo "AndyLanding" "master"
  clone_repo "dr-zulkifli-namecard" "master"
  clone_repo "yan-yuxuan-ecard" "master"
  clone_repo "simone-tesse-ecard" "master"
  clone_repo "haji-m-abdul-aziz-namecard" "main"
  clone_repo "bryan-lee-namecard" "main"

  sync_stefano
  sync_generic "${CLONE_ROOT}/AndyLanding" "${WEB_ROOT}/andy"
  sync_generic "${CLONE_ROOT}/dr-zulkifli-namecard" "${WEB_ROOT}/dr-zulkifli"
  sync_generic "${CLONE_ROOT}/yan-yuxuan-ecard" "${WEB_ROOT}/yan-yuxuan"
  sync_generic "${CLONE_ROOT}/simone-tesse-ecard" "${WEB_ROOT}/simone-tesse"
  sync_generic "${CLONE_ROOT}/haji-m-abdul-aziz-namecard" "${WEB_ROOT}/abdul-aziz"
  sync_generic "${CLONE_ROOT}/bryan-lee-namecard" "${WEB_ROOT}/bryan-lee"

  sync_landing_page

  log "Done. Test these URLs:"
  log "  https://${DOMAIN}/"
  log "  https://${DOMAIN}/stefano-qiu/"
  log "  https://${DOMAIN}/andy/"
  log "  https://${DOMAIN}/dr-zulkifli/"
  log "  https://${DOMAIN}/yan-yuxuan/"
  log "  https://${DOMAIN}/simone-tesse/"
  log "  https://${DOMAIN}/abdul-aziz/"
  log "  https://${DOMAIN}/bryan-lee/"
  log "Enable SSL in hPanel -> Security -> SSL if not already active."
}

main "$@"

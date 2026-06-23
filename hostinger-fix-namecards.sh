#!/usr/bin/env bash
set -euo pipefail

# Incremental fix: namecard (Stefano), card5 (Zulkifli), nginx default-server.
# Paste entire script into Hostinger VPS Terminal as root.
# Set GITHUB_TOKEN below before running.

export GITHUB_TOKEN="PASTE_YOUR_GITHUB_TOKEN_HERE"
export CERTBOT_EMAIL="admin@cyber-beast.tech"
GITHUB_ORG="Xenovative"

log() { printf '[fix] %s\n' "$1"; }
die() { printf '[fix] ERROR: %s\n' "$1" >&2; exit 1; }

sync_repo() {
  local repo_name="$1"
  local branch="${2:-main}"
  local target_dir="$HOME/${repo_name}"
  if [[ -d "${target_dir}/.git" ]]; then
    git -C "$target_dir" fetch origin
    git -C "$target_dir" reset --hard "origin/${branch}" 2>/dev/null || git -C "$target_dir" reset --hard "origin/master"
    git -C "$target_dir" clean -fd
  else
    git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${repo_name}.git" "$target_dir"
  fi
  chmod +x "${target_dir}"/*.sh "${target_dir}"/Stephen/*.sh 2>/dev/null || true
}

[[ -n "$GITHUB_TOKEN" && "$GITHUB_TOKEN" != "PASTE_YOUR_GITHUB_TOKEN_HERE" ]] || die "Set GITHUB_TOKEN on line 7"

log "Pulling latest repos..."
sync_repo "AndyLanding" "master"
sync_repo "StephenNameCard" "main"
sync_repo "dr-zulkifli-namecard" "master"
sync_repo "CBTNamecard" "main"

log "Deploying Stefano -> namecard.cyber-beast.tech"
"$HOME/StephenNameCard/Stephen/deploy-ssl.sh" --email "$CERTBOT_EMAIL"

log "Re-deploying Andy -> card3.cyber-beast.tech"
"$HOME/AndyLanding/deploy-ssl.sh" --email "$CERTBOT_EMAIL"

log "Deploying Zulkifli -> card5.cyber-beast.tech"
"$HOME/dr-zulkifli-namecard/deploy-ssl.sh" --email "$CERTBOT_EMAIL"

log "Re-deploying CBT -> director.cyber-beast.tech"
"$HOME/CBTNamecard/deploy-ssl.sh" --email "$CERTBOT_EMAIL"

log "Fixing nginx default-server fallback"
"$HOME/AndyLanding/fix-nginx-default.sh"

log "Done."
log "  https://namecard.cyber-beast.tech  (Stefano)"
log "  https://card3.cyber-beast.tech  (Andy)"
log "  https://card5.cyber-beast.tech  (Zulkifli)"
log "  https://director.cyber-beast.tech  (CBT)"

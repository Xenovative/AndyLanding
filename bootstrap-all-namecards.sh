#!/usr/bin/env bash
set -euo pipefail

# One-shot deploy for Xenovative namecards on cyber-beast.tech VPS.
# Run from Hostinger Browser Terminal (hPanel -> VPS -> Terminal) as root.
#
# Live URLs after success:
#   https://card1.cyber-beast.tech      Stefano Qiu
#   https://card3.cyber-beast.tech      Andy / Golden Throne
#   https://card5.cyber-beast.tech      Dr. Zulkifli Hasan
#   https://director.cyber-beast.tech   CBT / Ansgar Yeung

CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@cyber-beast.tech}"
GITHUB_ORG="Xenovative"

log() { printf '[bootstrap] %s\n' "$1"; }
die() { printf '[bootstrap] ERROR: %s\n' "$1" >&2; exit 1; }

ensure_command_exists() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

sync_repo() {
  local repo_name="$1"
  local branch="${2:-main}"
  local target_dir="$HOME/${repo_name}"

  if [[ -d "${target_dir}/.git" ]]; then
    log "Updating ${repo_name} in ${target_dir}"
    git -C "$target_dir" fetch origin
    git -C "$target_dir" reset --hard "origin/${branch}" 2>/dev/null \
      || git -C "$target_dir" reset --hard "origin/master"
    git -C "$target_dir" clean -fd
    return 0
  fi

  log "Cloning ${GITHUB_ORG}/${repo_name} -> ${target_dir}"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${repo_name}.git" "$target_dir"
  else
    git clone "https://github.com/${GITHUB_ORG}/${repo_name}.git" "$target_dir" \
      || die "Clone failed for ${repo_name}. Export GITHUB_TOKEN for private repos."
  fi
}

chmod_scripts() {
  local dir="$1"
  chmod +x \
    "${dir}/deploy-ssl.sh" \
    "${dir}/sync-site.sh" \
    "${dir}/fix-dns.sh" \
    "${dir}/fix-nginx-default.sh" \
    2>/dev/null || true
}

install_ssh_deploy_key() {
  local pubkey="${DEPLOY_PUBKEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5eF9Q+HVj+vlJU+2FnANNhSq8j6pW5lDeIU/v5wIzI cheesechiu@gmail.com}"
  local authorized_keys="/root/.ssh/authorized_keys"

  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  touch "$authorized_keys"
  chmod 600 "$authorized_keys"

  if grep -qF "$pubkey" "$authorized_keys" 2>/dev/null; then
    log "Deploy SSH key already installed"
    return 0
  fi

  printf '%s\n' "$pubkey" >> "$authorized_keys"
  log "Installed deploy SSH public key for GitHub Actions"
}

main() {
  ensure_command_exists git
  ensure_command_exists rsync
  ensure_command_exists nginx
  ensure_command_exists certbot

  log "Starting Xenovative namecard bootstrap"

  install_ssh_deploy_key

  sync_repo "AndyLanding" "master"
  sync_repo "CBTNamecard" "main"
  sync_repo "StephenNameCard" "main"
  sync_repo "dr-zulkifli-namecard" "master"

  chmod_scripts "$HOME/AndyLanding"
  chmod_scripts "$HOME/CBTNamecard"
  chmod_scripts "$HOME/StephenNameCard/Stephen"
  chmod_scripts "$HOME/dr-zulkifli-namecard"

  log "Deploying Stefano Qiu -> card1.cyber-beast.tech"
  if [[ -x "$HOME/StephenNameCard/Stephen/fix-dns.sh" ]]; then
    "$HOME/StephenNameCard/Stephen/fix-dns.sh" || log "DNS step for card1 reported issues; continuing"
  fi
  "$HOME/StephenNameCard/Stephen/deploy-ssl.sh" --email "$CERTBOT_EMAIL"

  log "Deploying Andy -> card3.cyber-beast.tech"
  if [[ -x "$HOME/AndyLanding/fix-dns.sh" ]]; then
    "$HOME/AndyLanding/fix-dns.sh" || log "DNS step for card3 reported issues; continuing"
  fi
  "$HOME/AndyLanding/deploy-ssl.sh" --email "$CERTBOT_EMAIL"

  log "Deploying Dr. Zulkifli -> card5.cyber-beast.tech"
  if [[ -x "$HOME/dr-zulkifli-namecard/fix-dns.sh" ]]; then
    "$HOME/dr-zulkifli-namecard/fix-dns.sh" || log "DNS step for card5 reported issues; continuing"
  fi
  "$HOME/dr-zulkifli-namecard/deploy-ssl.sh" --email "$CERTBOT_EMAIL"

  log "Deploying CBT -> director.cyber-beast.tech"
  "$HOME/CBTNamecard/deploy-ssl.sh" --email "$CERTBOT_EMAIL"

  log "Fixing nginx default-server fallback"
  if [[ -x "$HOME/AndyLanding/fix-nginx-default.sh" ]]; then
    "$HOME/AndyLanding/fix-nginx-default.sh"
  fi

  log "Verifying live pages..."
  for pair in \
    "card1.cyber-beast.tech|Stefano Qiu" \
    "card3.cyber-beast.tech|Golden Throne" \
    "card5.cyber-beast.tech|Zulkifli Hasan" \
    "director.cyber-beast.tech|Ansgar Yeung"
  do
    domain="${pair%%|*}"
    expected="${pair##*|}"
    title="$(curl -fsSL "https://${domain}/" 2>/dev/null | sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p' | head -n 1 || true)"
    if [[ "$title" == *"$expected"* ]]; then
      log "OK  https://${domain} -> ${title}"
    else
      log "WARN https://${domain} title='${title:-<empty>}' (expected '${expected}')"
    fi
  done

  log "Bootstrap complete."
  log "  Stefano:   https://card1.cyber-beast.tech"
  log "  Andy:      https://card3.cyber-beast.tech"
  log "  Zulkifli:  https://card5.cyber-beast.tech"
  log "  CBT:       https://director.cyber-beast.tech"
}

main "$@"

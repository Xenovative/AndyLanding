#!/usr/bin/env bash
set -euo pipefail

# One-shot fix: reset repo, fix DNS, fix SSL for card3.cyber-beast.tech
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/CheesyErwin/AndyLanding/master/bootstrap-fix.sh | bash
# Or on VPS:
#   cd ~/AndyLanding && git fetch origin && git reset --hard origin/master && ./bootstrap-fix.sh

REPO_DIR="${REPO_DIR:-$HOME/AndyLanding}"
REPO_URL="https://github.com/CheesyErwin/AndyLanding.git"
CERTBOT_EMAIL="admin@cyber-beast.tech"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)
      CERTBOT_EMAIL="${2:-}"
      shift 2
      ;;
    --email=*)
      CERTBOT_EMAIL="${1#*=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

log() { printf '[bootstrap] %s\n' "$1"; }

sync_repo() {
  if [[ -d "$REPO_DIR/.git" ]]; then
    log "Resetting ${REPO_DIR} to latest GitHub version"
    cd "$REPO_DIR"
    git fetch origin
    git reset --hard origin/master
    git clean -fd
  else
    log "Cloning ${REPO_URL} -> ${REPO_DIR}"
    rm -rf "$REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
  fi
}

main() {
  log "Andy namecard bootstrap fix starting"

  sync_repo

  chmod +x fix-dns.sh fix-cert.sh deploy-ssl.sh sync-site.sh fix-all.sh bootstrap-fix.sh fix-delegation.sh step1-setup-nameservers.sh 2>/dev/null || true

  log "Step 1/4: Nameserver setup (server + registrar instructions)"
  ./step1-setup-nameservers.sh || log "Nameserver setup reported issues"

  log "Step 2/4: DNS delegation check"
  ./fix-delegation.sh || log "Delegation still needs registrar update"

  log "Step 3/4: DNS records on Hestia"
  ./fix-dns.sh || log "DNS step reported issues; continuing"

  log "Step 4/4: SSL"
  ./fix-cert.sh --email "$CERTBOT_EMAIL"

  log "Finished. Open https://card3.cyber-beast.tech"
}

main "$@"

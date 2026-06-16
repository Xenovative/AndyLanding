#!/usr/bin/env bash
set -euo pipefail

# Fix Certbot/Nginx using the WRONG domain card3.cyber.beast.tech (dot).
# Correct domain: card3.cyber-beast.tech (hyphen)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRONG_DOMAIN="card3.cyber.beast.tech"
SITE_DOMAIN="card3.cyber-beast.tech"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@cyber-beast.tech}"

log() { printf '[fix-cert] %s\n' "$1"; }
die() { printf '[fix-cert] ERROR: %s\n' "$1" >&2; exit 1; }

cleanup_wrong_domain() {
  log "Removing wrong-domain configs for ${WRONG_DOMAIN}"

  rm -f "/etc/nginx/sites-enabled/${WRONG_DOMAIN}.conf"
  rm -f "/etc/nginx/sites-available/${WRONG_DOMAIN}.conf"
  rm -rf "/var/www/${WRONG_DOMAIN}"

  if [[ -d "/etc/letsencrypt/live/${WRONG_DOMAIN}" ]]; then
    log "Deleting failed cert data for ${WRONG_DOMAIN}"
    certbot delete --cert-name "$WRONG_DOMAIN" --non-interactive 2>/dev/null || true
  fi

  if [[ -d "/etc/letsencrypt/renewal/${WRONG_DOMAIN}.conf" ]]; then
    rm -f "/etc/letsencrypt/renewal/${WRONG_DOMAIN}.conf"
  fi
}

ensure_correct_deploy_script() {
  log "Pulling latest repo (must use ${SITE_DOMAIN})"
  cd "$SCRIPT_DIR"
  git pull --ff-only

  if grep -q "$WRONG_DOMAIN" "$SCRIPT_DIR/deploy-ssl.sh"; then
    die "deploy-ssl.sh still contains ${WRONG_DOMAIN}. Repo update failed."
  fi

  if ! grep -q "$SITE_DOMAIN" "$SCRIPT_DIR/deploy-ssl.sh"; then
    die "deploy-ssl.sh missing ${SITE_DOMAIN}."
  fi

  log "deploy-ssl.sh domain check OK: ${SITE_DOMAIN}"
}

check_dns() {
  local resolved

  resolved="$(dig @8.8.8.8 +short "$SITE_DOMAIN" A 2>/dev/null | head -n 1 || true)"
  if [[ -z "$resolved" ]]; then
    die "DNS for ${SITE_DOMAIN} is empty. Run ./fix-dns.sh first, then retry."
  fi

  log "Public DNS: ${SITE_DOMAIN} -> ${resolved}"
}

ensure_nginx_running() {
  nginx -t
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx
  else
    systemctl start nginx
    systemctl enable nginx
  fi
}

main() {
  if [[ "${1:-}" == "--email" && -n "${2:-}" ]]; then
    CERTBOT_EMAIL="$2"
    shift 2
  elif [[ "${1:-}" == --email=* ]]; then
    CERTBOT_EMAIL="${1#*=}"
    shift
  fi

  log "Fixing SSL for ${SITE_DOMAIN} (NOT ${WRONG_DOMAIN})"

  cleanup_wrong_domain
  ensure_correct_deploy_script
  check_dns
  ensure_nginx_running

  chmod +x deploy-ssl.sh sync-site.sh fix-dns.sh fix-cert.sh fix-all.sh
  ./deploy-ssl.sh --email "$CERTBOT_EMAIL"

  log "Done. Test: curl -sI https://${SITE_DOMAIN} | head"
}

main "$@"

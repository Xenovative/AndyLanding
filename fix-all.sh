#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_DOMAIN="card3.cyber-beast.tech"
WRONG_DOMAIN="card3.cyber.beast.tech"
PARENT_DOMAIN="cyber-beast.tech"
RECORD_NAME="card3"
VPS_IPV4="${VPS_IPV4:-89.116.111.157}"
VPS_IPV6="${VPS_IPV6:-2a02:4780:28:84a4::1}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@cyber-beast.tech}"
HESTIA_BIN="/usr/local/hestia/bin"

log() {
  printf '[fix-all] %s\n' "$1"
}

die() {
  printf '[fix-all] ERROR: %s\n' "$1" >&2
  exit 1
}

find_hestia_user() {
  if [[ ! -d "$HESTIA_BIN" ]]; then
    return 1
  fi

  if "$HESTIA_BIN/v-search-domain-owner" "$PARENT_DOMAIN" >/dev/null 2>&1; then
    "$HESTIA_BIN/v-search-domain-owner" "$PARENT_DOMAIN"
    return 0
  fi

  if "$HESTIA_BIN/v-search-domain-owner" "dns" "$PARENT_DOMAIN" >/dev/null 2>&1; then
    "$HESTIA_BIN/v-search-domain-owner" "dns" "$PARENT_DOMAIN"
    return 0
  fi

  return 1
}

fix_hestia_dns() {
  local hestia_user="$1"
  local record_id

  log "Updating Hestia DNS for ${RECORD_NAME}.${PARENT_DOMAIN} under user '${hestia_user}'"

  while read -r record_id; do
    [[ -z "$record_id" ]] && continue
    log "Removing old DNS record id=${record_id}"
    "$HESTIA_BIN/v-delete-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$record_id" yes || true
  done < <(
    "$HESTIA_BIN/v-list-dns-records" "$hestia_user" "$PARENT_DOMAIN" plain 2>/dev/null \
      | awk -v name="$RECORD_NAME" '$2 == name && ($3 == "A" || $3 == "AAAA") { print $1 }'
  )

  log "Adding A record ${RECORD_NAME} -> ${VPS_IPV4}"
  "$HESTIA_BIN/v-add-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$RECORD_NAME" A "$VPS_IPV4"

  log "Adding AAAA record ${RECORD_NAME} -> ${VPS_IPV6}"
  "$HESTIA_BIN/v-add-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$RECORD_NAME" AAAA "$VPS_IPV6"
}

cleanup_wrong_nginx_configs() {
  log "Removing wrong-domain Nginx configs (if any)"
  rm -f "/etc/nginx/sites-enabled/${WRONG_DOMAIN}.conf"
  rm -f "/etc/nginx/sites-available/${WRONG_DOMAIN}.conf"
  rm -rf "/var/www/${WRONG_DOMAIN}"
}

ensure_nginx_running() {
  log "Ensuring Nginx is running"
  nginx -t
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx
  else
    systemctl start nginx
    systemctl enable nginx
  fi
}

wait_for_dns() {
  local attempt resolved_ip

  log "Waiting for DNS ${SITE_DOMAIN} -> ${VPS_IPV4}"
  for attempt in $(seq 1 12); do
    resolved_ip="$(dig @8.8.8.8 +short "$SITE_DOMAIN" A 2>/dev/null | head -n 1 || true)"
    if [[ "$resolved_ip" == "$VPS_IPV4" ]]; then
      log "DNS looks correct: ${SITE_DOMAIN} -> ${resolved_ip}"
      return 0
    fi
    log "Attempt ${attempt}/12: currently '${resolved_ip:-<empty>}', waiting 10s..."
    sleep 10
  done

  log "DNS is not pointing to ${VPS_IPV4} yet. Continuing anyway; SSL may fail until DNS propagates."
}

main() {
  local hestia_user=""

  if [[ "${1:-}" == "--email" && -n "${2:-}" ]]; then
    CERTBOT_EMAIL="$2"
    shift 2
  elif [[ "${1:-}" == --email=* ]]; then
    CERTBOT_EMAIL="${1#*=}"
    shift
  fi

  log "Starting full fix for ${SITE_DOMAIN}"

  if hestia_user="$(find_hestia_user)"; then
    fix_hestia_dns "$hestia_user"
  else
    log "Hestia DNS owner not found automatically. Skipping DNS update."
    log "Manually point ${SITE_DOMAIN} to ${VPS_IPV4} before SSL can succeed."
  fi

  cleanup_wrong_nginx_configs
  ensure_nginx_running
  wait_for_dns

  log "Pulling latest deploy files"
  cd "$SCRIPT_DIR"
  git pull --ff-only

  chmod +x deploy-ssl.sh sync-site.sh fix-all.sh
  ./deploy-ssl.sh --email "$CERTBOT_EMAIL"

  log "Done. Open https://${SITE_DOMAIN}"
}

main "$@"

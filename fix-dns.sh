#!/usr/bin/env bash
set -euo pipefail

# Fixes public DNS for Andy namecard on Hestia VPS.
# Correct domain: card3.cyber-beast.tech  (hyphen, NOT cyber.beast.tech)

PARENT_DOMAIN="cyber-beast.tech"
SITE_DOMAIN="card3.cyber-beast.tech"
RECORD_NAME="card3"
VPS_IPV4="${VPS_IPV4:-89.116.111.157}"
VPS_IPV6="${VPS_IPV6:-2a02:4780:28:84a4::1}"
HESTIA_BIN="/usr/local/hestia/bin"

log() { printf '[fix-dns] %s\n' "$1"; }
die() { printf '[fix-dns] ERROR: %s\n' "$1" >&2; exit 1; }

[[ -d "$HESTIA_BIN" ]] || die "Hestia not found at ${HESTIA_BIN}"

find_hestia_user() {
  local owner=""

  for cmd in \
    "$HESTIA_BIN/v-search-domain-owner $PARENT_DOMAIN" \
    "$HESTIA_BIN/v-search-domain-owner dns $PARENT_DOMAIN" \
    "$HESTIA_BIN/v-search-domain-owner web $PARENT_DOMAIN"
  do
    owner="$(bash -c "$cmd" 2>/dev/null || true)"
    if [[ -n "$owner" && "$owner" != "Error:"* ]]; then
      printf '%s\n' "$owner"
      return 0
    fi
  done

  log "Could not auto-detect owner. Available users:"
  "$HESTIA_BIN/v-list-users" plain || true
  die "Run: HESTIA_USER=youruser $0"
}

ensure_dns_zone() {
  local hestia_user="$1"

  if "$HESTIA_BIN/v-list-dns-domains" "$hestia_user" plain 2>/dev/null | awk '{print $1}' | grep -Fxq "$PARENT_DOMAIN"; then
    log "DNS zone ${PARENT_DOMAIN} already exists for user ${hestia_user}"
    return 0
  fi

  log "Adding DNS zone ${PARENT_DOMAIN} for user ${hestia_user}"
  "$HESTIA_BIN/v-add-dns-domain" "$hestia_user" "$PARENT_DOMAIN" "$VPS_IPV4"
}

remove_old_card3_records() {
  local hestia_user="$1"
  local record_id

  while read -r record_id; do
    [[ -z "$record_id" ]] && continue
    log "Deleting old record id=${record_id}"
    "$HESTIA_BIN/v-delete-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$record_id" yes || true
  done < <(
    "$HESTIA_BIN/v-list-dns-records" "$hestia_user" "$PARENT_DOMAIN" plain 2>/dev/null \
      | awk -v name="$RECORD_NAME" 'NR > 1 && $2 == name && ($3 == "A" || $3 == "AAAA") { print $1 }'
  )
}

add_card3_records() {
  local hestia_user="$1"

  log "Adding A     ${RECORD_NAME}.${PARENT_DOMAIN} -> ${VPS_IPV4}"
  "$HESTIA_BIN/v-add-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$RECORD_NAME" A "$VPS_IPV4"

  log "Adding AAAA  ${RECORD_NAME}.${PARENT_DOMAIN} -> ${VPS_IPV6}"
  "$HESTIA_BIN/v-add-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$RECORD_NAME" AAAA "$VPS_IPV6"
}

show_records() {
  local hestia_user="$1"

  log "Current Hestia DNS records for ${PARENT_DOMAIN}:"
  "$HESTIA_BIN/v-list-dns-records" "$hestia_user" "$PARENT_DOMAIN" plain || true
}

verify_public_dns() {
  local attempt resolved

  log "Verifying public DNS (Google 8.8.8.8)..."
  for attempt in $(seq 1 18); do
    resolved="$(dig @8.8.8.8 +short "$SITE_DOMAIN" A 2>/dev/null | head -n 1 || true)"
    if [[ "$resolved" == "$VPS_IPV4" ]]; then
      log "SUCCESS: ${SITE_DOMAIN} -> ${resolved}"
      return 0
    fi
    log "Attempt ${attempt}/18: public DNS='${resolved:-<empty>}' (want ${VPS_IPV4})"
    sleep 10
  done

  log "Public DNS is not updated yet."
  log "If this stays empty, update DNS at your domain registrar for zone: ${PARENT_DOMAIN}"
  log "Add record: ${RECORD_NAME}  A  ${VPS_IPV4}"
  log "Add record: ${RECORD_NAME}  AAAA  ${VPS_IPV6}"
  return 1
}

main() {
  local hestia_user="${HESTIA_USER:-}"

  log "Fixing DNS for ${SITE_DOMAIN}"
  log "NOTE: Use cyber-beast.tech (hyphen). cyber.beast.tech does NOT exist in public DNS."

  if [[ -z "$hestia_user" ]]; then
    hestia_user="$(find_hestia_user)"
  fi

  log "Using Hestia user: ${hestia_user}"

  ensure_dns_zone "$hestia_user"
  remove_old_card3_records "$hestia_user"
  add_card3_records "$hestia_user"
  show_records "$hestia_user"

  if verify_public_dns; then
    log "DNS is ready. Run SSL deploy next:"
    log "  cd ~/AndyLanding && ./deploy-ssl.sh --email admin@cyber-beast.tech"
  else
    log "Hestia records were updated, but public DNS still needs time or registrar fix."
  fi
}

main "$@"

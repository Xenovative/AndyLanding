#!/usr/bin/env bash
set -euo pipefail

# Step 1 (server side): configure Hestia nameservers + glue records for cyber-beast.tech
# Then copy the printed nameservers into your domain REGISTRAR panel.
#
# Usage:
#   cd ~/AndyLanding && git pull && chmod +x step1-setup-nameservers.sh && ./step1-setup-nameservers.sh

PARENT_DOMAIN="cyber-beast.tech"
SITE_DOMAIN="card3.cyber-beast.tech"
RECORD_NAME="card3"
VPS_IPV4="${VPS_IPV4:-89.116.111.157}"
VPS_IPV6="${VPS_IPV6:-2a02:4780:28:84a4::1}"
HESTIA_BIN="/usr/local/hestia/bin"
HESTIA_CONF="/usr/local/hestia/conf/hestia.conf"

log() { printf '[step1-ns] %s\n' "$1"; }
warn() { printf '[step1-ns] WARNING: %s\n' "$1"; }
die() { printf '[step1-ns] ERROR: %s\n' "$1" >&2; exit 1; }

[[ -d "$HESTIA_BIN" ]] || die "Hestia not found at ${HESTIA_BIN}"

find_hestia_user() {
  local owner=""

  if [[ -n "${HESTIA_USER:-}" ]]; then
    printf '%s\n' "$HESTIA_USER"
    return 0
  fi

  owner="$("$HESTIA_BIN/v-search-domain-owner" "$PARENT_DOMAIN" 2>/dev/null || true)"
  if [[ -n "$owner" && "$owner" != Error:* ]]; then
    printf '%s\n' "$owner"
    return 0
  fi

  owner="$("$HESTIA_BIN/v-search-domain-owner" dns "$PARENT_DOMAIN" 2>/dev/null || true)"
  if [[ -n "$owner" && "$owner" != Error:* ]]; then
    printf '%s\n' "$owner"
    return 0
  fi

  log "Available Hestia users:"
  "$HESTIA_BIN/v-list-users" plain || true
  die "Set HESTIA_USER=youruser and run again"
}

read_current_ns() {
  NS1=""
  NS2=""
  NS3=""
  NS4=""

  if [[ -f "$HESTIA_CONF" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
        NS1|NS2|NS3|NS4) printf -v "$key" '%s' "$value" ;;
      esac
    done < <(grep -E '^NS[1-4]=' "$HESTIA_CONF" 2>/dev/null || true)
  fi
}

set_default_nameservers_if_missing() {
  local default_ns1="ns1.${PARENT_DOMAIN}"
  local default_ns2="ns2.${PARENT_DOMAIN}"

  read_current_ns

  if [[ -z "${NS1:-}" || -z "${NS2:-}" ]]; then
    log "Setting Hestia nameservers to ${default_ns1} and ${default_ns2}"
    "$HESTIA_BIN/v-change-sys-config-value" 'NS1' "$default_ns1"
    "$HESTIA_BIN/v-change-sys-config-value" 'NS2' "$default_ns2"
    read_current_ns
  else
    log "Hestia nameservers already configured"
  fi
}

ensure_dns_zone() {
  local hestia_user="$1"

  if ! "$HESTIA_BIN/v-list-dns-domains" "$hestia_user" plain 2>/dev/null | awk '{print $1}' | grep -Fxq "$PARENT_DOMAIN"; then
    log "Creating DNS zone ${PARENT_DOMAIN}"
    "$HESTIA_BIN/v-add-dns-domain" "$hestia_user" "$PARENT_DOMAIN" "$VPS_IPV4"
  else
    log "DNS zone ${PARENT_DOMAIN} already exists"
  fi
}

upsert_a_record() {
  local hestia_user="$1"
  local host="$2"
  local ip="$3"
  local record_id

  while read -r record_id; do
    [[ -z "$record_id" ]] && continue
    "$HESTIA_BIN/v-delete-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$record_id" yes || true
  done < <(
    "$HESTIA_BIN/v-list-dns-records" "$hestia_user" "$PARENT_DOMAIN" plain 2>/dev/null \
      | awk -v name="$host" 'NR > 1 && $2 == name && $3 == "A" { print $1 }'
  )

  log "Adding A  ${host}.${PARENT_DOMAIN} -> ${ip}"
  "$HESTIA_BIN/v-add-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$host" A "$ip"
}

upsert_aaaa_record() {
  local hestia_user="$1"
  local host="$2"
  local ip="$3"
  local record_id

  while read -r record_id; do
    [[ -z "$record_id" ]] && continue
    "$HESTIA_BIN/v-delete-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$record_id" yes || true
  done < <(
    "$HESTIA_BIN/v-list-dns-records" "$hestia_user" "$PARENT_DOMAIN" plain 2>/dev/null \
      | awk -v name="$host" 'NR > 1 && $2 == name && $3 == "AAAA" { print $1 }'
  )

  log "Adding AAAA  ${host}.${PARENT_DOMAIN} -> ${ip}"
  "$HESTIA_BIN/v-add-dns-record" "$hestia_user" "$PARENT_DOMAIN" "$host" AAAA "$ip"
}

ensure_required_records() {
  local hestia_user="$1"

  read_current_ns

  # Glue records for nameserver hostnames (required when using ns1.domain / ns2.domain)
  if [[ -n "${NS1:-}" && "$NS1" == *".${PARENT_DOMAIN}" ]]; then
    upsert_a_record "$hestia_user" "${NS1%%.${PARENT_DOMAIN}}" "$VPS_IPV4"
  fi
  if [[ -n "${NS2:-}" && "$NS2" == *".${PARENT_DOMAIN}" ]]; then
    upsert_a_record "$hestia_user" "${NS2%%.${PARENT_DOMAIN}}" "$VPS_IPV4"
  fi

  upsert_a_record "$hestia_user" "$RECORD_NAME" "$VPS_IPV4"
  upsert_aaaa_record "$hestia_user" "$RECORD_NAME" "$VPS_IPV6"

  # Apex/root record helps some setups
  upsert_a_record "$hestia_user" "@" "$VPS_IPV4" || true
}

show_zone() {
  local hestia_user="$1"
  log "Hestia DNS records for ${PARENT_DOMAIN}:"
  "$HESTIA_BIN/v-list-dns-records" "$hestia_user" "$PARENT_DOMAIN" plain || true
}

show_public_status() {
  log "Current PUBLIC nameservers for ${PARENT_DOMAIN}:"
  dig @8.8.8.8 +short NS "$PARENT_DOMAIN" | sort -u || true
  log "Current PUBLIC A record for ${SITE_DOMAIN}:"
  dig @8.8.8.8 +short A "$SITE_DOMAIN" || true
}

print_registrar_step1() {
  read_current_ns

  cat <<EOF

============================================================
STEP 1 — COPY THESE INTO YOUR DOMAIN REGISTRAR
Domain: ${PARENT_DOMAIN}
============================================================

1) Log in to your domain registrar (where you bought ${PARENT_DOMAIN})

2) Open: DNS / Nameservers / Manage nameservers

3) REMOVE parking nameservers:
   - ns1.dns-parking.com
   - ns2.dns-parking.com

4) SET custom nameservers to EXACTLY:
EOF

  [[ -n "${NS1:-}" ]] && printf '   - %s\n' "$NS1"
  [[ -n "${NS2:-}" ]] && printf '   - %s\n' "$NS2"
  [[ -n "${NS3:-}" ]] && printf '   - %s\n' "$NS3"
  [[ -n "${NS4:-}" ]] && printf '   - %s\n' "$NS4"

  cat <<EOF

5) Save changes and wait 15-60 minutes (sometimes up to 24h)

6) Verify on VPS:
   dig @8.8.8.8 +short NS ${PARENT_DOMAIN}
   dig @8.8.8.8 +short A ${SITE_DOMAIN}

   Expected A result: ${VPS_IPV4}

7) When A record is correct, run SSL:
   cd ~/AndyLanding && ./fix-cert.sh --email admin@cyber-beast.tech

============================================================
EOF
}

main() {
  local hestia_user

  log "Step 1 server setup for ${PARENT_DOMAIN}"

  hestia_user="$(find_hestia_user)"
  log "Using Hestia user: ${hestia_user}"

  set_default_nameservers_if_missing
  ensure_dns_zone "$hestia_user"
  ensure_required_records "$hestia_user"
  show_zone "$hestia_user"
  show_public_status
  print_registrar_step1

  log "Server-side Step 1 complete. Now update nameservers at registrar (instructions above)."
}

main "$@"

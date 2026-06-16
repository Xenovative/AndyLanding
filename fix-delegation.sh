#!/usr/bin/env bash
set -euo pipefail

# Diagnose and prepare DNS delegation for cyber-beast.tech on Hestia VPS.
# Delegation must be fixed at your domain REGISTRAR (cannot be fixed by Nginx/Certbot alone).

PARENT_DOMAIN="cyber-beast.tech"
SITE_DOMAIN="card3.cyber-beast.tech"
RECORD_NAME="card3"
VPS_IPV4="${VPS_IPV4:-89.116.111.157}"
VPS_IPV6="${VPS_IPV6:-2a02:4780:28:84a4::1}"
HESTIA_BIN="/usr/local/hestia/bin"
HESTIA_CONF="/usr/local/hestia/conf/hestia.conf"

log() { printf '[fix-delegation] %s\n' "$1"; }
section() { printf '\n=== %s ===\n' "$1"; }

read_hestia_ns() {
  local key value
  NS1=""
  NS2=""
  NS3=""
  NS4=""

  if [[ -f "$HESTIA_CONF" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
        NS1|NS2|NS3|NS4)
          printf -v "$key" '%s' "$value"
          ;;
      esac
    done < <(grep -E '^NS[1-4]=' "$HESTIA_CONF" 2>/dev/null || true)
  fi
}

show_public_delegation() {
  section "Current public nameservers for ${PARENT_DOMAIN}"
  dig @8.8.8.8 +short NS "$PARENT_DOMAIN" | sort -u || true

  section "Current public A record for ${SITE_DOMAIN}"
  dig @8.8.8.8 +short A "$SITE_DOMAIN" || true
  dig @8.8.8.8 +short AAAA "$SITE_DOMAIN" || true
}

show_hestia_nameservers() {
  read_hestia_ns
  section "Nameservers configured on THIS Hestia server"
  [[ -n "${NS1:-}" ]] && printf 'NS1=%s\n' "$NS1"
  [[ -n "${NS2:-}" ]] && printf 'NS2=%s\n' "$NS2"
  [[ -n "${NS3:-}" ]] && printf 'NS3=%s\n' "$NS3"
  [[ -n "${NS4:-}" ]] && printf 'NS4=%s\n' "$NS4"

  if [[ -z "${NS1:-}" && -z "${NS2:-}" ]]; then
    log "Could not read NS from ${HESTIA_CONF}"
    log "Check Hestia panel: Server -> Configure -> Server Settings -> Nameservers"
  fi
}

ensure_hestia_zone_records() {
  local hestia_user="${HESTIA_USER:-}"

  [[ -d "$HESTIA_BIN" ]] || return 0

  if [[ -z "$hestia_user" ]]; then
    hestia_user="$("$HESTIA_BIN/v-search-domain-owner" "$PARENT_DOMAIN" 2>/dev/null || true)"
    if [[ -z "$hestia_user" || "$hestia_user" == Error:* ]]; then
      hestia_user="$("$HESTIA_BIN/v-search-domain-owner" dns "$PARENT_DOMAIN" 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$hestia_user" || "$hestia_user" == Error:* ]]; then
    log "Skipping Hestia zone sync (owner not found). Set HESTIA_USER=youruser if needed."
    return 0
  fi

  section "Ensuring Hestia DNS zone records for user: ${hestia_user}"

  if ! "$HESTIA_BIN/v-list-dns-domains" "$hestia_user" plain 2>/dev/null | awk '{print $1}' | grep -Fxq "$PARENT_DOMAIN"; then
    log "Creating DNS zone ${PARENT_DOMAIN}"
    "$HESTIA_BIN/v-add-dns-domain" "$hestia_user" "$PARENT_DOMAIN" "$VPS_IPV4"
  fi

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "$SCRIPT_DIR/fix-dns.sh" ]]; then
    HESTIA_USER="$hestia_user" "$SCRIPT_DIR/fix-dns.sh" || true
  fi
}

print_registrar_instructions() {
  read_hestia_ns

  section "WHAT YOU MUST CHANGE AT YOUR DOMAIN REGISTRAR"
  cat <<EOF
Problem:
  ${PARENT_DOMAIN} currently uses parking nameservers (ns1.dns-parking.com / ns2.dns-parking.com).
  Public DNS does NOT read records from this VPS until nameservers are updated.

Fix at registrar for ${PARENT_DOMAIN}:

  1) Open your domain registrar DNS / Nameserver settings for ${PARENT_DOMAIN}

  2) Replace parking nameservers with THIS server's nameservers:
EOF

  [[ -n "${NS1:-}" ]] && printf '     - %s\n' "$NS1"
  [[ -n "${NS2:-}" ]] && printf '     - %s\n' "$NS2"
  [[ -n "${NS3:-}" ]] && printf '     - %s\n' "$NS3"
  [[ -n "${NS4:-}" ]] && printf '     - %s\n' "$NS4"

  if [[ -z "${NS1:-}" && -z "${NS2:-}" ]]; then
    cat <<EOF
     (Run this script again after setting NS in Hestia, or copy NS from:
      Hestia panel -> Server -> Configure -> Server Settings)
EOF
  fi

  cat <<EOF

  3) After NS propagation, this zone on the VPS must contain:

     ${RECORD_NAME}.${PARENT_DOMAIN}   A      ${VPS_IPV4}
     ${RECORD_NAME}.${PARENT_DOMAIN}   AAAA   ${VPS_IPV6}

  4) Verify (repeat until correct):

     dig @8.8.8.8 +short NS ${PARENT_DOMAIN}
     dig @8.8.8.8 +short A ${SITE_DOMAIN}

  5) When A record shows ${VPS_IPV4}, run SSL:

     cd ~/AndyLanding && ./fix-cert.sh --email admin@cyber-beast.tech

EOF

  section "Alternative (if you cannot change nameservers yet)"
  cat <<EOF
If you must keep dns-parking nameservers for now, add this record
in the PARKING DNS panel (not Hestia):

  Host: card3
  Type: A
  Value: ${VPS_IPV4}

Then verify:
  dig @8.8.8.8 +short A ${SITE_DOMAIN}
EOF
}

main() {
  log "DNS delegation check for ${SITE_DOMAIN}"
  show_public_delegation
  show_hestia_nameservers
  ensure_hestia_zone_records
  print_registrar_instructions
}

main "$@"

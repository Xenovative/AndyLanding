#!/usr/bin/env bash
set -euo pipefail

# Docker deploy for Andy namecard on a VPS that already runs host Nginx (Hestia).
# Container listens on localhost:8007; host Nginx proxies card3.cyber-beast.tech -> :8007

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SITE_DOMAIN="card3.cyber-beast.tech"
CONTAINER_PORT="8007"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@cyber-beast.tech}"
NGINX_AVAILABLE="/etc/nginx/sites-available/${SITE_DOMAIN}.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/${SITE_DOMAIN}.conf"
CERTBOT_WEBROOT="/var/www/certbot"

log() { printf '[deploy-docker] %s\n' "$1"; }
die() { printf '[deploy-docker] ERROR: %s\n' "$1" >&2; exit 1; }

ensure_command_exists() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

write_nginx_http_proxy() {
  cat <<EOF
server {
    listen 80;
    server_name ${SITE_DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${CERTBOT_WEBROOT};
    }

    location / {
        proxy_pass http://127.0.0.1:${CONTAINER_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
}

write_nginx_https_proxy() {
  cat <<EOF
server {
    listen 80;
    server_name ${SITE_DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${CERTBOT_WEBROOT};
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${SITE_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${SITE_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SITE_DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:${CONTAINER_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
}

reload_or_start_nginx() {
  nginx -t
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx
  else
    systemctl start nginx
    systemctl enable nginx
  fi
}

configure_host_nginx() {
  local temp_config
  temp_config="$(mktemp)"

  mkdir -p "$(dirname "$NGINX_AVAILABLE")" "$(dirname "$NGINX_ENABLED")" "$CERTBOT_WEBROOT"

  if [[ -f "/etc/letsencrypt/live/${SITE_DOMAIN}/fullchain.pem" ]]; then
    write_nginx_https_proxy > "$temp_config"
  else
    write_nginx_http_proxy > "$temp_config"
  fi

  install -m 0644 "$temp_config" "$NGINX_AVAILABLE"
  ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"
  rm -f "$temp_config"
  reload_or_start_nginx
}

issue_ssl_if_needed() {
  if [[ -f "/etc/letsencrypt/live/${SITE_DOMAIN}/fullchain.pem" ]]; then
    log "SSL certificate already present"
    return 0
  fi

  ensure_command_exists certbot
  log "Requesting SSL certificate for ${SITE_DOMAIN}"
  certbot certonly --webroot -w "$CERTBOT_WEBROOT" \
    --email "$CERTBOT_EMAIL" --agree-tos --no-eff-email \
    -d "$SITE_DOMAIN"

  local temp_config
  temp_config="$(mktemp)"
  write_nginx_https_proxy > "$temp_config"
  install -m 0644 "$temp_config" "$NGINX_AVAILABLE"
  rm -f "$temp_config"
  reload_or_start_nginx
}

start_container() {
  log "Building and starting Docker container on 127.0.0.1:${CONTAINER_PORT}"
  docker compose down 2>/dev/null || true
  docker compose up -d --build

  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${CONTAINER_PORT}/" || true)"
  [[ "$code" == "200" ]] || die "Container not responding on 127.0.0.1:${CONTAINER_PORT} (got HTTP ${code:-none})"
  log "Container OK (HTTP ${code})"
}

verify_dns_hint() {
  local resolved
  resolved="$(dig @8.8.8.8 +short "$SITE_DOMAIN" A 2>/dev/null | head -n 1 || true)"
  if [[ -z "$resolved" ]]; then
    log "WARNING: Public DNS for ${SITE_DOMAIN} is empty. Run ./step1-setup-nameservers.sh"
  else
    log "Public DNS: ${SITE_DOMAIN} -> ${resolved}"
  fi
}

main() {
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

  ensure_command_exists docker
  ensure_command_exists curl
  ensure_command_exists dig

  log "Deploying ${SITE_DOMAIN} with Docker + host Nginx reverse proxy"

  start_container
  configure_host_nginx
  issue_ssl_if_needed
  verify_dns_hint

  log "Docker deploy complete."
  log "Local test:  curl -sI http://127.0.0.1:${CONTAINER_PORT}/ | head"
  log "Public URL:   https://${SITE_DOMAIN}"
  log "NOTE: Port ${CONTAINER_PORT} is localhost-only. Use domain on port 80/443, not :${CONTAINER_PORT}."
}

main "$@"

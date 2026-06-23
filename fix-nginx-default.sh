#!/usr/bin/env bash
set -euo pipefail

# Stops Zulkifli (or any site) from being the nginx SSL default for unknown hostnames.
# Installs a neutral catch-all that closes unmatched HTTPS connections.

CATCHALL_AVAILABLE="/etc/nginx/sites-available/00-default-catchall.conf"
CATCHALL_ENABLED="/etc/nginx/sites-enabled/00-default-catchall.conf"

log() { printf '[fix-nginx-default] %s\n' "$1"; }

ensure_command_exists() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "Required command '%s' not found.\n" "$1" >&2
    exit 1
  }
}

strip_default_server_flags() {
  local config_path search_paths

  search_paths=(
    /etc/nginx/sites-enabled
    /etc/nginx/sites-available
    /etc/nginx/conf.d
  )

  for config_path in "${search_paths[@]}"; do
    [[ -d "$config_path" ]] || continue
    while IFS= read -r -d '' file; do
      if grep -q 'default_server' "$file" 2>/dev/null; then
        log "Removing default_server from ${file}"
        sudo sed -i \
          -e 's/listen \(.*\) default_server;/listen \1;/g' \
          -e 's/listen \(.*\) ssl \(.*\) default_server;/listen \1 ssl \2;/g' \
          -e 's/listen \(.*\) ssl http2 default_server;/listen \1 ssl http2;/g' \
          "$file"
      fi
    done < <(find "$config_path" -type f -print0 2>/dev/null)
  done
}

install_catchall() {
  local temp_config cert_name
  temp_config="$(mktemp)"

  cert_name="$(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -v '^README$' | head -n 1 || true)"
  if [[ -z "$cert_name" ]]; then
    cert_name="card3.cyber-beast.tech"
  fi

  cat > "$temp_config" <<EOF
# Neutral default — unmatched hostnames get no content (prevents wrong namecard fallback)
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/${cert_name}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${cert_name}/privkey.pem;

    return 444;
}
EOF

  sudo mkdir -p "$(dirname "$CATCHALL_AVAILABLE")" "$(dirname "$CATCHALL_ENABLED")"
  sudo install -m 0644 "$temp_config" "$CATCHALL_AVAILABLE"
  sudo ln -sf "$CATCHALL_AVAILABLE" "$CATCHALL_ENABLED"
  rm -f "$temp_config"
  log "Installed catch-all default vhost at ${CATCHALL_AVAILABLE}"
}

main() {
  ensure_command_exists nginx
  ensure_command_exists sudo

  log "Fixing nginx default-server fallback"
  strip_default_server_flags
  install_catchall
  sudo nginx -t
  if systemctl is-active --quiet nginx; then
    sudo systemctl reload nginx
  else
    sudo systemctl start nginx
  fi
  log "Done. Unknown hostnames will no longer serve a random namecard."
}

main "$@"

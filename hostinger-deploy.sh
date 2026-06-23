#!/usr/bin/env bash
set -euo pipefail

# Paste this entire script into Hostinger VPS Browser Terminal (hPanel -> VPS -> Terminal).
# It downloads the latest bootstrap from Xenovative/AndyLanding and deploys all 3 namecards.

CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@cyber-beast.tech}"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  read -rsp "GitHub token (repo read access to Xenovative): " GITHUB_TOKEN
  echo
  export GITHUB_TOKEN
fi

tmp_bootstrap="$(mktemp)"
trap 'rm -f "$tmp_bootstrap"' EXIT

curl -fsSL \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/Xenovative/AndyLanding/contents/bootstrap-all-namecards.sh" \
  -o "$tmp_bootstrap"

chmod +x "$tmp_bootstrap"
CERTBOT_EMAIL="$CERTBOT_EMAIL" GITHUB_TOKEN="$GITHUB_TOKEN" "$tmp_bootstrap"

#!/usr/bin/env bash
# Deploy all 7 Regalia Club namecards to Hostinger Premium Web Hosting.
# Run from hPanel -> Advanced -> SSH Access (Browser SSH), then paste this whole script.
#
# Optional for private repos (yan-yuxuan-ecard, simone-tesse-ecard):
#   export GITHUB_TOKEN="ghp_your_token_here"
#
# Usage:
#   bash deploy-regaliaclub-vip.sh

set -euo pipefail

DOMAIN="regaliaclub.vip"
ORG="Xenovative"
WORKDIR="${HOME}/.regaliaclub-deploy"
CLONE_ROOT="${WORKDIR}/repos"

log() { printf '[regaliaclub] %s\n' "$1"; }
die() { printf '[regaliaclub] ERROR: %s\n' "$1" >&2; exit 1; }

find_public_html() {
  local candidates=(
    "${HOME}/domains/${DOMAIN}/public_html"
    "${HOME}/public_html/domains/${DOMAIN}/public_html"
    "${HOME}/public_html"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  die "Could not find public_html for ${DOMAIN}. Set WEB_ROOT manually: WEB_ROOT=/path bash $0"
}

WEB_ROOT="${WEB_ROOT:-$(find_public_html)}"
log "Web root: ${WEB_ROOT}"

ensure_command_exists() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command '$1'. Enable SSH/git on your Hostinger plan."
}

ensure_command_exists git
ensure_command_exists rsync

mkdir -p "$CLONE_ROOT"

clone_repo() {
  local repo="$1"
  local branch="$2"
  local dest="${CLONE_ROOT}/${repo}"

  if [[ -d "${dest}/.git" ]]; then
    log "Updating ${repo}..."
    git -C "$dest" fetch origin
    git -C "$dest" reset --hard "origin/${branch}" 2>/dev/null || git -C "$dest" reset --hard "origin/master"
    git -C "$dest" clean -fd
    return 0
  fi

  log "Cloning ${ORG}/${repo} (${branch})..."
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    git clone --depth 1 -b "$branch" \
      "https://x-access-token:${GITHUB_TOKEN}@github.com/${ORG}/${repo}.git" \
      "$dest"
  else
    git clone --depth 1 -b "$branch" \
      "https://github.com/${ORG}/${repo}.git" \
      "$dest" \
      || die "Clone failed for ${repo}. If it is private, export GITHUB_TOKEN first."
  fi
}

sync_stefano() {
  local src="${CLONE_ROOT}/StephenNameCard/Stephen"
  local dest="${WEB_ROOT}/stefano-qiu"
  mkdir -p "$dest"
  rsync -av --delete \
    --include='/index.html' \
    --include='/styles.css' \
    --include='/script.js' \
    --include='/stefano-qiu.vcf' \
    --include='/stefano-profile.png' \
    --include='/composite.png' \
    --include='/highlight-*.png' \
    --include='/layer_*.png' \
    --include='/gt-logo*.png' \
    --include='/goldenthrone-*.jpeg' \
    --include='/img/' \
    --include='/img/***' \
    --exclude='*' \
    "${src}/" "${dest}/"
}

sync_generic() {
  local src="$1"
  local dest="$2"
  shift 2
  local extra_excludes=("$@")

  mkdir -p "$dest"
  local args=(
    -av --delete
    --exclude '.git'
    --exclude '.github'
    --exclude '.gitignore'
    --exclude '.dockerignore'
    --exclude 'Dockerfile'
    --exclude 'docker-compose.yml'
    --exclude 'nginx.conf'
    --exclude 'README.md'
    --exclude '*.sh'
    --exclude '*.ps1'
    --exclude 'deploy*'
    --exclude 'fix-*'
    --exclude 'bootstrap*'
    --exclude 'hostinger*'
    --exclude 'step*'
    --exclude '*.psd'
    --exclude '*.pdf'
  )
  local item
  for item in "${extra_excludes[@]}"; do
    args+=(--exclude "$item")
  done
  rsync "${args[@]}" "${src}/" "${dest}/"
}

write_landing_page() {
  cat > "${WEB_ROOT}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="description" content="Regalia Club digital name cards" />
  <title>Regalia Club — Digital Name Cards</title>
  <style>
    :root { --bg:#0f1419; --card:#1a222d; --text:#f5f1e8; --muted:#b8b0a2; --gold:#c9a962; --border:rgba(201,169,98,.25); }
    * { box-sizing:border-box; }
    body { margin:0; min-height:100vh; font-family:Georgia,"Times New Roman",serif; background:radial-gradient(circle at top,#1b2430 0%,var(--bg) 55%); color:var(--text); }
    .wrap { max-width:720px; margin:0 auto; padding:48px 20px 64px; }
    header { text-align:center; margin-bottom:40px; }
    .eyebrow { letter-spacing:.28em; text-transform:uppercase; font-size:.72rem; color:var(--gold); margin-bottom:12px; }
    h1 { margin:0 0 10px; font-size:clamp(2rem,5vw,2.8rem); font-weight:500; }
    .subtitle { margin:0; color:var(--muted); }
    .cards { display:grid; gap:14px; }
    a.card { display:flex; align-items:center; justify-content:space-between; gap:16px; padding:18px 20px; background:var(--card); border:1px solid var(--border); border-radius:14px; color:inherit; text-decoration:none; }
    a.card:hover { border-color:var(--gold); background:#202a36; }
    .name { font-size:1.08rem; margin:0 0 4px; }
    .role { margin:0; color:var(--muted); font-size:.92rem; }
    .arrow { color:var(--gold); }
    footer { margin-top:36px; text-align:center; color:var(--muted); font-size:.85rem; }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="eyebrow">Regalia Club</div>
      <h1>Digital Name Cards</h1>
      <p class="subtitle">Select a member card below</p>
    </header>
    <div class="cards">
      <a class="card" href="stefano-qiu/"><div><p class="name">Stefano Qiu</p><p class="role">Golden Throne</p></div><span class="arrow">→</span></a>
      <a class="card" href="andy/"><div><p class="name">Andy</p><p class="role">Golden Throne</p></div><span class="arrow">→</span></a>
      <a class="card" href="dr-zulkifli/"><div><p class="name">Dr. Zulkifli Hasan</p><p class="role">Senator</p></div><span class="arrow">→</span></a>
      <a class="card" href="yan-yuxuan/"><div><p class="name">顏郁璇</p><p class="role">顏金佩精品直播</p></div><span class="arrow">→</span></a>
      <a class="card" href="simone-tesse/"><div><p class="name">Simone Tesse</p><p class="role">Business Development Consultant</p></div><span class="arrow">→</span></a>
      <a class="card" href="abdul-aziz/"><div><p class="name">Dato’ Haji Mohd Abdul Aziz Bin Mohamed</p><p class="role">Digital Name Card</p></div><span class="arrow">→</span></a>
      <a class="card" href="bryan-lee/"><div><p class="name">Bryan Lee</p><p class="role">Board Member | CAF Capital</p></div><span class="arrow">→</span></a>
    </div>
    <footer>regaliaclub.vip</footer>
  </div>
</body>
</html>
EOF
}

main() {
  log "Starting deploy to ${WEB_ROOT}"

  clone_repo "StephenNameCard" "main"
  clone_repo "AndyLanding" "master"
  clone_repo "dr-zulkifli-namecard" "master"
  clone_repo "yan-yuxuan-ecard" "master"
  clone_repo "simone-tesse-ecard" "master"
  clone_repo "haji-m-abdul-aziz-namecard" "main"
  clone_repo "bryan-lee-namecard" "main"

  sync_stefano
  sync_generic "${CLONE_ROOT}/AndyLanding" "${WEB_ROOT}/andy"
  sync_generic "${CLONE_ROOT}/dr-zulkifli-namecard" "${WEB_ROOT}/dr-zulkifli"
  sync_generic "${CLONE_ROOT}/yan-yuxuan-ecard" "${WEB_ROOT}/yan-yuxuan"
  sync_generic "${CLONE_ROOT}/simone-tesse-ecard" "${WEB_ROOT}/simone-tesse"
  sync_generic "${CLONE_ROOT}/haji-m-abdul-aziz-namecard" "${WEB_ROOT}/abdul-aziz"
  sync_generic "${CLONE_ROOT}/bryan-lee-namecard" "${WEB_ROOT}/bryan-lee"

  write_landing_page

  log "Done. Test these URLs:"
  log "  https://${DOMAIN}/"
  log "  https://${DOMAIN}/stefano-qiu/"
  log "  https://${DOMAIN}/andy/"
  log "  https://${DOMAIN}/dr-zulkifli/"
  log "  https://${DOMAIN}/yan-yuxuan/"
  log "  https://${DOMAIN}/simone-tesse/"
  log "  https://${DOMAIN}/abdul-aziz/"
  log "  https://${DOMAIN}/bryan-lee/"
  log "Enable SSL in hPanel -> Security -> SSL if not already active."
}

main "$@"

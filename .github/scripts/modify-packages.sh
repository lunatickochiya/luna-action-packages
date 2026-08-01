#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

readonly GRAPHQL_QUERY='query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    defaultBranchRef {
      target { ... on Commit { oid } }
    }
    latestRelease {
      tagName
      tagCommit { oid }
    }
    refs(
      refPrefix: "refs/tags/"
      last: 1
      orderBy: { field: TAG_COMMIT_DATE, direction: ASC }
    ) {
      nodes {
        name
        target { oid }
      }
    }
  }
}'

readonly SOURCE_UPDATE_EXCLUDES=(
  3proxy
  accel-ppp
  aic8800
  amule
  aria2
  brook
  chinadns-ng
  cloudflared
  containerd
  coremark
  curl
  daed
  ddns-go
  filebrowser
  frp
  fullconenat
  homebox
  joker
  libcron
  libcryptopp
  libtorrent-rasterbar
  libwxwidgets
  mbedtls
  miniupnpd-nft
  mmdvm-host
  msd_lite
  mt76
  n2n_v2
  naiveproxy
  natter
  netmaker
  netdata
  nexttrace
  nikki
  openlist
  oscam
  pppwn-cpp
  qBittorrent-Enhanced-Edition
  quickjspp
  r8152
  r8168
  rtl8188eu
  rtl8189es
  rtl8192eu
  rtl8812au-ac
  rtl8821cu
  rtl88x2bu
  shadowsocks-libev
  shadowsocksr-libev
  softethervpn5
  sub-web
  subconverter
  tailscale
  tuic-server
  ua2f
  udp2raw
  upx
  v2raya
  wxbase
  xtables-wgobfs
  ysf-clients
)

declare -A REPOSITORY_METADATA_CACHE=()
REPOSITORY_METADATA_RESULT=''

log() {
  printf '[modify-packages] %s\n' "$*"
}

warn() {
  printf '[modify-packages] WARNING: %s\n' "$*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    return 1
  }
}

is_source_update_excluded() {
  local package="$1"
  local excluded

  [[ "$package" == luci-* ]] && return 0
  for excluded in "${SOURCE_UPDATE_EXCLUDES[@]}"; do
    [[ "$package" == "$excluded" ]] && return 0
  done
  return 1
}

extract_github_repository() {
  local makefile="$1"
  local repository

  repository="$(
    grep -m1 'PKG_SOURCE_URL.*github' "$makefile" |
      sed -nE 's|.*github\.com[/:]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(\.git)?.*|\1/\2|p'
  )"
  repository="${repository%.git}"

  [[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s\n' "$repository"
}

get_repository_metadata() {
  local repository="$1"
  local owner="${repository%%/*}"
  local name="${repository#*/}"
  local metadata

  if [[ ${REPOSITORY_METADATA_CACHE[$repository]+cached} ]]; then
    REPOSITORY_METADATA_RESULT="${REPOSITORY_METADATA_CACHE[$repository]}"
    return 0
  fi

  if ! metadata="$(
    gh api graphql \
      --raw-field owner="$owner" \
      --raw-field name="$name" \
      --raw-field query="$GRAPHQL_QUERY"
  )"; then
    warn "Unable to query ${repository}; keeping its existing version."
    return 1
  fi

  REPOSITORY_METADATA_CACHE["$repository"]="$metadata"
  REPOSITORY_METADATA_RESULT="$metadata"
}

version_lt() {
  local current="$1"
  local candidate="$2"
  local newest

  newest="$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n 1)"
  [[ "$current" != "$newest" ]]
}

replace_legacy_ifname() {
  log 'Replacing legacy network *.ifname references'

  local file
  while IFS= read -r -d '' file; do
    sed -i -E 's/(network\..*)\.ifname/\1.device/g' "$file"
  done < <(
    find . \
      \( -path '*/root/*' -o -path '*/files/*' -o -path '*/luasrc/*' \) \
      ! -path './base-files/*' \
      ! -path './dnsmasq/*' \
      ! -path './luci-base/*' \
      ! -path './ppp/*' \
      -type f -print0
  )
}

update_package_sources() {
  log 'Updating GitHub-backed package versions'

  local makefile package repository metadata
  local default_oid current_version latest_version release_oid

  for makefile in */Makefile; do
    package="${makefile%%/*}"
    is_source_update_excluded "$package" && continue

    repository="$(extract_github_repository "$makefile")" || continue
    get_repository_metadata "$repository" || continue
    metadata="$REPOSITORY_METADATA_RESULT"

    default_oid="$(jq -r '.data.repository.defaultBranchRef.target.oid // empty' <<<"$metadata")"
    if [[ -n "$default_oid" ]] && grep -q '^PKG_SOURCE_VERSION:=' "$makefile"; then
      sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$default_oid/" "$makefile"
    fi

    current_version="$(
      sed -nE 's/^PKG_VERSION:=(.*)$/\1/p' "$makefile" |
        head -n 1 |
        sed -E 's/^(v|release-)//'
    )"
    [[ "$current_version" =~ [0-9] ]] || continue

    latest_version="$(
      jq -r '.data.repository.latestRelease.tagName // empty' <<<"$metadata" |
        sed -E 's/^(v|release-)//'
    )"
    [[ "$latest_version" =~ [0-9] ]] || continue
    [[ "$latest_version" != *'('* ]] || continue

    log "${repository}: ${current_version} -> ${latest_version}"
    version_lt "$current_version" "$latest_version" || continue

    release_oid="$(
      jq -r '
        .data.repository.latestRelease.tagCommit.oid //
        .data.repository.refs.nodes[-1].target.oid //
        empty
      ' <<<"$metadata"
    )"
    [[ -n "$release_oid" ]] || continue

    sed -i \
      -e "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$release_oid/" \
      -e "s/^PKG_VERSION:=.*/PKG_VERSION:=$latest_version/" \
      "$makefile"
  done
}

normalize_luci_packages() {
  log 'Normalizing LuCI package metadata'

  local package makefile
  local controllers

  for package in luci-*/; do
    makefile="${package}Makefile"
    [[ -f "$makefile" ]] || continue

    if grep -q 'luci\.mk' "$makefile"; then
      sed -i -E '/^(PKG_VERSION|PKG_RELEASE):=/d' "$makefile"
    fi

    controllers=("${package}luasrc/controller/"*.lua)
    ((${#controllers[@]} > 0)) || continue
    grep -q '"nas",' "${controllers[@]}" || continue
    grep -q '_("NAS")' "${controllers[@]}" && continue
    sed -i 's/ index()/ index()\n\tentry({"admin", "nas"}, firstchild(), _("NAS") , 45).dependent = false/' "${controllers[@]}"
  done
}

run_diy_helpers() {
  log 'Generating LuCI compatibility files'

  local helper
  for helper in \
    .github/diy/create_acl_for_luci.sh \
    .github/diy/convert_translation.sh \
    .github/diy/generate_ucitrack.sh; do
    if ! bash "$helper" -a >/dev/null 2>&1; then
      warn "Helper did not complete cleanly: ${helper}"
    fi
  done
}

sed_if_exists() {
  local file="$1"
  shift

  if [[ -f "$file" ]]; then
    sed -i "$@" "$file"
  else
    warn "Skipping missing file: ${file}"
  fi
}

append_if_exists() {
  local file="$1"
  local line="$2"

  if [[ -f "$file" ]]; then
    printf '%s\n' "$line" >>"$file"
  else
    warn "Skipping missing file: ${file}"
  fi
}

apply_package_overrides() {
  log 'Applying package-specific compatibility changes'

  rm -rf luci-app-partexp/po/zh_Hans

  sed_if_exists luci-app-dnscrypt-proxy2/Makefile '/minisign:minisign/d'
  sed_if_exists ngrokc/Makefile 's/+libstdcpp/+libstdcpp +zlib/'
  sed_if_exists luci-app-rclone/Makefile 's/+rclone\( \|$\)/+rclone +fuse-utils\1/g'
  sed_if_exists luci-app-openclash/Makefile 's/+libcap /+libcap +libcap-bin /'
  sed_if_exists luci-app-argon-config/Makefile 's/\(+luci-compat\)/\1 +luci-theme-argon/'
  sed_if_exists luci-app-vsftpd/Makefile 's/+vsftpd$/+vsftpd-alt/'
  sed_if_exists luci-app-packet-capture/Makefile 's/ +uhttpd-mod-ubus//'
  sed_if_exists ddns-scripts/files/etc/init.d/ddns '/boot()/,+2d'
  sed_if_exists base-files/files/etc/openwrt_release "/DISTRIB_DESCRIPTION/c\\DISTRIB_DESCRIPTION=\"%D %C by Kiddin'\""
  sed_if_exists mwan3/Makefile 's/PKG_VERSION:=2/PKG_VERSION:=3/'
  sed_if_exists ariang/Makefile '/+uhttpd/d'

  sed_if_exists base-files/files/lib/upgrade/keep.d/base-files-essential \
    -e '$a /etc/bench.log' \
    -e '/\/etc\/profile/d' \
    -e '/\/etc\/shinit/d'
  sed_if_exists base-files/Makefile \
    -e '/^\/etc\/profile/d' \
    -e '/^\/etc\/shinit/d'

  append_if_exists uwsgi/files-luci-support/luci-webui.ini 'cgi-timeout = 300'
  append_if_exists uwsgi/files-luci-support/luci-cgi_io.ini 'cgi-timeout = 90'
  sed_if_exists uwsgi/files-luci-support/luci-webui.ini '/limit-as/c\limit-as = 5000'
  sed_if_exists uwsgi/files/uwsgi.init 's/procd_set_param stderr 1/procd_set_param stderr 0/'
  sed_if_exists luci-app-wifidog/luasrc/model/cbi/wifidog/wifidog_cfg.lua 's/\tip.neighbors/\tluci.ip.neighbors/'
  sed_if_exists luci-app-ssr-plus/Makefile 's/ if aarch64||arm||i386||x86_64//'
  sed_if_exists luci-app-transmission/Makefile 's/transmission-daemon$/transmission-daemon +transmission-web-control/'

  mkdir -p \
    luci-app-passwall/root/www/luci-static/passwall \
    luci-app-passwall2/root/www/luci-static/passwall2 \
    luci-app-ssr-plus/root/www/luci-static/shadowsocksr
  cp -rf luci-app-bypass/root/www/luci-static/bypass/. luci-app-passwall/root/www/luci-static/passwall/
  cp -rf luci-app-bypass/root/www/luci-static/bypass/. luci-app-passwall2/root/www/luci-static/passwall2/
  cp -rf luci-app-bypass/root/www/luci-static/bypass/. luci-app-ssr-plus/root/www/luci-static/shadowsocksr/

  if [[ -f luci-app-quickstart/htdocs/luci-static/quickstart/style.css ]]; then
    printf '%s\n' \
      '#page>div[data-v-d324f700]:first-child{display:none}' \
      'button.btn_styles.color1[data-v-0d223b54]:last-child{display:none}' \
      >>luci-app-quickstart/htdocs/luci-static/quickstart/style.css
  else
    warn 'Skipping missing quickstart stylesheet.'
  fi

  local makefile
  for makefile in */Makefile; do
    sed -i \
      -e 's?include \.\./\.\./\(lang\|devel\)?include $(TOPDIR)/feeds/packages/\1?' \
      -e 's/\(\(^\|[[:space:]]\)\(PKG_HASH\|PKG_MD5SUM\|PKG_MIRROR_HASH\|HASH\):=\).*/\1skip/' \
      -e 's?\.\./\.\./luci.mk?$(TOPDIR)/feeds/luci/luci.mk?' \
      -e 's/+ca-certificates/+ca-bundle/' \
      -e 's/php7/php8/g' \
      -e 's/+docker /+docker +dockerd /g' \
      "$makefile"
  done
}

set_package_releases() {
  log 'Refreshing package release numbers'

  local makefile package release
  for makefile in */Makefile; do
    package="${makefile%%/*}"

    if grep -q '^PKG_VERSION:=' "$makefile" && ! grep -q '^PKG_RELEASE:=' "$makefile"; then
      sed -i '/^PKG_VERSION:=/a PKG_RELEASE:=' "$makefile"
    fi

    grep -q '^PKG_RELEASE:=' "$makefile" || continue
    release="$(git rev-list --count HEAD -- "$package")"
    sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=$release/" "$makefile"
  done
}

wait_for_tasks() {
  local failed=0
  local task pid

  for task in "$@"; do
    pid="${task#*:}"
    if ! wait "$pid"; then
      warn "Task failed: ${task%%:*}"
      failed=1
    fi
  done
  ((failed == 0))
}

main() {
  local repository_root
  repository_root="$(git rev-parse --show-toplevel)"
  cd "$repository_root"

  export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  : "${GH_TOKEN:?GH_TOKEN must contain the GitHub Actions token}"
  require_command gh
  require_command git
  require_command jq

  replace_legacy_ifname

  update_package_sources &
  local source_pid=$!
  normalize_luci_packages &
  local luci_pid=$!
  wait_for_tasks \
    "update-package-sources:${source_pid}" \
    "normalize-luci-packages:${luci_pid}"

  run_diy_helpers
  apply_package_overrides
  set_package_releases
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

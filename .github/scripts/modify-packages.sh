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

CURRENT_STAGE='startup'
CURRENT_ITEM=''
declare -A ORIGINAL_PKG_VERSIONS=()
declare -A REPOSITORY_METADATA_CACHE=()
REPOSITORY_METADATA_RESULT=''

log() {
  printf '[modify-packages] %s\n' "$*"
}

warn() {
  printf '[modify-packages] WARNING: %s\n' "$*" >&2
  printf '::warning title=Modify warning::%s\n' "$*" >&2
}

handle_error() {
  local status="$1"
  local line="$2"
  local command="$3"

  trap - ERR
  printf '::error title=Modify failed::stage=%s; item=%s; line=%s; exit=%s; command=%q\n' \
    "$CURRENT_STAGE" "${CURRENT_ITEM:-n/a}" "$line" "$status" "$command" >&2
  exit "$status"
}

run_stage() {
  local stage="$1"
  shift

  CURRENT_STAGE="$stage"
  CURRENT_ITEM=''
  printf '::group::Modify - %s\n' "$stage"
  log "START: ${stage}"
  "$@"
  log "DONE: ${stage}"
  printf '::endgroup::\n'
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

latest() {
  local repository="$1"
  local owner="${repository%%/*}"
  local name="${repository#*/}"

  gh api graphql \
    --raw-field owner="$owner" \
    --raw-field name="$name" \
    --raw-field query="$GRAPHQL_QUERY"
}

get_repository_metadata() {
  local repository="$1"
  local metadata

  if [[ ${REPOSITORY_METADATA_CACHE[$repository]+cached} ]]; then
    REPOSITORY_METADATA_RESULT="${REPOSITORY_METADATA_CACHE[$repository]}"
    return 0
  fi

  if ! metadata="$(latest "$repository")"; then
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

normalize_release_tag() {
  local version="$1"

  version="${version##*/}"
  version="${version#release-}"
  version="${version#v}"
  version="${version#V}"
  printf '%s\n' "$version"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

read_package_version() {
  sed -nE \
    's/^[[:space:]]*PKG_VERSION[[:space:]]*[:?+]?=[[:space:]]*(.*)$/\1/p' \
    "$1"
}

snapshot_package_versions() {
  log 'Recording PKG_VERSION values immediately before latest updates'

  local makefile
  for makefile in */Makefile; do
    CURRENT_ITEM="$makefile"
    ORIGINAL_PKG_VERSIONS["$makefile"]="$(read_package_version "$makefile")"
  done
  CURRENT_ITEM=''
}

skip_hashes_for_latest_version_changes() {
  log 'Checking which PKG_VERSION values were changed by latest updates'

  local makefile original_version current_version hash_field_count
  local version_changes=0
  local hash_changes=0

  for makefile in */Makefile; do
    [[ ${ORIGINAL_PKG_VERSIONS[$makefile]+recorded} ]] || continue
    CURRENT_ITEM="$makefile"
    original_version="${ORIGINAL_PKG_VERSIONS[$makefile]}"
    current_version="$(read_package_version "$makefile")"
    [[ "$current_version" != "$original_version" ]] || continue

    ((version_changes += 1))
    log "latest changed PKG_VERSION in ${makefile}: ${original_version:-<empty>} -> ${current_version:-<empty>}"

    hash_field_count="$(
      grep -Ec '^[[:space:]]*PKG_(HASH|MIRROR_HASH|MD5SUM)[[:space:]]*[:?+]?=' "$makefile" || true
    )"
    if ((hash_field_count > 0)); then
      sed -i -E \
        's/^([[:space:]]*PKG_(HASH|MIRROR_HASH|MD5SUM)[[:space:]]*[:?+]?=[[:space:]]*)[^#]*([[:space:]]*#.*)?$/\1skip\3/' \
        "$makefile"
      ((hash_changes += hash_field_count))
      log "Set ${hash_field_count} existing PKG_HASH/PKG_MIRROR_HASH/PKG_MD5SUM field(s) to skip in ${makefile}"
    else
      log "No PKG_HASH/PKG_MIRROR_HASH/PKG_MD5SUM exists in ${makefile}; leaving hash fields unchanged"
    fi
  done

  CURRENT_ITEM=''
  log "latest changed ${version_changes} PKG_VERSION file(s); updated ${hash_changes} hash field(s)"
}

update_package_sources() {
  log 'Updating GitHub-backed package versions with latest release metadata'

  local makefile package repository metadata
  local default_oid current_version latest_version release_oid escaped_version

  for makefile in */Makefile; do
    package="${makefile%%/*}"
    is_source_update_excluded "$package" && continue

    repository="$(extract_github_repository "$makefile")" || continue
    CURRENT_ITEM="${package} (${repository})"
    get_repository_metadata "$repository" || continue
    metadata="$REPOSITORY_METADATA_RESULT"

    default_oid="$(jq -r '.data.repository.defaultBranchRef.target.oid // empty' <<<"$metadata")"
    if [[ -n "$default_oid" ]] && grep -q '^PKG_SOURCE_VERSION:=' "$makefile"; then
      sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$default_oid/" "$makefile"
    fi

    current_version="$(normalize_release_tag "$(read_package_version "$makefile")")"
    [[ "$current_version" =~ [0-9] ]] || continue

    latest_version="$(normalize_release_tag "$(
      jq -r '.data.repository.latestRelease.tagName // empty' <<<"$metadata"
    )")"
    [[ "$latest_version" =~ [0-9] ]] || continue
    [[ "$latest_version" != *'('* ]] || continue

    version_lt "$current_version" "$latest_version" || continue
    log "Updating ${package} from ${repository}: ${current_version} -> ${latest_version}"

    release_oid="$(
      jq -r '
        .data.repository.latestRelease.tagCommit.oid //
        .data.repository.refs.nodes[-1].target.oid //
        empty
      ' <<<"$metadata"
    )"
    [[ -n "$release_oid" ]] || continue

    escaped_version="$(escape_sed_replacement "$latest_version")"
    if ! sed -i \
      -e "s|^PKG_SOURCE_VERSION:=.*|PKG_SOURCE_VERSION:=$release_oid|" \
      -e "s|^PKG_VERSION:=.*|PKG_VERSION:=$escaped_version|" \
      "$makefile"; then
      printf '::error file=%s,title=Package version update failed::repository=%s; version=%s\n' \
        "$makefile" "$repository" "$latest_version" >&2
      return 1
    fi
  done
  CURRENT_ITEM=''
}

replace_legacy_ifname() {
  log 'Replacing legacy network *.ifname references'

  local file
  while IFS= read -r -d '' file; do
    CURRENT_ITEM="$file"
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

normalize_luci_controllers() {
  log 'Adding missing LuCI NAS menu entries'

  local package
  local controllers

  for package in luci-*/; do
    CURRENT_ITEM="$package"

    controllers=("${package}luasrc/controller/"*.lua)
    ((${#controllers[@]} > 0)) || continue
    grep -q '"nas",' "${controllers[@]}" || continue
    grep -q '_("NAS")' "${controllers[@]}" && continue
    sed -i 's/ index()/ index()\n\tentry({"admin", "nas"}, firstchild(), _("NAS") , 45).dependent = false/' "${controllers[@]}"
  done
  CURRENT_ITEM=''
}

run_diy_helpers() {
  log 'Generating LuCI compatibility files'

  local helper
  for helper in \
    .github/diy/create_acl_for_luci.sh \
    .github/diy/convert_translation.sh \
    .github/diy/generate_ucitrack.sh; do
    CURRENT_ITEM="$helper"
    if ! bash "$helper" -a >/dev/null 2>&1; then
      warn "Helper did not complete cleanly: ${helper}"
    fi
  done
  CURRENT_ITEM=''
}

sed_if_exists() {
  local file="$1"
  shift

  if [[ -f "$file" ]]; then
    CURRENT_ITEM="$file"
    if ! sed -i "$@" "$file"; then
      printf '::error file=%s,title=File modification failed::sed arguments: %s\n' \
        "$file" "$*" >&2
      return 1
    fi
  else
    warn "Skipping missing file: ${file}"
  fi
}

append_if_exists() {
  local file="$1"
  local line="$2"

  if [[ -f "$file" ]]; then
    CURRENT_ITEM="$file"
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
    CURRENT_ITEM="$makefile"
    sed -i \
      -e 's?include \.\./\.\./\(lang\|devel\)?include $(TOPDIR)/feeds/packages/\1?' \
      -e 's?\.\./\.\./luci.mk?$(TOPDIR)/feeds/luci/luci.mk?' \
      -e 's/+ca-certificates/+ca-bundle/' \
      -e 's/php7/php8/g' \
      -e 's/+docker /+docker +dockerd /g' \
      "$makefile"
  done
  CURRENT_ITEM=''
}

main() {
  local repository_root
  repository_root="$(git rev-parse --show-toplevel)"
  cd "$repository_root"

  export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  : "${GH_TOKEN:?GH_TOKEN must contain the built-in GitHub Actions token}"
  require_command gh
  require_command git
  require_command jq

  trap 'handle_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

  run_stage 'replace legacy network options' replace_legacy_ifname
  run_stage 'record versions before latest' snapshot_package_versions
  run_stage 'update GitHub package versions' update_package_sources
  run_stage 'update hashes changed by latest' skip_hashes_for_latest_version_changes
  run_stage 'normalize LuCI controllers' normalize_luci_controllers
  run_stage 'run DIY generators' run_diy_helpers
  run_stage 'apply package overrides' apply_package_overrides
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

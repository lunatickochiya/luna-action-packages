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
  natflow
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

is_apk_version() {
  local version="$1"

  # OpenWrt 25.12 appends -r$(PKG_RELEASE) itself.  PKG_VERSION therefore
  # must use apk's version grammar and must not contain an opkg-style suffix.
  [[ "$version" =~ ^[0-9]+(\.[0-9]+)*[a-z]?(_(alpha|beta|pre|rc|cvs|svn|git|hg|p)[0-9]*)*(~[0-9a-f]+)?(-r[0-9]+)?$ ]]
}

trim_version() {
  local value="$1"

  value="${value//$'\r'/}"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s\n' "$value"
}

normalize_apk_version() {
  local version

  version="$(trim_version "$1")"
  version="${version##*/}"
  version="${version#release-}"
  version="${version#v}"
  version="${version#V}"

  # Keep the common upstream spellings while translating them to apk's
  # ordered suffixes.  Hashes are represented by apk's ~hash component.
  if [[ "$version" =~ ^([0-9]+)-([0-9]+)-([0-9]+)-([0-9a-f]+)$ ]]; then
    version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}~${BASH_REMATCH[4]}"
  elif [[ "$version" =~ ^([0-9]+)-([0-9]+)-([0-9]+)$ ]]; then
    version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  elif [[ "$version" =~ ^([0-9]+(\.[0-9]+)+)-([0-9]+)$ ]]; then
    version="${BASH_REMATCH[1]}.${BASH_REMATCH[3]}"
  elif [[ "$version" =~ ^([0-9]+(\.[0-9]+)+)-([0-9a-f]+)$ ]]; then
    version="${BASH_REMATCH[1]}~${BASH_REMATCH[3]}"
  elif [[ "$version" =~ ^([0-9]+(\.[0-9]+)+)_v([0-9].*)$ ]]; then
    version="${BASH_REMATCH[1]}.${BASH_REMATCH[3]}"
  elif [[ "$version" =~ ^(.+)-(alpha|beta|pre|rc|cvs|svn|git|hg|p)([0-9]*)$ ]]; then
    version="${BASH_REMATCH[1]}_${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
  elif [[ "$version" =~ ^(.+)-dev([0-9]*)$ ]]; then
    version="${BASH_REMATCH[1]}_pre${BASH_REMATCH[2]}"
  elif [[ "$version" =~ ^([0-9]+(\.[0-9]+)*)p([0-9]+)$ ]]; then
    version="${BASH_REMATCH[1]}_p${BASH_REMATCH[3]}"
  elif [[ "$version" =~ ^svn([0-9]+)$ ]]; then
    version="${BASH_REMATCH[1]}_svn"
  elif [[ "$version" =~ ^Release([0-9].*)$ ]]; then
    version="${BASH_REMATCH[1]}"
  elif [[ "$version" =~ ^kaiplus-runtime-v([0-9].*)$ ]]; then
    version="${BASH_REMATCH[1]}"
  elif [[ "$version" =~ ^MatriX\.([0-9]+)$ ]]; then
    version="${BASH_REMATCH[1]}"
  elif [[ "$version" =~ ^(.+)-par$ ]]; then
    version="${BASH_REMATCH[1]}_p"
  fi

  printf '%s\n' "$version"
}

read_package_release() {
  sed -nE \
    's/^[[:space:]]*PKG_RELEASE[[:space:]]*[:?+]?=[[:space:]]*(.*)$/\1/p' \
    "$1" | head -n 1
}

normalize_apk_release() {
  local release

  release="$(trim_version "$1")"
  [[ -n "$release" ]] || {
    printf '\n'
    return
  }

  # Build-time commit counts and autorelease helpers are numeric after make
  # expansion.  A source hash is not an apk revision, so use a stable numeric
  # revision for the legacy form that appears in this feed.
  if [[ "$release" == '$(PKG_SOURCE_VERSION)' || "$release" == '${PKG_SOURCE_VERSION}' ]]; then
    printf '1\n'
  elif [[ "$release" == *'$('* || "$release" == *'${'* ]]; then
    printf '%s\n' "$release"
  elif [[ "$release" =~ ^r([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$release" =~ ^[0-9]+([-._][0-9]+)+$ ]]; then
    printf '%s\n' "${release//[-._]/}"
  elif [[ "$release" =~ ^[[:alpha:]]+$ ]]; then
    printf '1\n'
  elif [[ "$release" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$release"
  else
    printf '1\n'
  fi
}

version_is_used_for_source() {
  local makefile="$1"

  grep -Fq '$(PKG_VERSION)' "$makefile" ||
    grep -Fq '${PKG_VERSION}' "$makefile"
}

preserve_upstream_version_references() {
  local makefile="$1"
  local source_version="$2"
  local escaped_source_version

  source_version="$(trim_version "$source_version")"
  if ! make_variable_exists "$makefile" PKG_SOURCE_TAG; then
    escaped_source_version="$(escape_sed_replacement "$source_version")"
    sed -i -E \
      "0,/^[[:space:]]*PKG_VERSION[[:space:]]*[:?+]?=.*[[:space:]]*$/ {/^[[:space:]]*PKG_VERSION[[:space:]]*[:?+]?=.*[[:space:]]*$/s|^|PKG_SOURCE_TAG:=${escaped_source_version}\\n|;}" \
      "$makefile"
  fi
  if [[ "$source_version" == v* ]]; then
    sed -i 's/v\$(PKG_VERSION)/$(PKG_SOURCE_TAG)/g' "$makefile"
  fi
  sed -i \
    -e 's/\$(PKG_VERSION)/$(PKG_SOURCE_TAG)/g' \
    -e 's/\${PKG_VERSION}/$(PKG_SOURCE_TAG)/g' \
    "$makefile"
}

replace_make_variable() {
  local file="$1"
  local variable="$2"
  local value="$3"
  local escaped_value

  escaped_value="$(escape_sed_replacement "$value")"
  sed -i -E \
    "0,/^([[:space:]]*${variable}[[:space:]]*[:?+]?=[[:space:]]*).*/s|^([[:space:]]*${variable}[[:space:]]*[:?+]?=[[:space:]]*).*|\\1${escaped_value}|" \
    "$file"
}

make_variable_exists() {
  local file="$1"
  local variable="$2"

  grep -Eq "^[[:space:]]*${variable}[[:space:]]*[:?+]?=" "$file"
}

normalize_apk_metadata() {
  log 'Normalizing package versions for OpenWrt 25.12 APK metadata'

  local makefile version release normalized_version normalized_release
  local version_changes=0
  local release_changes=0

  for makefile in */Makefile; do
    CURRENT_ITEM="$makefile"
    version="$(read_package_version "$makefile" | head -n 1)"
    [[ -n "$version" ]] || continue
    release="$(read_package_release "$makefile")"
    normalized_version="$(normalize_apk_version "$version")"
    normalized_release="$(normalize_apk_release "$release")"

    # A literal -rN in PKG_VERSION is only valid when PKG_RELEASE is empty;
    # otherwise package-defaults.mk would produce ...-rN-rM.
    if [[ "$normalized_release" =~ ^[0-9]+$ && "$normalized_version" =~ ^(.+)-r[0-9]+$ ]]; then
      normalized_version="${BASH_REMATCH[1]}"
    fi

    if [[ "$version" == *'$('* ]]; then
      if [[ "$release" != "$normalized_release" && -n "$normalized_release" && "$normalized_release" != *'$('* && "$normalized_release" != *'${'* ]]; then
        replace_make_variable "$makefile" PKG_RELEASE "$normalized_release"
        ((release_changes += 1))
        log "Normalized PKG_RELEASE in ${makefile}: ${release} -> ${normalized_release}"
      fi
      continue
    fi

    if ! is_apk_version "$normalized_version"; then
      log "Using APK-safe fallback PKG_VERSION in ${makefile}: ${version} -> 0"
      normalized_version='0'
    fi

    if [[ "$(trim_version "$version")" != "$normalized_version" ]] && version_is_used_for_source "$makefile"; then
      preserve_upstream_version_references "$makefile" "$version"
    fi

    if [[ "$normalized_version" != "$version" ]]; then
      replace_make_variable "$makefile" PKG_VERSION "$normalized_version"
      ((version_changes += 1))
      log "Normalized PKG_VERSION in ${makefile}: ${version} -> ${normalized_version}"
    fi

    if [[ "$release" != "$normalized_release" && -n "$normalized_release" && "$normalized_release" != *'$('* && "$normalized_release" != *'${'* ]]; then
      replace_make_variable "$makefile" PKG_RELEASE "$normalized_release"
      ((release_changes += 1))
      log "Normalized PKG_RELEASE in ${makefile}: ${release} -> ${normalized_release}"
    fi
  done

  CURRENT_ITEM=''
  log "Normalized ${version_changes} PKG_VERSION field(s) and ${release_changes} PKG_RELEASE field(s)"
}

normalize_release_tag() {
  local version="$1"

  version="$(trim_version "$version")"
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
  local default_oid current_version current_version_raw latest_version upstream_latest_version
  local upstream_source_version current_source_version release_oid release

  for makefile in */Makefile; do
    package="${makefile%%/*}"
    is_source_update_excluded "$package" && continue

    repository="$(extract_github_repository "$makefile")" || continue
    CURRENT_ITEM="${package} (${repository})"
    get_repository_metadata "$repository" || continue
    metadata="$REPOSITORY_METADATA_RESULT"

    current_version_raw="$(read_package_version "$makefile")"
    [[ "$current_version_raw" != *'$('* ]] || continue
    current_version="$(normalize_apk_version "$(normalize_release_tag "$current_version_raw")")"
    is_apk_version "$current_version" || {
      warn "Skipping ${package}: current PKG_VERSION is not APK-compatible (${current_version:-<empty>})."
      continue
    }

    upstream_latest_version="$(normalize_release_tag "$(
      jq -r '.data.repository.latestRelease.tagName // empty' <<<"$metadata"
    )")"
    latest_version="$(normalize_apk_version "$upstream_latest_version")"
    [[ "$latest_version" =~ [0-9] ]] || continue
    [[ "$latest_version" != *'('* ]] || continue
    if ! is_apk_version "$latest_version"; then
      warn "Skipping ${package}: GitHub release tag is not APK-compatible (${latest_version})."
      continue
    fi

    release="$(trim_version "$(read_package_release "$makefile")")"
    if [[ -n "$release" && "$release" =~ ^[0-9]+$ ]] &&
      ! is_apk_version "${latest_version}-r${release}"; then
      warn "Skipping ${package}: ${latest_version}-r${release} is not a valid APK package version."
      continue
    fi

    default_oid="$(jq -r '.data.repository.defaultBranchRef.target.oid // empty' <<<"$metadata")"
    if ! version_lt "$current_version" "$latest_version"; then
      if [[ -n "$default_oid" ]] && make_variable_exists "$makefile" PKG_SOURCE_VERSION; then
        replace_make_variable "$makefile" PKG_SOURCE_VERSION "$default_oid"
      fi
      continue
    fi
    log "Updating ${package} from ${repository}: ${current_version} -> ${latest_version}"

    release_oid="$(
      jq -r '
        .data.repository.latestRelease.tagCommit.oid //
        .data.repository.refs.nodes[-1].target.oid //
        empty
      ' <<<"$metadata"
    )"
    [[ -n "$release_oid" ]] || continue

    if ! make_variable_exists "$makefile" PKG_VERSION; then
      printf '::error file=%s,title=Package version update failed::repository=%s; version=%s\n' \
        "$makefile" "$repository" "$latest_version" >&2
      return 1
    fi
    if make_variable_exists "$makefile" PKG_SOURCE_TAG; then
      current_source_version="$(sed -nE 's/^[[:space:]]*PKG_SOURCE_TAG[[:space:]]*[:?+]?=[[:space:]]*(.*)$/\1/p' "$makefile" | head -n 1)"
      upstream_source_version="$upstream_latest_version"
      if [[ "$current_source_version" == v* ]]; then
        upstream_source_version="v${upstream_source_version#v}"
      elif [[ "$current_source_version" == release-* ]]; then
        upstream_source_version="release-${upstream_source_version#release-}"
      fi
      replace_make_variable "$makefile" PKG_SOURCE_TAG "$upstream_source_version"
    elif [[ "$upstream_latest_version" != "$latest_version" ]] && version_is_used_for_source "$makefile"; then
      preserve_upstream_version_references "$makefile" "$upstream_latest_version"
      replace_make_variable "$makefile" PKG_SOURCE_TAG "$upstream_latest_version"
    fi
    replace_make_variable "$makefile" PKG_VERSION "$latest_version"
    if make_variable_exists "$makefile" PKG_SOURCE_VERSION; then
      replace_make_variable "$makefile" PKG_SOURCE_VERSION "$release_oid"
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
  run_stage 'normalize APK package metadata' normalize_apk_metadata
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

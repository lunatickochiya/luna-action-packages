#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

CURRENT_STAGE='startup'
CURRENT_ITEM=''

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

  require_command git

  trap 'handle_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

  run_stage 'replace legacy network options' replace_legacy_ifname
  run_stage 'normalize LuCI controllers' normalize_luci_controllers
  run_stage 'run DIY generators' run_diy_helpers
  run_stage 'apply package overrides' apply_package_overrides
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

CURRENT_OPERATION='startup'

handle_error() {
  local status="$1"
  local line="$2"
  local command="$3"

  trap - ERR
  printf '::error title=Package preparation failed::operation=%s; line=%s; exit=%s; command=%q\n' \
    "$CURRENT_OPERATION" "$line" "$status" "$command" >&2
  exit "$status"
}

move_entries() {
  local description="$1"
  shift

  CURRENT_OPERATION="move ${description}"
  if (($# == 0)); then
    printf '::error title=Expected package files are missing::operation=%s\n' "$CURRENT_OPERATION" >&2
    return 1
  fi
  printf '[prepare-packages] %s: %s entries\n' "$description" "$#"
  mv -n "$@" ./
}

merge_luci_packages() {
  local entry package
  local entries=(luciapp/*)

  CURRENT_OPERATION='merge selected LuCI packages'
  ((${#entries[@]} > 0)) || {
    printf '::error title=LuCI staging directory is empty::directory=luciapp\n' >&2
    return 1
  }

  for entry in "${entries[@]}"; do
    package="${entry##*/}"
    case "$package" in
      luci-app-noddos | \
      luci-app-cshark | \
      luci-app-dnscrypt-proxy | \
      luci-app-https-dns-proxy | \
      luci-app-ssr-mudb-server | \
      luci-app-ledtrig-*)
        continue
        ;;
    esac
    mv -n "$entry" ./
  done
  rm -rf luciapp
}

overlay_diy_packages() {
  local source destination package
  local sources=(.github/diy/packages/*)

  CURRENT_OPERATION='overlay DIY packages'
  for source in "${sources[@]}"; do
    [[ -d "$source" ]] || continue
    package="${source##*/}"
    destination="./${package}"
    printf '[prepare-packages] overlay %s\n' "$package"
    mkdir -p "$destination"
    cp -rf "$source/." "$destination/"

    if [[ -f "$source/Makefile.k" ]]; then
      cp -f "$source/Makefile.k" "$destination/Makefile"
      rm -f "$destination/Makefile.k"
    fi
  done
}

main() {
  local repository_root
  repository_root="$(git rev-parse --show-toplevel)"
  cd "$repository_root"
  trap 'handle_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

  printf '::group::Prepare packages - merge upstream trees\n'
  merge_luci_packages
  move_entries 'Lean packages' lean/*
  rm -rf lean
  move_entries 'Lienol packages' liep/*
  rm -rf liep
  move_entries 'WWAN packages' wwan/*/*
  rm -rf wwan

  CURRENT_OPERATION='rename shortcut-fe to shortcut-fe-mod'
  [[ -d shortcut-fe ]] || {
    printf '::error title=Required package missing::directory=shortcut-fe\n' >&2
    return 1
  }
  mv shortcut-fe shortcut-fe-mod
  move_entries 'shortcut-fe-mod packages' shortcut-fe-mod/*
  rm -rf shortcut-fe-mod

  move_entries 'openwrt-app-actions packages' openwrt-app-actions/applications/*
  rm -rf openwrt-app-actions
  printf '::endgroup::\n'

  printf '::group::Prepare packages - clean metadata and apply DIY overlay\n'
  CURRENT_OPERATION='remove nested VCS metadata'
  find . -mindepth 2 -maxdepth 2 -type d \( -name .git -o -name .svn \) -prune -exec rm -rf {} +
  overlay_diy_packages
  printf '::endgroup::\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

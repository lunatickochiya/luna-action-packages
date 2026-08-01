#!/usr/bin/env bash

set -Eeuo pipefail

CURRENT_OPERATION='startup'
CURRENT_ITEM=''

handle_error() {
  local status="$1"
  local line="$2"
  local command="$3"

  trap - ERR
  printf '::error title=Commit or push failed::operation=%s; item=%s; line=%s; exit=%s; command=%q\n' \
    "$CURRENT_OPERATION" "${CURRENT_ITEM:-n/a}" "$line" "$status" "$command" >&2
  exit "$status"
}

main() {
  local repository_root commit_message package makefile release branch status
  local changed_packages=()

  repository_root="$(git rev-parse --show-toplevel)"
  cd "$repository_root"
  trap 'handle_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

  commit_message="Sync upstream $(date '+%Y-%m-%d %H:%M:%S')"
  CURRENT_OPERATION='stage synchronized files'
  git add --all

  if git diff --cached --quiet; then
    printf '::notice title=No upstream changes::Nothing to commit or push.\n'
    return 0
  fi

  CURRENT_OPERATION='create temporary release-count commit'
  git commit -m "$commit_message"

  CURRENT_OPERATION='collect changed packages'
  mapfile -t changed_packages < <(
    git diff-tree --no-commit-id --name-only -r HEAD |
      cut -d/ -f1 |
      sort -u
  )

  CURRENT_OPERATION='update changed package release numbers'
  for package in "${changed_packages[@]}"; do
    makefile="$package/Makefile"
    CURRENT_ITEM="$makefile"
    if [[ -f "$makefile" ]] && grep -q '^PKG_RELEASE:=' "$makefile"; then
      release="$(git rev-list --count HEAD -- "$package")"
      sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=$release/" "$makefile"
    fi
  done

  CURRENT_ITEM=''
  CURRENT_OPERATION='replace temporary commit with final commit'
  git reset --soft HEAD^
  git add --all
  git commit -m "$commit_message"

  CURRENT_OPERATION='push synchronized packages'
  branch="$(git branch --show-current)"
  if git push --force-with-lease; then
    printf '::notice title=Upstream sync pushed::branch=%s; commit=%s\n' \
      "$branch" "$(git rev-parse --short HEAD)"
  else
    status=$?
    printf '::error title=Git push failed::branch=%s; remote=%s; exit=%s; the remote may have changed during this run\n' \
      "$branch" "$(git remote get-url origin)" "$status" >&2
    return "$status"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

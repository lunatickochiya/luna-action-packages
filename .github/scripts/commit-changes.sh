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
  local repository_root commit_message branch status

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

  CURRENT_OPERATION='commit synchronized files'
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

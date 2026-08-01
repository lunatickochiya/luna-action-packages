#!/usr/bin/env bash

set -Eeuo pipefail

CURRENT_PATCH='startup'

handle_error() {
  local status="$1"
  local line="$2"
  local command="$3"

  trap - ERR
  printf '::error file=%s,title=Patch step failed::line=%s; exit=%s; command=%q\n' \
    "$CURRENT_PATCH" "$line" "$status" "$command" >&2
  exit "$status"
}

patch_targets() {
  awk '
    BEGIN { separator = "" }
    /^\+\+\+ / {
      path = $2
      sub(/^b\//, "", path)
      if (path != "/dev/null" && !seen[path]++) {
        printf "%s%s", separator, path
        separator = ","
      }
    }
    END { print "" }
  ' "$1"
}

apply_patch_file() {
  local patch_file="$1"
  local targets output status
  local options=(
    -d .
    -p1
    --batch
    -E
    --forward
    --no-backup-if-mismatch
  )

  CURRENT_PATCH="$patch_file"
  targets="$(patch_targets "$patch_file")"
  printf '::group::Patch - %s\n' "$patch_file"
  printf '[apply-patches] file=%s\n' "$patch_file"
  printf '[apply-patches] targets=%s\n' "${targets:-unknown}"

  if output="$(patch --dry-run "${options[@]}" <"$patch_file" 2>&1)"; then
    printf '[apply-patches] dry-run passed\n'
  else
    status=$?
    printf '%s\n' "$output" >&2
    printf '::error file=%s,title=Patch dry-run failed::targets=%s; exit=%s; see output above for the rejected hunk\n' \
      "$patch_file" "${targets:-unknown}" "$status" >&2
    printf '::endgroup::\n'
    return "$status"
  fi

  if output="$(patch "${options[@]}" <"$patch_file" 2>&1)"; then
    printf '%s\n' "$output"
    printf '[apply-patches] applied successfully\n'
    printf '::endgroup::\n'
  else
    status=$?
    printf '%s\n' "$output" >&2
    printf '::error file=%s,title=Patch apply failed::targets=%s; exit=%s; dry-run passed but apply failed\n' \
      "$patch_file" "${targets:-unknown}" "$status" >&2
    printf '::endgroup::\n'
    return "$status"
  fi
}

main() {
  local repository_root patch_file
  local patches=()

  repository_root="$(git rev-parse --show-toplevel)"
  cd "$repository_root"
  trap 'handle_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

  mapfile -d '' -t patches < <(
    find .github/diy/patches -type f -name '*.patch' -print0 | sort -z
  )
  printf '[apply-patches] patch count=%s\n' "${#patches[@]}"

  for patch_file in "${patches[@]}"; do
    apply_patch_file "$patch_file"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

#!/usr/bin/env bash

set -Eeuo pipefail

fail() {
	printf '::error title=Package file conflict::%s\n' "$1" >&2
	return 1
}

main() {
	local repository_root
	repository_root="$(git rev-parse --show-toplevel)"
	cd "$repository_root"

	if [[ -e luci-app-oaf/root/usr/share/rpcd/acl.d/luci-app-oaf.json ]]; then
		fail 'luci-app-oaf must not package the ACL file owned by appfilter'
	fi

	if [[ -e luci-app-tailscale/root/etc/config/tailscale ]]; then
		fail 'luci-app-tailscale must not package /etc/config/tailscale owned by tailscale'
	fi

	if [[ -e luci-app-tailscale/root/etc/init.d/tailscale ]]; then
		fail 'luci-app-tailscale must not package /etc/init.d/tailscale owned by tailscale'
	fi

	grep -q '^  DEPENDS:=+luci-app-tailscale-community$' luci-app-tailscale/Makefile ||
		fail 'luci-app-tailscale must remain a compatibility package for luci-app-tailscale-community'

	printf '[check-package-conflicts] known package ownership conflicts: none\n'
}

main "$@"

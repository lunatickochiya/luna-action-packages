-- Compatibility shim for luci.model.ipkg on apk-based OpenWrt.
--
-- Older LuCI applications (luci-app-rclone, luci-app-openclash, ...) still
-- require the opkg-era helper module.  OpenWrt 25.12 uses apk and no longer
-- ships /usr/lib/lua/luci/model/ipkg.lua, which makes those pages fail with:
--
--   module 'luci.model.ipkg' not found
--
-- This module implements the small subset of the old API that those
-- applications use, backed by apk.

local sys = require "luci.sys"

local M = {}

local function valid_pkg(pkg)
	return type(pkg) == "string" and pkg:match("^[%w%._+%-]+$") ~= nil
end

local function apk_ok(args)
	return sys.call("apk " .. args .. " >/dev/null 2>&1") == 0
end

function M.installed(pkg)
	return valid_pkg(pkg) and apk_ok("info -e " .. pkg)
end

function M.available(pkg)
	if not valid_pkg(pkg) then
		return false
	end
	if M.installed(pkg) then
		return true
	end
	local f = io.popen("apk search -x " .. pkg .. " 2>/dev/null")
	local out = f and f:read("*a") or ""
	if f then
		f:close()
	end
	return out ~= ""
end

-- The old module returned a table of package metadata.  Current callers have
-- apk fallbacks; returning nil keeps them on that path.
function M.info(pkg)
	return nil
end

function M.version(pkg)
	return nil
end

function M.update()
	return apk_ok("update")
end

function M.install(pkg)
	return valid_pkg(pkg) and apk_ok("add " .. pkg)
end

function M.remove(pkg)
	return valid_pkg(pkg) and apk_ok("del " .. pkg)
end

return M

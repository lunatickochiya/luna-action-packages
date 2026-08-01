#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s extglob nullglob

readonly MAX_PARALLEL_GROUPS="${MAX_PARALLEL_GROUPS:-8}"

log() {
  printf '[sync-upstream] %s\n' "$*"
}

git_clone() {
  local url="$1"
  local destination="${2:-${url##*/}}"
  destination="${destination%.git}"

  log "Cloning ${url}"
  git clone --depth 1 --filter=blob:none --no-tags "$url" "$destination"
}

git_clone_branch() {
  local url="$1"
  local branch="$2"
  local destination="${3:-${url##*/}}"
  destination="${destination%.git}"

  log "Cloning ${url} (${branch})"
  git clone --branch "$branch" --depth 1 --filter=blob:none --no-tags "$url" "$destination"
}

git_sparse_clone() {
  local branch="$1"
  local url="$2"
  local destination="$3"
  shift 3

  log "Sparse cloning ${url} (${branch}): $*"
  git clone --branch "$branch" --depth 1 --filter=blob:none --sparse --no-tags "$url" "$destination"
  git -C "$destination" sparse-checkout set -- "$@"

  local path
  for path in "$@"; do
    [[ -e "$destination/$path" ]] || {
      printf 'Missing sparse-checkout path: %s/%s\n' "$destination" "$path" >&2
      return 1
    }
    mv -n "$destination/$path" ./
  done
  rm -rf "$destination"
}

mvdir() {
  local source="$1"
  local directories=("$source"/*/)

  ((${#directories[@]} > 0)) || {
    printf 'No package directories found in %s\n' "$source" >&2
    return 1
  }
  mv -n "${directories[@]}" ./
  rm -rf "$source"
}

move_contents() {
  local source="$1"
  local entries=("$source"/*)

  ((${#entries[@]} > 0)) || {
    printf 'No files found in %s\n' "$source" >&2
    return 1
  }
  mv -n "${entries[@]}" ./
  rm -rf "$source"
}

clone_many() {
  local url
  for url in "$@"; do
    git_clone "$url"
  done
}

source_group_01() {
  clone_many \
    https://github.com/kiddin9/luci-app-dnsfilter \
    https://github.com/kiddin9/aria2 \
    https://github.com/kiddin9/luci-app-baidupcs-web \
    https://github.com/kiddin9/luci-theme-edge \
    https://github.com/kiddin9/luci-app-xlnetacc \
    https://github.com/kiddin9/luci-app-wizard \
    https://github.com/kiddin9/luci-app-cloudreve

  git_clone https://github.com/kiddin9/autoshare
  mvdir autoshare
  git_clone https://github.com/kiddin9/openwrt-adguardhome
  mvdir openwrt-adguardhome
  git_clone https://github.com/kiddin9/openwrt-clouddrive2
  mv -n openwrt-clouddrive2/clouddrive2 ./
  rm -rf openwrt-clouddrive2
}

source_group_02() {
  git_clone https://github.com/pexcn/openwrt-chinadns-ng chinadns-ng
  git_clone https://github.com/Openwrt-Passwall/openwrt-passwall
  mvdir openwrt-passwall
  git_clone_branch https://github.com/fw876/helloworld master
  mv -n helloworld/{luci-app-ssr-plus,tuic-client,shadow-tls,lua-neturl,redsocks2,gn,dns2tcp,trojan,dns2socks-rust} ./
  rm -rf helloworld
  git_clone https://github.com/Lienol/openwrt-package liep
  rm -rf liep/other
  git_clone_branch https://github.com/AutoCONFIG/minieap-openwrt default
  clone_many \
    https://github.com/rufengsuixing/luci-app-autoipsetadder \
    https://github.com/NateLol/luci-app-beardropper
  git_clone https://github.com/riverscn/openwrt-iptvhelper
  mvdir openwrt-iptvhelper
}

source_group_03() {
  clone_many \
    https://github.com/jerrykuku/luci-theme-argon \
    https://github.com/jerrykuku/luci-app-argon-config \
    https://github.com/eamonxg/luci-theme-aurora \
    https://github.com/eamonxg/luci-app-aurora-config \
    https://github.com/eamonxg/luci-theme-shadcn \
    https://github.com/lunatickochiya/luci-app-advancedplus-mod \
    https://github.com/sirpdboy/luci-app-autotimeset \
    https://github.com/sirpdboy/luci-app-partexp \
    https://github.com/sirpdboy/luci-app-parentcontrol \
    https://github.com/sirpdboy/luci-app-poweroffdevice
  git_clone https://github.com/sirpdboy/luci-app-lucky oplucky
  move_contents oplucky
  git_clone https://github.com/sirpdboy/luci-app-ddns-go ddns-go1
  mvdir ddns-go1
  git_clone https://github.com/sirpdboy/netspeedtest speedtest
  mvdir speedtest
}

source_group_04() {
  git_clone https://github.com/destan19/OpenAppFilter
  mvdir OpenAppFilter
  clone_many \
    https://github.com/destan19/luci-app-harbor-file \
    https://github.com/lvqier/luci-app-dnsmasq-ipset \
    https://github.com/peter-tank/luci-app-autorepeater
  git_clone https://github.com/laipeng668/luci-app-gecoosac openwrt-gecoosac
  mvdir openwrt-gecoosac
  git_clone https://github.com/walkingsky/luci-wifidog luci-app-wifidog
  git_clone https://github.com/brvphoenix/luci-app-wrtbwmon wrtbwmon1
  mvdir wrtbwmon1
  git_clone https://github.com/brvphoenix/wrtbwmon wrtbwmon2
  mvdir wrtbwmon2
  git_clone_branch https://github.com/jjm2473/luci-app-cupsd dev cupsd1
  mv -n cupsd1/{luci-app-cupsd,cups} ./
  rm -rf cupsd1
  git_clone https://github.com/sbwml/luci-app-mosdns openwrt-mos
  mv -n openwrt-mos/{*mosdns,v2dat} ./
  rm -rf openwrt-mos
}

source_group_05() {
  clone_many \
    https://github.com/esirplayground/LingTiGameAcc \
    https://github.com/esirplayground/luci-app-LingTiGameAcc \
    https://github.com/zxlhhyccc/luci-app-v2raya \
    https://github.com/jerrykuku/luci-app-go-aliyundrive-webdav \
    https://github.com/asvow/luci-app-tailscale
  git_clone https://github.com/SSSSSimon/tencentcloud-openwrt-plugin-ddns
  mv -n tencentcloud-openwrt-plugin-ddns/tencentcloud_ddns ./luci-app-tencentddns
  rm -rf tencentcloud-openwrt-plugin-ddns
  git_clone https://github.com/Tencent-Cloud-Plugins/tencentcloud-openwrt-plugin-cos
  mv -n tencentcloud-openwrt-plugin-cos/tencentcloud_cos ./luci-app-tencentcloud-cos
  rm -rf tencentcloud-openwrt-plugin-cos
  git_clone https://github.com/doushang/luci-app-shortcutmenu luci-shortcutmenu
  mv -n luci-shortcutmenu/luci-app-shortcutmenu ./
  rm -rf luci-shortcutmenu
  git_clone https://github.com/messense/aliyundrive-webdav aliyundrive
  move_contents aliyundrive/openwrt
  rm -rf aliyundrive
  git_clone https://github.com/sbilly/netmaker-openwrt
  mv -n netmaker-openwrt/netmaker ./
  rm -rf netmaker-openwrt
  git_clone https://github.com/lisaac/luci-app-dockerman dockerman
  move_contents dockerman/applications
  rm -rf dockerman
}

source_group_06() {
  git_clone https://github.com/ophub/luci-app-amlogic amlogic
  mv -n amlogic/luci-app-amlogic ./
  rm -rf amlogic
  git_clone https://github.com/mingxiaoyu/luci-app-cloudflarespeedtest cloudflarespeedtest
  move_contents cloudflarespeedtest/applications
  rm -rf cloudflarespeedtest
  git_clone https://github.com/Openwrt-Passwall/openwrt-passwall2 passwall2
  mv -n passwall2/luci-app-passwall2 ./
  rm -rf passwall2
  git_clone https://github.com/linkease/nas-packages
  mv -n nas-packages/{network/services/*,multimedia/*} ./
  rm -rf nas-packages
  git_clone https://github.com/linkease/nas-packages-luci
  move_contents nas-packages-luci/luci
  rm -rf nas-packages-luci
  git_clone https://github.com/linkease/istore
  move_contents istore/luci
  rm -rf istore
}

source_group_07() {
  clone_many \
    https://github.com/KyleRicardo/MentoHUST-OpenWrt-ipk \
    https://github.com/frainzy1477/luci-app-clash \
    https://github.com/peter-tank/luci-app-fullconenat \
    https://github.com/KFERMercer/luci-app-tcpdump \
    https://github.com/UnblockNeteaseMusic/luci-app-unblockneteasemusic
  git_clone https://github.com/sbwml/luci-app-openlist oplist
  mvdir oplist
  git_clone https://github.com/ykxVK8yL5L/pikpak-webdav pikpak
  move_contents pikpak/openwrt
  rm -rf pikpak
  git_clone https://github.com/jjm2473/openwrt-apps
  rm -rf openwrt-apps/{luci-app-cpufreq,luci-app-ota,homebox,luci-alias.mk}
  sed -i 's|luci-alias.mk|../luci.mk|' openwrt-apps/*/Makefile
  mvdir openwrt-apps
}

source_group_08() {
  git_clone https://github.com/4IceG/luci-app-sms-tool smstool
  mvdir smstool
  git_clone https://github.com/4IceG/luci-app-modemband modemb
  move_contents modemb
  git_clone https://github.com/obsy/modemband
  clone_many \
    https://github.com/ZeaKyX/speedtest-web \
    https://github.com/ZeaKyX/luci-app-speedtest-web
  git_clone https://github.com/yichya/luci-app-xray yichya
  mv -f yichya/status ./luci-app-xray-status
  mv -f yichya/core ./luci-app-xray
  rm -rf yichya
  clone_many \
    https://github.com/rafmilecki/luci-app-xjay \
    https://github.com/jhonathanc/ps3netsrv-openwrt
  move_contents ps3netsrv-openwrt
  git_clone https://github.com/Internet1235/qy-openwrt
  mvdir qy-openwrt
}

source_group_09() {
  clone_many \
    https://github.com/honwen/luci-app-aliddns \
    https://github.com/peter-tank/luci-app-dnscrypt-proxy2 \
    https://github.com/NateLol/luci-app-oled \
    https://github.com/pymumu/luci-app-smartdns \
    https://github.com/pymumu/openwrt-smartdns \
    https://github.com/CHN-beta/rkp-ipid
  git_clone https://github.com/4IceG/luci-app-3ginfo op3ginfo
  mv -n op3ginfo/{3ginfo,luci-app-3ginfo} ./
  rm -rf op3ginfo
  git_clone https://github.com/sundaqiang/openwrt-packages sundaqiang
  mv -n sundaqiang/luci-* ./
  rm -rf sundaqiang
  git_clone https://github.com/vernesong/OpenClash
  mv -n OpenClash/luci-app-openclash ./
  rm -rf OpenClash
  git_clone https://github.com/Erope/openwrt_nezha nezha
  mvdir nezha
}

source_group_10() {
  clone_many \
    https://github.com/mchome/openwrt-dogcom \
    https://github.com/mchome/luci-app-dogcom \
    https://github.com/zzsj0928/luci-app-pushbot \
    https://github.com/shanglanxin/luci-app-homebridge \
    https://github.com/xptsp/luci-app-nodogsplash \
    https://github.com/xptsp/luci-mod-listening-ports \
    https://github.com/xptsp/luci-app-squid-adv \
    https://github.com/xptsp/openwrt-bcrypt-tool
  git_clone https://github.com/koshev-msk/modemfeed
  rm -rf modemfeed/packages/net/3proxy
  mv -n modemfeed/*/!(telephony)/* ./
  rm -rf modemfeed
  git_clone https://github.com/ykxVK8yL5L/luci-app-synology synology
  mv -n synology/luci-app-synology ./
  rm -rf synology
  git_clone https://github.com/htynkn/openwrt-switch-lan-play
  move_contents openwrt-switch-lan-play/package
  rm -rf openwrt-switch-lan-play
  git_clone https://github.com/kongfl888/openwrt-my-dnshelper
  mvdir openwrt-my-dnshelper
}

source_group_11() {
  git_clone https://github.com/linkease/openwrt-app-actions
  git_clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages
  rm -rf openwrt-passwall-packages/{naiveproxy,tuic-client}
  mvdir openwrt-passwall-packages
}

source_group_12() {
  clone_many \
    https://github.com/honwen/luci-app-shadowsocks-rust \
    https://github.com/Ausaci/luci-app-nat6-helper \
    https://github.com/derisamedia/luci-theme-alpha \
    https://github.com/animegasan/luci-app-alpha-config
  git_clone https://github.com/Hyy2001X/AutoBuild-Packages
  rm -rf AutoBuild-Packages/luci-app-adguardhome
  mvdir AutoBuild-Packages
  git_clone https://github.com/lazywalker/mmdvm-openwrt
  rm -rf mmdvm-openwrt/misc
  mvdir mmdvm-openwrt
}

source_group_13() {
  clone_many \
    https://github.com/BoringCat/luci-app-minieap \
    https://github.com/izilzty/luci-app-chinadns-ng \
    https://github.com/Diciya/luci-app-broadbandacc \
    https://github.com/zerolabnet/luci-app-torbp
  git_clone https://github.com/wiwizcom/WiFiPortal
  mvdir WiFiPortal
  git_clone https://github.com/vinewx/NanoHatOLED
  mv -n NanoHatOLED/nanohatoled ./
  rm -rf NanoHatOLED
  git_clone https://github.com/sbwml/luci-app-airconnect airconnect1
  move_contents airconnect1
}

source_group_14() {
  git_clone_branch https://github.com/sirpdboy/luci-theme-kucat master
  git_clone https://github.com/sirpdboy/luci-app-kucat-config
  clone_many \
    https://github.com/blueberry-pie-11/luci-app-natmap \
    https://github.com/sirpdboy/luci-app-chatgpt-web \
    https://github.com/sirpdboy/luci-app-eqosplus \
    https://github.com/danchexiaoyang/luci-app-syncthing
  git_clone https://github.com/QiuSimons/luci-app-daed-next daed1
  mvdir daed1
  git_clone https://github.com/kiddin9/openwrt-netdata netdata
  git_clone https://github.com/JiaY-shi/fancontrol fanc
  mvdir fanc
  git_clone https://github.com/Siriling/5G-Modem-Support
  mv -n 5G-Modem-Support/{luci-app-modem,luci-app-cpe,luci-app-sms-tool,ndisc} ./
  rm -rf 5G-Modem-Support
}

source_group_15() {
  clone_many \
    https://github.com/muink/luci-app-dnsproxy \
    https://github.com/muink/luci-app-einat \
    https://github.com/muink/openwrt-einat-ebpf \
    https://github.com/muink/openwrt-natmapt \
    https://github.com/muink/luci-app-natmapt \
    https://github.com/muink/openwrt-stuntman \
    https://github.com/muink/openwrt-alwaysonline \
    https://github.com/muink/luci-app-alwaysonline \
    https://github.com/muink/openwrt-rgmac \
    https://github.com/muink/luci-app-change-mac \
    https://github.com/muink/luci-app-packagesync \
    https://github.com/muink/luci-app-tn-netports \
    https://github.com/muink/openwrt-go-stun \
    https://github.com/muink/luci-app-tinyfilemanager
}

source_group_16() {
  clone_many \
    https://github.com/gSpotx2f/luci-app-temp-status \
    https://github.com/gSpotx2f/luci-app-cpu-perf \
    https://github.com/gSpotx2f/luci-app-log \
    https://github.com/gSpotx2f/luci-app-internet-detector \
    https://github.com/gSpotx2f/luci-app-disks-info \
    https://github.com/gSpotx2f/luci-app-interfaces-statistics \
    https://github.com/gSpotx2f/luci-app-cpu-status-mini \
    https://github.com/gSpotx2f/luci-app-cpu-status
  git_clone https://github.com/Carseason/openwrt-packages Carseason
  mv -n Carseason/*/* ./
  mv -n services/routergo ./
  rm -rf Carseason
  git_clone https://github.com/Carseason/openwrt-themedog
  move_contents openwrt-themedog/luci
  rm -rf openwrt-themedog
  git_clone https://github.com/Carseason/openwrt-app-actions Carseason
  move_contents Carseason/applications
  rm -rf Carseason
  git_clone_branch https://github.com/Thaolga/luci-app-nekoclash neko nekoclash
  mv -n nekoclash/luci-app-nekoclash ./
  rm -rf nekoclash
  git_clone https://github.com/nosignals/openwrt-neko
  mv -n openwrt-neko/{luci-app-neko,mihomo} ./
  rm -rf openwrt-neko
  git_clone https://github.com/nikkinikki-org/OpenWrt-nikki
  mv -n OpenWrt-nikki/{luci-app-nikki,nikki} ./
  rm -rf OpenWrt-nikki
  git_clone https://github.com/fcshark-org/openwrt-fchomo
  mvdir openwrt-fchomo
  git_clone https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community tailscalec
  mv -n tailscalec/luci-app-tailscale-community ./
  rm -rf tailscalec
}

source_group_17() {
  clone_many \
    https://github.com/liudf0716/luci-app-yt-dlp \
    https://github.com/liudf0716/luci-app-kcptun \
    https://github.com/liudf0716/luci-app-xfrpc \
    https://github.com/liudf0716/luci-app-apfree-wifidog \
    https://github.com/ilxp/luci-app-ikoolproxy \
    https://github.com/animegasan/luci-app-droidnet \
    https://github.com/animegasan/luci-app-ipinfo \
    https://github.com/animegasan/luci-app-dnsleaktest \
    https://github.com/animegasan/luci-app-gpioled
  git_clone https://github.com/liudf0716/actions-apfree-wifidog
  mv -n actions-apfree-wifidog/apfree-wifidog ./
  rm -rf actions-apfree-wifidog
  git_clone https://github.com/hingbong/hickory-dns-openwrt
  mvdir hickory-dns-openwrt
}

source_group_18() {
  clone_many \
    https://github.com/EasyTier/luci-app-easytier \
    https://github.com/ntlf9t/luci-app-dnspod \
    https://github.com/jarod360/luci-app-xupnpd \
    https://github.com/fuqiang03/openwrt-caddy \
    https://github.com/lmq8267/luci-app-caddy \
    https://github.com/sbwml/luci-app-smbuser \
    https://github.com/rushxrushx/luci-app-redsocks \
    https://github.com/luochongjun/luci-app-dynv6 \
    https://github.com/nicholas9698/luci-app-campusnet
  git_clone https://github.com/lmq8267/luci-app-vnt opvnt
  mv -f opvnt/luci-app-vnt ./
  rm -rf opvnt
  git_clone https://github.com/RymFred11/luci-app-nettask nettask
  mv -n nettask/luci-app-nettask ./
  rm -rf nettask
}

source_group_19() {
  clone_many \
    https://github.com/jackpang960/luci-app-hypermodem \
    https://github.com/CrazyPegasus/luci-app-accesscontrol-plus \
    https://github.com/4IceG/luci-app-lite-watchdog \
    https://github.com/Mitsuhaxy/luci-app-miniproxy \
    https://github.com/arenekosreal/luci-app-nginx \
    https://github.com/lunatickochiya/luci-app-school \
    https://github.com/tano-systems/luci-app-tn-lldpd \
    https://github.com/DRAWCORE/luci-app-qos-emong \
    https://github.com/wintbiit/luci-app-sakurafrp \
    https://github.com/douo/luci-app-tinyfecvpn
  git_clone https://github.com/tkmsst/luci-app-cellularstatus cellularstatus
  move_contents cellularstatus/luci/applications
  rm -rf cellularstatus
  git_clone https://github.com/tracemouse/luci-app-coredns coredns
  mv -n coredns/luci-app-coredns ./
  rm -rf coredns
  git_clone https://github.com/ykxVK8yL5L/luci-app-taskschedule taskschedule
  mvdir taskschedule
}

source_group_20() {
  clone_many \
    https://github.com/ttimasdf/luci-app-jederproxy \
    https://github.com/ApeaSuperz/luci-app-cqustdotnet \
    https://github.com/xcode75/luci-app-xclient \
    https://github.com/mukaiu/luci-app-domain-proxy \
    https://github.com/danielaskdd/luci-app-smartvpn \
    https://github.com/hequan2017/luci-app-forcedata
  git_clone https://github.com/chenzhen6666/luci-app-mproxy mproxy
  mvdir mproxy
  git_clone https://github.com/sbwml/luci-app-openai opai
  mvdir opai
}

source_group_21() {
  clone_many \
    https://github.com/muink/luci-app-ssrust \
    https://github.com/hudra0/qosmate \
    https://github.com/muink/luci-app-netdata \
    https://github.com/xptsp/luci-app-ympd \
    https://github.com/xptsp/openwrt-ympd \
    https://github.com/xptsp/openwrt-peanut \
    https://github.com/calfeche13/luci-app-public-ip-monitor \
    https://github.com/tty228/luci-app-wechatpush \
    https://github.com/AngelaCooljx/luci-theme-material3 \
    https://github.com/sbwml/luci-app-webdav \
    https://github.com/sbwml/package_kernel_tcp-brutal \
    https://github.com/hudra0/luci-app-qosmate
  git_clone https://github.com/sbwml/luci-app-quickfile quickf
  mvdir quickf
}

source_group_22() {
  git_clone https://github.com/QiuSimons/OpenWrt-Add
  mv -n OpenWrt-Add/luci-app-irqbalance ./
  rm -rf OpenWrt-Add
  git_clone https://github.com/lucikap/Brukamen
  mv -n Brukamen/luci-app-ua2f ./
  rm -rf Brukamen
  git_clone https://github.com/HiGarfield/lede-17.01.4-Mod
  mv -n lede-17.01.4-Mod/package/extra/luci-app-openvpn-server ./
  rm -rf lede-17.01.4-Mod
  git_clone_branch https://github.com/syb999/openwrt-15.05 master
  mv -n openwrt-15.05/package/network/services/openwrt-netem/{luci-app-netem,netem-control} ./
  rm -rf openwrt-15.05
}

source_group_23() {
  git_sparse_clone master https://github.com/coolsnowwolf/packages leanpkg \
    net/mwan3 multimedia/UnblockNeteaseMusic-Go utils/bandwidthd \
    multimedia/UnblockNeteaseMusic net/softethervpn5 net/baidupcs-web \
    multimedia/gmediarender multimedia/pppwn-cpp net/go-aliyundrive-webdav \
    net/qBittorrent-static net/phtunnel net/frp net/uugamebooster net/verysync \
    net/vlmcsd net/dnsforwarder net/tcpping net/netatalk net/pgyvpn
  git_sparse_clone openwrt-23.05 https://github.com/openwrt/packages oppackages \
    utils/coremark utils/watchcat utils/dockerd utils/cgroupfs-mount net/uwsgi \
    net/ddns-scripts net/curl net/ariang net/rp-pppoe
}

source_group_24() {
  git_sparse_clone openwrt-23.05 https://github.com/openwrt/openwrt openwrt \
    package/base-files package/network/config/firewall4 package/network/config/firewall \
    package/system/opkg package/network/services/ppp package/network/services/dnsmasq
  git_sparse_clone openwrt-23.05 https://github.com/openwrt/luci opluci \
    applications/luci-app-attendedsysupgrade applications/luci-app-aria2 \
    applications/luci-app-ddns applications/luci-app-acme applications/luci-app-opkg \
    applications/luci-app-firewall applications/luci-app-ksmbd applications/luci-app-samba4 \
    applications/luci-app-watchcat applications/luci-app-upnp applications/luci-app-transmission \
    modules/luci-base modules/luci-mod-network modules/luci-mod-status modules/luci-mod-system
  git_sparse_clone main https://github.com/qosmio/packages-extra nssextra modules/luci-mod-status-nss
}

source_group_25() {
  git_sparse_clone openwrt-23.05 https://github.com/immortalwrt/packages immpkgs-pdnsd-alt \
    net/pdnsd-alt net/dufs net/mwol
}

source_group_26() {
  git_sparse_clone openwrt-24.10 https://github.com/immortalwrt/packages immpkgs \
    net/n2n net/dae net/sub-web net/dnsproxy net/haproxy net/v2raya net/cdnspeedtest \
    net/keepalived net/amule libs/antileech net/go-nats net/go-wol net/bitsrunlogin-go \
    net/transfer net/sysuh3c net/3proxy net/cloudreve net/daed lang/node-pnpm \
    net/subconverter net/ngrokc net/oscam net/njit8021xclient net/scutclient net/gost \
    net/ua2f net/qBittorrent-Enhanced-Edition net/tinyportmapper net/tinyfecvpn \
    net/nexttrace net/pcap-dnsproxy net/rustdesk-server net/tuic-server net/speedtest-go \
    net/speedtest-cli net/dns-forwarder net/ipset-lists net/ShadowVPN net/cloudflared \
    net/nps net/naiveproxy lang/lua-maxminddb net/pdnsd-alt libs/jpcre2 libs/wxbase \
    libs/rapidjson libs/libcron libs/libcryptopp libs/quickjspp libs/toml11 \
    libs/libtorrent-rasterbar libs/libdouble-conversion libs/qt6base libs/cxxopts \
    libs/alac sound/spotifyd utils/qt6tools utils/cpulimit utils/filebrowser \
    utils/cups-bjnp utils/joker net/udp2raw net/msd_lite multimedia/you-get \
    multimedia/lux multimedia/ykdl multimedia/gallery-dl devel/go-rice admin/gotop
}

source_group_27() {
  git_sparse_clone develop https://github.com/Ysurac/openmptcprouter-feeds openmptcp \
    luci-app-snmpd luci-app-packet-capture luci-app-mail msmtp luci-app-iperf atinout
  git_sparse_clone master https://github.com/xiaoqingfengATGH/feeds-xiaoqingfeng xiaoqingfeng \
    homeredirect luci-app-homeredirect
  git_sparse_clone master https://github.com/immortalwrt/immortalwrt immortal \
    package/emortal/autocore package/emortal/automount package/network/utils/fullconenat \
    package/network/utils/fullconenat-nft package/network/utils/nftables \
    package/emortal/cpufreq package/utils/mhz package/libs/libnftnl \
    package/firmware/wireless-regdb
  git_sparse_clone openwrt-23.05 https://github.com/immortalwrt/immortalwrt immortal1 \
    package/kernel/r8168 package/kernel/r8125 package/kernel/rtl8188eu \
    package/kernel/rtl8192eu package/kernel/rtl8821cu package/kernel/rtl8812au-ac \
    package/kernel/rtl8189es
}

source_group_28() {
  git_sparse_clone master https://github.com/x-wrt/com.x-wrt x-wrt \
    luci-app-macvlan luci-app-xwan
  git_sparse_clone master https://github.com/sbwml/openwrt_pkgs openwrt_pkgs luci-app-socat
  git_sparse_clone master https://github.com/immortalwrt/luci immluci1 \
    applications/luci-app-dufs applications/luci-app-libreswan \
    applications/luci-app-strongswan-swanctl
  git_sparse_clone openwrt-24.10 https://github.com/immortalwrt/luci immluci2 \
    applications/luci-app-homeproxy
  git_sparse_clone master https://github.com/immortalwrt/packages immpkgs1 \
    utils/swanmon libs/davici libs/libcron
  git_sparse_clone openwrt-25.12 https://github.com/coolsnowwolf/luci applications \
    protocols/luci-proto-openvpnc themes/luci-theme-design
  git_sparse_clone master https://github.com/coolsnowwolf/lede leanlede \
    package/lean package/qca/shortcut-fe package/wwan \
    package/network/services/shellsync package/network/services/e2guardian \
    package/network/services/noddos
}

run_source_groups() {
  local groups=(
    source_group_{01..28}
  )
  local staging_root="$PWD/.sync-upstream"
  local group running=0 failed=0

  rm -rf "$staging_root"
  mkdir -p "$staging_root"

  for group in "${groups[@]}"; do
    mkdir -p "$staging_root/$group"
    (
      cd "$staging_root/$group"
      "$group"
    ) &
    ((running += 1))

    if ((running >= MAX_PARALLEL_GROUPS)); then
      if ! wait -n; then
        failed=1
      fi
      ((running -= 1))
    fi
  done

  while ((running > 0)); do
    if ! wait -n; then
      failed=1
    fi
    ((running -= 1))
  done

  ((failed == 0)) || {
    printf 'One or more upstream source groups failed.\n' >&2
    return 1
  }

  local entries
  for group in "${groups[@]}"; do
    entries=("$staging_root/$group"/*)
    ((${#entries[@]} > 0)) || {
      printf 'Upstream source group produced no files: %s\n' "$group" >&2
      return 1
    }
    mv -n "${entries[@]}" ./
  done
  rm -rf "$staging_root"
}

clean_old_packages() {
  local directory
  for directory in ./*/; do
    rm -rf "$directory"
  done
}

main() {
  local repository_root
  repository_root="$(git rev-parse --show-toplevel)"
  cd "$repository_root"

  [[ -d .github/diy ]] || {
    printf 'Run this script from the packages repository.\n' >&2
    return 1
  }
  [[ "$MAX_PARALLEL_GROUPS" =~ ^[1-9][0-9]*$ ]] || {
    printf 'MAX_PARALLEL_GROUPS must be a positive integer.\n' >&2
    return 1
  }

  clean_old_packages
  run_source_groups

  git_sparse_clone master https://github.com/coolsnowwolf/luci leluci applications libs/luci-lib-fs
  mv -f applications luciapp
  rm -rf luciapp/{luci-app-qbittorrent,luci-app-cpufreq,luci-app-zerotier,luci-app-ipsec-server,luci-app-ipsec-vpnd,luci-app-e2guardian,luci-app-webdav,luci-app-aliyundrive-fuse}

  git_sparse_clone openwrt-23.05 https://github.com/immortalwrt/luci immluci \
    applications protocols/luci-proto-minieap
  mv -n applications/* luciapp/
  rm -rf applications
  rm -rf luciapp/{luci-app-ipsec-vpnd,luci-app-ipsec-vpnserver-manyusers,luci-app-homeproxy}

  local ipk
  for ipk in luciapp/!(luci-app-rclone|luci-app-mwan3)/; do
    if [[ -d "$ipk/po" ]] && (($(find "$ipk/po" -mindepth 1 -maxdepth 1 | wc -l) > 3)); then
      rm -rf "$ipk"
    fi
  done
}

main "$@"

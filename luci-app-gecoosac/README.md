<h1 align="center">OpenWrt 集客AC控制器 JS 增强版</h1>

> 注意：仅支持集客 AP 7.6 及以上版本固件，低版本固件无法接收 AC 下发的配置，有条件的建议更新 AP 固件到 8.x 及以上版本。特别感谢`lwb1978`大佬的付出！下载地址：[Packages](https://github.com/laipeng668/openwrt-ci-roc/releases/tag/Packages)

---

### 下载源码:

 ```Bash

   git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac

 ```

### 配置菜单:

 ```Bash

   make menuconfig # 选择 LUCI -> Applications -> luci-app-gecoosac

 ```

### 编译:

 ```Bash

   make package/luci-app-gecoosac/compile V=s # 构建 luci-app-gecoosac

 ```

<h2 align="center">页面预览</h2>

![Homepage](Homepage.png)
# 集客 AC OpenWrt 插件 2.2 版
### 注意：2.2 版仅支持集客 AP 7.6 及以上版本的固件，低版本固件无法接收 AC 下发的配置，有条件的建议更新 AP 固件到 8.x 。
### 另外：由于 2.2 版 软AC 增加了参数，本仓库不再兼容 2.2 以下版本的 AC 程序。
-------------------------------------------

### 下载源码方法:

 ```Brach

   # 下载源码
   git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
   make menuconfig

 ```

### 配置菜单:

 ```Brach

   make menuconfig
   # 找到 LuCI -> Applications, 选择 luci-app-gecoosac, 保存后退出。

 ```

### 编译:

 ```Brach

   # 编译固件
   make package/luci-app-gecoosac/compile V=s

 ```

### 致谢:

 ```Brach

   特别感谢lwb1978大佬的付出！

 ```


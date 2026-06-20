<h1 align="center">OpenWrt 集客AC控制器 JS 增强版</h1>

> 注意：仅支持集客 AP 7.6 及以上版本固件，低版本固件无法接收 AC 下发的配置，有条件的建议更新 AP 固件到 8.x 及以上版本。

---

### 下载源码:

 ```Bash

   git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac

 ```

### 配置菜单:

 ```Bash

   make menuconfig
   # 找到 LuCI -> Applications, 选择 luci-app-gecoosac, 保存后退出。

 ```

### 编译:

 ```Bash

   make package/luci-app-gecoosac/compile V=s

 ```

### LuCI 位置:

> 服务 -> 集客AC控制器

### 致谢:

> 特别感谢lwb1978大佬的付出！

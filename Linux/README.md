# RealityLink for Linux

RealityLink Linux 是多协议 Electron GUI 客户端，默认面向 Ubuntu/
Debian 22.04+，支持 x86_64 与 arm64。数据面使用固定版本的 sing-box 1.13.14。

## 功能

- 导入 VLESS、VMess、Trojan、Shadowsocks、Hysteria2、TUIC 分享链接
- 导入 `sub://` 与 HTTP(S) 订阅，按订阅分组、更新和删除
- 节点添加、编辑、删除、延迟测试和本地持久化
- 全局 TUN TCP/UDP 接管
- 连接中热切换节点
- 首次连接通过 polkit/pkexec 授权，切换和正常断开不重复授权
- 配置启动前调用 `sing-box check`
- 实时日志和异常退出提示

## 开发运行

需要 Node.js 22+、npm，以及带图形 polkit agent 的 Linux 桌面环境。

```bash
cd Linux
npm ci
npm run prepare-core
npm start
```

不要使用 root 启动 Electron；连接时仅 TUN 控制进程通过 `pkexec` 获取权限。

## 测试与打包

```bash
npm test
npm run dist
```

输出位于 `Linux/dist/`，包含 AppImage 和 Debian 软件包。构建脚本根据当前
机器架构下载 sing-box，并验证上游 SHA-256。交叉发布另一架构时，应在对应
架构的 GitHub Actions runner 或 Linux 构建机上执行。

AppImage 使用：

```bash
chmod +x RealityLink-0.2.0-linux-x86_64.AppImage
./RealityLink-0.2.0-linux-x86_64.AppImage
```

Ubuntu/Debian 安装：

```bash
sudo apt install ./RealityLink-0.2.0-linux-amd64.deb
```

## 数据与恢复

节点与设置保存在 Electron 的用户数据目录，文件权限为 `0600`；运行配置与
日志位于其 `runtime/` 子目录。App 正常退出会先发送 TUN 停止信号。若 App
崩溃，重新启动后会检测仍在运行的受管 sing-box，并允许用户正常断开。

目前只提供跨桌面环境一致的全局 TUN。GNOME `gsettings`、KDE 配置和环境变量
代理行为不同，因此首版不提供标为“通用”的系统代理模式。

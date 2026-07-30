# RealityLink for Windows

RealityLink Windows 是面向 Windows 10/11 的多协议 Electron GUI，
支持 x86_64 与 arm64，数据面使用固定版本的 sing-box 1.13.14。

## 功能

- 导入 VLESS、VMess、Trojan、Shadowsocks、Hysteria2、TUIC 分享链接
- 导入 `sub://` 与 HTTP(S) 订阅，按订阅分组、更新和删除
- 节点添加、编辑、删除、延迟测试和本地持久化
- 全局 TUN TCP/UDP 接管
- 连接中热切换节点
- 每次连接只显示一次 Windows UAC；热切换和正常断开不重复授权
- 启动前运行 `sing-box check`
- 实时标准输出与错误日志
- App 异常退出后恢复受管 TUN 会话

## 开发

需要 Node.js 22+、npm、Windows 10/11 和 PowerShell 5.1+：

```powershell
cd Windows
npm ci
npm run prepare-core
npm start
```

不要以管理员身份直接运行整个 Electron App。只有连接期间的 TUN 控制脚本通过
UAC 提权，并将 sing-box 复制到仅 SYSTEM/Administrators 可修改的临时目录。

## 测试与打包

```powershell
npm test
npm run dist
```

输出位于 `Windows/dist/`，包括可安装的 NSIS `.exe` 和便携版 `.exe`，并为
每个产物生成 `.sha256`。构建脚本固定下载 sing-box 1.13.14，并验证上游
Windows 归档的 SHA-256。

未使用 Authenticode 签名的开源构建可能触发 Microsoft Defender SmartScreen。
用户应只从项目 Release 下载并先核对 SHA-256。若需要普通用户无警告安装，
发布者需要购买代码签名证书并对 Release 产物签名。

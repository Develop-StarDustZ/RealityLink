# RealityLink for macOS

原生 SwiftUI 客户端源码，支持 macOS 13 及以上系统。

支持 VLESS、VMess、Trojan、Shadowsocks、Hysteria2 和 TUIC；可以导入单个分享链接、
`sub://` 以及 HTTP(S) 混合订阅。配置由 sing-box 1.13.14 执行并在连接前校验。

## 开发

从仓库根目录运行：

```bash
swift test --package-path macOS
swift run --package-path macOS
```

生成本地 `.app`：

```bash
./Scripts/build-app.sh
```

生成 ARM64、Intel x64 和 Universal 三种发布包：

```bash
./Scripts/release.sh
```

发布成品写入仓库根目录的 `dist/macos/`，Swift 构建缓存留在
`macOS/.build/`，两者都不会提交到 Git。

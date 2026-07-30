# RealityLink

<p align="center">
  <img src="Assets/AppIcon-source.png" width="128" height="128" alt="RealityLink star logo">
</p>

**Language: [English](README.md) · [中文](README.zh.md)**

A free, open-source desktop client for macOS, Windows, and Linux. Manage nodes and subscriptions, switch with one click, and route traffic through system proxy or global TUN. The data plane is the proven `sing-box` core.

## 1. Download

| OS | Device | Download 0.2.0 |
| --- | --- | --- |
| macOS | Apple Silicon (M1–M4) | [ARM64 ZIP](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-macOS-arm64.zip) |
| macOS | Intel Mac | [Intel ZIP](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-macOS-x64.zip) |
| macOS | Unsure | [Universal ZIP](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-macOS-universal.zip) |
| Windows | Most PCs | [Installer](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-windows-x64-setup.exe) · [Portable](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-windows-x64-portable.exe) |
| Windows | ARM devices | [Installer](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-windows-arm64-setup.exe) · [Portable](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-windows-arm64-portable.exe) |
| Linux | Intel/AMD | [AppImage](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-linux-x86_64.AppImage) · [DEB](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-linux-amd64.deb) |
| Linux | ARM64 | [AppImage](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-linux-arm64.AppImage) · [DEB](https://github.com/Develop-StarDustZ/RealityLink/releases/download/v0.2.0/RealityLink-0.2.0-linux-arm64.deb) |

## 2. Install

- **macOS**: Unzip, drag `RealityLink.app` to **Applications**. First launch: Control-click → **Open** → confirm. If blocked, open **System Settings → Privacy & Security** → **Open Anyway**.
- **Windows**: Double-click the installer, or the portable build (don't move it while connected). If SmartScreen warns, choose **More info → Run anyway**.
- **Linux**: Double-click the AppImage (or **Run** if asked). For DEB, double-click to open in your Software Center and follow the password prompt.

## 3. First use

1. Click **Import link** and paste a node, `sub://`, or HTTP(S) subscription.
2. Pick a mode: **System proxy** or **Global TUN**.
3. Select a node and click **Connect**. Enter the admin password when asked.
4. Remove server addresses, UUIDs, and passwords before sharing logs.

## 4. Features

- VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, plus subscription URLs
- Menu-bar quick connect / disconnect, live logs, persistent config
- macOS uses native SwiftUI; Linux / Windows are Electron-based
- Calls `sing-box check` before start to avoid invalid config touching the network

## 5. Platforms

- **macOS 13+** SwiftUI — see [`macOS/`](macOS/)
- **Linux** Ubuntu / Debian desktop — see [`Linux/`](Linux/)
- **Windows 10/11** — see [`Windows/`](Windows/)

## 6. Help

- Bugs and feature requests: [Issues](https://github.com/Develop-StarDustZ/RealityLink/issues)
- Security: **Security → Report a vulnerability** (do not post publicly)
- Email: [develop@stardustz.com](mailto:develop@stardustz.com)
- When reporting, include version, OS, CPU type, and what you did vs. what happened. **Never share real node links or credentials.**

## Development

### Build from source

```bash
git clone https://github.com/Develop-StarDustZ/RealityLink.git
cd RealityLink

# macOS — SwiftUI, requires macOS 13 + Xcode 15 / Swift 5.10
swift run --package-path macOS          # run from source
./Scripts/build-app.sh                  # build a runnable .app

# Linux / Windows — Electron, requires Node 22
cd Linux && npm ci && npm test
cd Windows && npm ci && npm test
```

### Release build

`Scripts/release.sh` pins sing-box 1.13.14, downloads upstream archives, verifies
SHA-256, and emits signed ZIPs and SHA-256 files into `dist/`.

```bash
./Scripts/release.sh
(cd dist/macos/arm64 && shasum -a 256 -c RealityLink-0.2.0-macOS-arm64.zip.sha256)
```

Pushing a tag such as `v0.2.0` triggers `.github/workflows/release.yml`, which
rebuilds all three platforms on CI and publishes a GitHub Release.

```bash
git tag -a v0.2.0 -m "RealityLink 0.2.0"
git push origin v0.2.0
```

### Build a release on a clean repo

```bash
git init -b main
git add .
git commit -m "Release RealityLink 0.2.0"
git remote add origin git@github.com:Develop-StarDustZ/RealityLink.git
git push -u origin main
```

Create the GitHub repo **empty** first — do not pre-add README / LICENSE /
.gitignore, or the first push will conflict.

## Notes

- Use only with servers you own or are authorized to use, and follow applicable laws and network-service terms.
- On macOS, an unsigned build is blocked by Gatekeeper the first time. The README's install steps explain how to open it.
- On Windows, builds without a commercial Authenticode certificate trigger SmartScreen.
- Each platform's first TUN connection asks for admin permission: macOS authorization, Linux `pkexec`, Windows UAC. Test on real hardware before shipping.

## Repository layout

```text
RealityLink/
├── macOS/      SwiftUI source, resources, tests
├── Linux/      Electron client
├── Windows/    Electron client
├── Assets/     Brand source assets
├── Scripts/    Cross-platform build / release scripts
├── README.md   This file (English, default)
├── README.zh.md  Chinese version
└── dist/       Local release output (gitignored)
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). The bundled `sing-box` is also
GPL-3.0-or-later; its copyright and pinned version are listed in the third-party
notices.

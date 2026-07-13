# Mihomo for macOS

Mihomo 是一个 SwiftUI-first 的 macOS 原生 mihomo 客户端，目标是在保持桌面端信息密度的同时，把日常代理操作、配置管理、网络恢复和维护工具清晰分层。

当前版本：`v1.10.0`

## v1.10.0 更新重点

- 核心控制通道改为应用自动管理，Profile、JS Transform 与 YAML 覆写不再破坏客户端和核心之间的连接。
- 设置页移除“本机 Controller”，改为用户语义明确的“远程管理”；只有跨设备管理时才显示监听地址、管理端口和访问密钥。
- 远程管理与局域网代理权限拆分，开启远程管理时自动切换监听地址并生成访问密钥。
- Sniffer 统一命名为“域名嗅探”，迁入网络工作区并提供概览快速开关、独立详情页与 Profile 接管选项。
- 域名嗅探支持 HTTP、TLS、QUIC 端口、识别方式、强制/跳过域名以及来源/目标 IP 或 CIDR 例外。
- 补齐设置 schema v5 迁移、Runtime Config 优先级说明、真实 Settings Window/AX QA 与 110 项自动化测试。

完整变更见 [v1.10.0 Release Notes](docs/releases/v1.10.0.md)，架构与开发约定见 [开发文档](Mihomo-macOS-development-report.md)。

## 功能范围

- 原生侧栏、Toolbar、Settings window 与 Menu Bar Extra。
- Core、系统代理、TUN、系统 DNS 的独立控制、状态检测、快照和恢复。
- 本地/远程 Profile、自动刷新、覆写片段、运行时预览与 `mihomo -t` 校验。
- GUI 策略组和规则编辑，离线策略预览，节点切换与延迟测试。
- Proxy/Rule Provider、本地规则集、Geo 数据更新、历史和回滚。
- 应用托管的核心 HTTP/WebSocket 控制通道，提供最近请求、活动连接、DNS 观测、时间窗口流量和日志实时状态，并支持断线恢复与 polling fallback。
- XPC Helper 执行需要权限的核心、代理、DNS、TUN 与 LaunchDaemon 操作。
- 本地/WebDAV/Gist 备份、Secret Vault、Age Profile 加密、诊断包和软件更新。

## 系统要求

- macOS 14 或更新版本。
- Swift 5.9+。
- 项目默认使用：

```bash
export DEVELOPER_DIR='/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer'
```

- 网络下载可使用：

```bash
export https_proxy=http://127.0.0.1:6152
export http_proxy=http://127.0.0.1:6152
export all_proxy=socks5://127.0.0.1:6153
```

## 构建与运行

```bash
./script/build_and_run.sh
```

脚本会停止旧进程、使用 SwiftPM 构建三个 product、生成 `dist/Mihomo.app`、签名并启动该绝对路径下的客户端。

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

若 `/Applications/Mihomo.app` 仍在运行，系统可能把旧窗口带到前台。验证时请确认侧栏版本，或直接检查：

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Mihomo.app/Contents/Info.plist
pgrep -fl '/Mihomo.app/Contents/MacOS/Mihomo'
```

## 测试与质量门禁

```bash
swift test
git diff --check
./script/maintainability_audit.sh
./script/build_and_run.sh --verify
```

当前测试集包含 110 个 XCTest，覆盖 Activity/日志展示、两色流量语义、域名嗅探配置、应用托管控制通道、多选表格键盘交互、规则参数与稳定命中计数、覆写作用域、配置质量、运行时 Store 隔离、设置迁移、Runtime Config 合并、Profile 结构编辑、Provider 更新与回滚、网络请求超时、核心实时状态恢复、Helper 路径边界、备份恢复、更新回滚、Secret Vault 和 AppKit accessibility。

网络恢复与辅助功能人工检查：

```bash
./script/network_takeover_smoke.sh
./script/network_takeover_smoke.sh --assert-clean
./script/accessibility_qa_checklist.sh
```

## 配置合并语义

最终 Runtime Config 从低到高依次合并：

```text
应用默认
  ↓ Profile 覆盖
Profile 配置
  ↓ JS Transform
JS 输出
  ↓ YAML 覆写
最终 Runtime Config
```

配置页的“字段来源”和“合并层级”应始终与此规则一致。新增设置字段时，必须同时检查 `RuntimeConfigBuilder`、`ProfileQualityAnalyzer`、设置迁移和相关测试。

有两个明确例外：

- `external-controller` 与 `secret` 始终由应用管理，确保客户端能连接自己启动的核心；远程管理设置只决定监听范围、端口和访问密钥。
- 开启“由 Mihomo 管理域名嗅探”时，最终 `sniffer` 使用网络工作区设置；关闭后才遵循 Profile/覆写中的 `sniffer`。

两项能力的用户语义与配置边界见 [核心控制与域名嗅探设计](docs/design/control-channel-and-domain-sniffing.md)。

## Release

本地发布包：

```bash
export https_proxy=http://127.0.0.1:6152
export http_proxy=http://127.0.0.1:6152
export all_proxy=socks5://127.0.0.1:6153
./script/package_release.sh 1.10.0
./script/release_smoke_test.sh 1.10.0
```

产物位于 `dist/releases/`：

- `Mihomo-1.10.0-macOS-arm64.zip`
- `Mihomo-1.10.0-update.json`
- `mihomo-update.json`
- `Mihomo-1.10.0-provenance.md`

Release 必须上传 zip 和 `mihomo-update.json`，否则应用内更新无法发现或验证新版本。manifest 使用 Ed25519 签名，私钥从 `MIHOMO_UPDATE_PRIVATE_KEY` 或 `~/.mihomo-update-signing/ed25519.private` 读取。

当前发布采用固定 ad-hoc signing identifier，未进行 Apple notarization。首次安装下载版本可能需要：

```bash
xattr -dr com.apple.quarantine /Applications/Mihomo.app
```

## 项目结构

```text
Sources/Mihomo/
  Models/       数据模型与设置 schema
  Services/     配置、网络、下载、备份、更新等纯服务
  Stores/       AppStore 与按领域拆分的协调逻辑
  Views/        SwiftUI 页面和 AppKit bridge
Sources/MihomoHelper/   特权 Helper
Sources/MihomoJSWorker/ JS Transform 隔离进程
Tests/MihomoTests/      XCTest
script/                 构建、发布、smoke 与质量门禁
```

## 安全边界

- Helper 只接受预期 app bundle/signing identifier，并验证允许访问的路径。
- 下载的 core、Age、External UI 与 Geo 数据在替换前验证 SHA-256。
- Runtime/Provider 路径禁止父目录穿越和 symlink escape。
- 普通备份默认脱敏；可迁移 Secret 使用单独的口令加密 bundle。
- 诊断导出会脱敏已知 secret、credential 和 URL query。
- 软件更新验证 manifest 签名、zip SHA-256、bundle id 和 signing identifier，并在替换失败时恢复旧 App。

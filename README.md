# Mihomo for macOS

Mihomo 是一个 SwiftUI-first 的 macOS 原生 mihomo 客户端，目标是在保持桌面端信息密度的同时，把日常代理操作、配置管理、网络恢复和维护工具清晰分层。

当前版本：`v1.18.0`

## v1.18.0 更新重点

- 规则表按分类使用更易区分的文本颜色，降低蓝紫色系类别混淆。
- 配置质量面板统一各分段内容宽度；字段来源在窄窗口下自动切换为纵向信息布局。
- 覆写概览将顶层键改为跨列摘要，完整展示更多字段，减少无效留白。

完整变更见 [v1.18.0 Release Notes](docs/releases/v1.18.0.md)。

## v1.17.0 更新重点

- 修复规则命中计数（控制器规则类型与配置规则键对齐）。
- 规则页分类筛选与更清晰的类型 / 命中展示。
- 配置与覆写编辑器保留中文 Unicode，并显示行号与行数。
- 策略 / 网络 / 高级工具 / 诊断 / 设置信息层级与文案优化。

完整变更见 [v1.17.0 Release Notes](docs/releases/v1.17.0.md)。

## v1.11.2 更新重点

- 覆写 Space 快速查看改为应用自有窗口，提供行号、语法高亮、元数据、问题列表和多选前后切换。
- 覆写页底部改为“覆写概览”，汇总行数、大小、顶层键，并定位 YAML、JavaScript 与 Sniffer 规则问题。
- 配置摘要卡填满内容宽度；配置质量问题明确标注“当前 Profile / App 设置 / 覆写 / 最终配置”来源。
- 设置改为主窗口侧栏页面，侧栏、菜单栏与 `Command-,` 使用同一导航入口。
- 延迟测试移入通用设置，保留代理节点测试 URL，并新增独立的 DIRECT 测试 URL。

完整变更见 [v1.11.2 Release Notes](docs/releases/v1.11.2.md)，架构与开发约定见 [开发文档](Mihomo-macOS-development-report.md)。

## 功能范围

- 原生侧栏、Toolbar、主窗口设置页与 Menu Bar Extra。
- Core、系统代理、TUN、系统 DNS 的独立控制、状态检测、快照和恢复。
- 本地/远程 Profile 与覆写订阅、自动刷新、运行时预览与 `mihomo -t` 校验。
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

当前测试集包含 148 个 XCTest，覆盖 Activity/日志展示、两色流量语义、Profile↔App 设置同步、覆写 YAML/JavaScript 分析、完整 Geo 默认值、域名嗅探配置、应用托管控制通道、多选表格键盘交互、规则参数与稳定命中计数、覆写作用域与远程订阅、配置质量来源、DIRECT/代理测速设置、运行时 Store 隔离、设置迁移、Runtime Config 合并、Profile 结构编辑、Provider 更新与回滚、网络请求超时、核心实时状态恢复、Helper 超时、签名部署选择、传统安装路径与 ad-hoc 更新 CDHash 固定、备份恢复、更新回滚、Secret Vault 和 AppKit accessibility。

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

当前 Profile 与 App 之间还有一条同步链：

- 启用、导入或刷新 Profile 时，Profile 中已经声明的端口、LAN、日志、DNS、TUN 和域名嗅探字段覆盖 App 中的同名值。
- 用户之后修改这些 App 设置并应用时，只把发生变化的字段同步回当前 Profile；无关设置不触碰 Profile。
- JS Transform 与 YAML 覆写只参与 Runtime Config 生成，不回写 Profile，仍保持更高运行时优先级。

唯一明确例外：

- `external-controller` 与 `secret` 始终由应用管理，确保客户端能连接自己启动的核心；远程管理设置只决定监听范围、端口和访问密钥。

相关边界见 [核心控制与域名嗅探设计](docs/design/control-channel-and-domain-sniffing.md) 与 [Profile 设置同步设计](docs/design/profile-settings-synchronization.md)。

## Release

CI / 本机 ad-hoc 验证包：

```bash
MIHOMO_ALLOW_ADHOC_RELEASE=1 RELEASE_BUILD=1 SKIP_APP_LAUNCH=1 \
  ./script/build_and_run.sh --verify
```

无 Apple Developer 账户时，可显式生成未公证的 ad-hoc GitHub Release：

```bash
MIHOMO_ALLOW_UNNOTARIZED_RELEASE=1 ./script/package_release.sh <version>
MIHOMO_ALLOW_UNNOTARIZED_RELEASE=1 ./script/release_smoke_test.sh <version>
```

该 Release 必须明确标注“未签名、未公证”。下载后如被 Gatekeeper 阻止，用户需执行 `xattr -cr /Applications/Mihomo.app`。主程序会检测签名身份；没有可用 Apple Team 时，“注册”“修复”和核心启动自愈会请求管理员授权，使用 root 所有且绑定当前 App CDHash 的传统 Helper。应用内更新仍由 Ed25519 manifest、zip SHA-256、bundle identifier 以及主 App/Helper 的精确 CDHash 共同校验。

受保护的正式发行先运行：

```bash
./script/protected_release_checklist.sh --version <version>
```

Developer ID 正式发布机必须提供 identity、Team ID、notarytool 凭据和 Ed25519 update manifest 私钥；ad-hoc 发布仍必须提供 Ed25519 私钥。产物位于 `dist/releases/`：

- `Mihomo-<version>-macOS-arm64.zip`
- `Mihomo-<version>-update.json`
- `mihomo-update.json`
- `Mihomo-<version>-provenance.md`

Release 必须上传 zip 和 `mihomo-update.json`，否则应用内更新无法发现或验证新版本。manifest 使用 Ed25519 签名，私钥从 `MIHOMO_UPDATE_PRIVATE_KEY` 或 `~/.mihomo-update-signing/ed25519.private` 读取。

应用内更新会校验 manifest Ed25519 签名、zip SHA-256、bundle id，并按 `signingMode` 校验 Developer ID TeamIdentifier 或主 App/Helper 的精确 ad-hoc CDHash；更新前等待旧 Helper 注销，更新后重新注册或重新绑定传统 Helper。

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

- Bundle 内 Helper 只接受同一 App Bundle；传统 Helper 使用 root 所有的授权文件校验 App 路径、bundle identifier 和精确签名 CDHash，并继续验证允许访问的路径。
- 下载的 core、Age 与 Geo 数据在替换前验证 SHA-256；默认 Geo 数据会自动读取上游 `.sha256sum`。
- Runtime/Provider 路径禁止父目录穿越和 symlink escape。
- 普通备份默认脱敏；可迁移 Secret 使用单独的口令加密 bundle。
- 诊断导出会脱敏已知 secret、credential 和 URL query。
- 软件更新验证 manifest 签名、zip SHA-256、bundle id，以及 Developer ID TeamIdentifier 或精确 ad-hoc CDHash，并在替换失败时恢复旧 App 与 Helper 状态。

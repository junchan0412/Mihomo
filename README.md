# Mihomo for macOS

Mihomo 是一个 SwiftUI-first 的 macOS 原生 mihomo 客户端，目标是在保持桌面端信息密度的同时，把日常代理操作、配置管理、网络恢复和维护工具清晰分层。

当前版本：`v1.25.11`

## v1.25.11 更新重点

- 菜单栏下拉窗口的 window 背景统一使用 Liquid Glass/material，与内部玻璃表面保持一致。
- 菜单栏状态图标复用 Mihomo 软件图标的三柱矢量 mark，并固定尺寸避免 template label 中只显示模式 badge。
- 修复 ad-hoc/传统 Helper 更新时误调用 `SMAppService` 注销导致的 entitlement 错误，并避免更新后强制启动重复实例。

完整变更见 [v1.25.11 Release Notes](docs/releases/v1.25.11.md)。

## v1.25.9 更新重点

- 菜单栏状态图标复用 Mihomo App 的矢量品牌 mark，运行状态、出站模式与停用状态保持清晰区分。
- 菜单栏下拉面板改用 macOS 26 Liquid Glass；相关玻璃表面共享同一 `GlassEffectContainer`，macOS 14/15 继续使用自适应 material fallback。
- 移除菜单栏整块渐变背景与重复自绘 chrome，保留系统窗口材质和原生菜单交互，减少滚动与 hover 时的视觉冲突。

完整变更见 [v1.25.9 Release Notes](docs/releases/v1.25.9.md)。

## v1.25.8 更新重点

- 修复同一 Runtime Provider 路径同时被 Profile Provider 与 Node Provider 引用时的重复刷新，批量更新现在只会处理一次目标文件。
- 修复 mihomo core 曾以 `root` 创建 Provider 文件后，后续刷新因权限不足而失败的问题；替换过程改为同目录 staging、原子 `rename` 和目录 `fsync`。
- 保持既有内容校验、备份、回滚与 HTML 错误页拒绝机制，异常响应不会覆盖当前可用资源。

完整变更见 [v1.25.8 Release Notes](docs/releases/v1.25.8.md)。

## v1.25.7 更新重点

- 全新 Mihomo App 图标：以参考图的玻璃质感为灵感，使用深色圆角底、顶部高光和蓝青到紫色的三柱信号 mark，提供 light/dark 资源与多尺寸 ICNS。
- 菜单栏图标与 App 图标统一为三柱信号 mark，保留系统 template 渲染能力，并用状态色与运行状态表达当前核心状态。
- 菜单栏下拉菜单改为半透明材质面板，增加运行状态头部、实时上传/下载速率、分组留白和 hover 行反馈，策略、配置与维护入口保持原有操作路径。

完整变更见 [v1.25.7 Release Notes](docs/releases/v1.25.7.md)。

## v1.25.6 更新重点

- 菜单栏按常用代理操作顺序重构：显示主窗口、出站模式、策略组、系统代理、TUN、终端命令、功能面板、覆写列表、资源更新、配置切换与重载配置。
- 策略组一级菜单保留当前节点和延迟；二级菜单顶部提供延迟测试，下面列出节点和对应延迟。
- “模块”改为覆写列表：按当前配置筛选，勾选状态清晰可见；核心运行时切换覆写会自动重载并立即生效。
- 对节点提供商的 TLS 证书异常与 HTML 404 返回给出安全诊断，继续拒绝不可信或非订阅内容，避免覆盖已有 Provider 文件。

完整变更见 [v1.25.6 Release Notes](docs/releases/v1.25.6.md)。

## v1.25.5 更新重点

- 节点提供商支持 Clash YAML、Base64 YAML 与常见节点 URI 订阅，并自动转换为 Mihomo 可读取的 Provider YAML。
- 订阅 URL 返回 HTML 404 或 HTTPS 证书异常时提供明确诊断，不再笼统显示“不是可解析内容”。
- 菜单栏重构为紧凑的原生层级菜单：策略组显示当前节点并提供二级节点选择；补齐客户端流量、系统代理/TUN、功能、模块、面板、配置和维护入口。
- Provider 下载与刷新保持 staging、fsync、原子替换和 SHA-256 摘要；异常内容不会覆盖现有资源。

完整变更见 [v1.25.5 Release Notes](docs/releases/v1.25.5.md)。

## v1.25.3 更新重点

- 主窗口页面切换加入渐入渐出过渡，侧边栏选择不同工作区时内容区不再瞬间替换。
- 页面过渡会尊重系统“减少动态效果”设置，开启后停用切换动画。
- 发布包继续使用既有 ad-hoc manifest 校验链，应用内更新可通过最新 manifest 发现本版本。

完整变更见 [v1.25.3 Release Notes](docs/releases/v1.25.3.md)。

## v1.25.2 更新重点

- 规则、配置、覆写、配置资源与日志列表统一为 SwiftUI 内容行，使用同色背景、稳定分隔和固定右侧状态/操作列，取消相邻行的交替底色。
- 资源页明确拆分为“配置资源 / 节点提供商 / 规则”，Proxy 与 Rule Provider 不再混在同一列表；节点提供商的时间、刷新和更多操作列保持统一横坐标。
- 侧边栏改用无动画的稳定导航行，并把高频连接/运行状态移到独立 Footer，修复切页时图标闪烁。
- 页面进入时不再同步重解析整份配置，减少切换工作区时的主线程卡顿；多选列表支持 Command/Shift 选择。
- `swift test`：231/231 通过；维护性审计覆盖 235 个 Swift 文件，0 warning、0 over-max。

完整变更见 [v1.25.2 Release Notes](docs/releases/v1.25.2.md)。

## v1.25.1 更新重点

- Activity 搜索加入 200ms debounce、稳定选区 reconciliation 和有界并发批量关闭，降低高频列表刷新与批量操作压力。
- 网络接管状态新增“未知”和最近检查时间；系统代理、DNS、TUN 操作互斥，TUN 路由恢复失败默认 fail-closed，并提供明确的强制关闭确认。
- Provider 下载采用 staging + fsync + 原子替换，拒绝 HTML/空映射/无有效条目内容，并记录 SHA-256 校验摘要。
- 批量 Provider/Profile 刷新支持取消、去重和旧任务 generation 保护；设置保存前校验端口、并发、超时、URL、DNS 与 IP/CIDR。
- 更新器支持受信任 HTTPS manifest 镜像并自动回退 GitHub，manifest Ed25519 签名链保持不变；网络页面、状态派生和 manifest 校验按职责拆分。
- 删除节点提供商时同步移除关联 Profile 中的 `proxy-providers` 条目，并保留配置注释与换行格式。
- 主窗口侧栏、页面背景、Toolbar 与 cards 统一语义底色，减少透明材质叠加造成的视觉色差。
- 规则、配置、覆写、资源与日志列表统一使用稳定单色背景，去除相邻行色差；资源页拆分为“配置资源 / 节点提供商 / 规则”，并统一右侧操作列横坐标。
- 页面切换移除整页重建、全局 transition 与 selection 动画，减少侧栏图标闪烁和切换卡顿。
- `swift test`：229/229 通过；维护性审计覆盖 233 个 Swift 文件，0 warning、0 over-max。

完整变更见 [v1.25.1 Release Notes](docs/releases/v1.25.1.md)。

## v1.24.1 更新重点

- 软件更新窗口显示真实下载字节数、总量、速率和可取消状态，并将检查、下载、校验、准备安装与重启安装统一为结构化阶段。
- 更新包完成 SHA-256、manifest 签名、bundle identifier 及 App/Helper 签名校验后，才显示“重启安装”；取消或失败会清理临时文件并保留当前版本。
- 设置、菜单栏和命令面板共用同一套更新状态与操作入口，避免重复触发检查、下载或安装。
- 新增下载进度模型与阶段状态回归测试；`swift test`、构建启动、ad-hoc bundle 校验和维护性审计均通过。

完整变更见 [v1.24.1 Release Notes](docs/releases/v1.24.1.md)。

## v1.24.0 更新重点

- 配置资源的全部更新、更新所选与回滚所选统一采用有界并发队列，遵守资源页的并发设置；结果按选择顺序归并，批量历史只落盘一次。
- 资源批量操作期间会禁用重复入口，避免多次点击造成同一文件并发更新；全量资源更新去除一次多余的配置重解析。
- 远程覆写的所选刷新与全部刷新接入订阅刷新并发设置，所有结果完成后一次提交覆写存储，并防止重复刷新。
- 新增并发上限、输出顺序和不可刷新资源过滤的回归测试；维护性审计扩展至 225 个 Swift 文件且保持 0 warning、0 over-max。

完整变更见 [v1.24.0 Release Notes](docs/releases/v1.24.0.md)。

## v1.23.0 更新重点

- 连接、DNS、流量、日志、概览时间轴及主要管理列表统一空状态与筛选后的 selection reconciliation，避免显示已被筛掉的详情或创建空 AppKit 表格。
- Profile、覆写与 Provider 的远程来源统一隐藏 URL 凭据、query、fragment 与高熵 path token，降低界面、截图和 accessibility tree 泄露风险。
- Activity 连接刷新改由 revision 驱动；日志展示按批次缓存；流量窗口单次遍历聚合；概览时间轴使用二分定位与单次分桶。
- 策略、资源、规则、Profile 与覆写页面从单个 presentation snapshot 派生列表、计数、选区和表格配置，减少同轮渲染中的重复扫描。
- 覆写刷新和添加收进紧凑菜单，窄窗口下保留导出与删除入口；命令面板快捷键冲突已修正。
- `AppStore`、AppKit table、Controller polling、Profile 刷新、配置质量、资源、规则与 Activity 等大型实现按职责拆分，并删除迁移后遗留代码。
- 当前 221 个 Swift 文件全部不超过 350 行；维护性审计为 0 个 warning、0 个 over-max 文件，最大文件为 347 行。
- 211 个 XCTest 覆盖新增的展示快照、空状态、选区、脱敏、性能派生状态与职责拆分回归。

完整变更见 [v1.23.0 Release Notes](docs/releases/v1.23.0.md)。

## v1.22.1 更新重点

- 修复覆写版本历史把 JSON 快照误当 YAML 顶层映射解析而显示“无字段变更”的问题；现在会准确显示覆写的新增、删除、内容、状态、类型、作用范围与来源变化。
- 命令面板改用稳定命令 ID，并支持在搜索框内使用上/下箭头选择、Enter 执行、Esc 关闭；实机验证可正常跳转页面。

完整变更见 [v1.22.1 Release Notes](docs/releases/v1.22.1.md)。

## v1.22.0 更新重点

- 主侧栏使用稳定的页面背景 token，避免原生侧栏材质在不同窗口状态下与内容区产生明显色差。
- 菜单栏支持最近切换、策略组收藏、全量/单组测速；每个节点显示延迟或不可用状态，策略详情保留测速历史、失败原因和最近时间。
- 新增 `Command-Shift-P` 命令面板，集中处理跳转、切配置、测速、资源刷新和网络开关。
- 连接详情新增“进程 → 域名 → 规则 → 策略链 → 出站”的路由解释；资源页支持导出所选文件；诊断导出升级为脱敏运行健康报告。
- Profile 与覆写编辑器支持版本快照、顶层字段差异和恢复；开启 Profile 加密后版本内容同样受 Age 保护。

完整变更见 [v1.22.0 Release Notes](docs/releases/v1.22.0.md)。

## v1.21.1 更新重点

- 修复同名节点 Provider 会以“独立项 + Profile 导入项”重复出现的问题；Profile 定义会自动合并并保留用户分组和标签。
- 删除或关联 Provider 的预览会先自动清理已有同名重复记录，展示可确认的记录变化，不再出现只有“取消”可用的阻断弹窗。

完整变更见 [v1.21.1 Release Notes](docs/releases/v1.21.1.md)。

## v1.21.0 更新重点

- 节点 Provider 写回 Profile 时保留 YAML 注释、字段顺序、未知字段与既有缩进；行内注释的空白也不会被改写。
- 同名 Provider 以来源 Profile 与名称共同识别；冲突会在写入前展示，批量导入、关联切换和编辑均支持预览与单步撤销。
- 远程 Profile 批量刷新遇到需保留的 Provider 时进入逐项确认队列，避免遗漏后续刷新结果。
- 侧栏列表背景与详情页统一；配置质量内容在切换时保持稳定宽度，字段来源可滚动查看；覆写概览将顶层键改为全宽摘要，收回无效右侧留白。

完整变更见 [v1.21.0 Release Notes](docs/releases/v1.21.0.md)，竞品对比与后续清单见[桌面客户端差距分析](docs/design/desktop-client-gap-analysis.md)。

## v1.20.0 更新重点

- 策略页按可用性与延迟自动排序，并提供未测速、快速、一般、较慢、不可用筛选；菜单栏支持节点/策略组搜索、按组测速和节点延迟展示。
- 节点提供商支持批量导入、分组与标签。导入 Profile 会提取已有 `proxy-providers`；新增或关联节点提供商会同步回关联 Profile。
- 远程刷新 Profile 时合并上一个版本中远端遗漏的 `proxy-providers`，防止已关联 Provider 被刷新置空。
- 侧栏支持可折叠分区、右键快捷收藏，并与内容区使用一致的页面背景。

完整变更见 [v1.20.0 Release Notes](docs/releases/v1.20.0.md)，竞品对比与后续清单见[桌面客户端差距分析](docs/design/desktop-client-gap-analysis.md)。

## v1.19.0 更新重点

- 主窗口侧栏改用与内容区一致的页面背景，消除系统侧栏底色带来的视觉割裂。
- 菜单栏升级为策略组工作面板：可展开查看每个节点、显示实时延迟、单组测速或全量测速，并保留核心、系统代理、TUN 与常用操作。
- 节点提供商从配置资源中独立保存；可添加订阅并为每个 Profile 复选接入。

完整变更见 [v1.19.0 Release Notes](docs/releases/v1.19.0.md)。

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
- 独立节点提供商、Proxy/Rule Provider、本地规则集、Geo 数据更新、历史和回滚。
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

当前测试集包含 225 个 XCTest，覆盖 Activity/日志展示与缓存筛选、多窗口流量聚合、筛选结果 selection reconciliation、远程来源 URL 参数与 path token 脱敏、概览时间轴空状态、分桶与两色流量语义、资源、规则、策略、Profile 与覆写列表 presentation snapshot、规则编辑 draft 规范化、覆写筛选/选区/表高边界、资源搜索/未就绪/无数据空状态、Profile↔App 设置同步、AppStore 派生状态与相同值发布抑制、覆写 YAML/JavaScript 分析、完整 Geo 默认值、域名嗅探配置、应用托管控制通道、多选表格键盘交互、规则参数与稳定命中计数、覆写作用域与远程订阅、配置质量来源、DIRECT/代理测速设置、节点提供商与 Profile 双向同步、Provider 更新与回滚与内容校验、批量取消、设置输入校验、运行时 Store 隔离、设置迁移、Runtime Config 合并、Profile 结构编辑、网络请求超时、核心实时状态恢复、Helper 超时、签名部署选择、传统安装路径与 ad-hoc 更新 CDHash 固定、备份恢复、更新回滚、Secret Vault 和 AppKit accessibility。

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
覆写输出
  ↓ 独立节点提供商注入
最终 Runtime Config
```

独立节点提供商保存在 `node-providers.json`，可按 Profile 复选。导入、刷新 Profile 时会提取其 `proxy-providers` 并建立关联；从资源页新增、编辑或关联 Provider 时会回写关联 Profile 的同名定义。若 Profile 已有同名 Provider，运行时不重复注入，而是以 Profile 定义为来源。远程 Profile 刷新缺少旧 Provider 时，旧定义会保留，避免把已关联 Provider 置空。配置页的“字段来源”和“合并层级”应始终与此规则一致。新增设置字段时，必须同时检查 `RuntimeConfigBuilder`、`ProfileQualityAnalyzer`、设置迁移和相关测试。

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

# Mihomo macOS 原生客户端开发报告（第二版）

生成日期：2026-07-06
报告定位：基于当前仓库状态，对第一版开发报告进行更新。第二版重点不再是单纯功能候选，而是梳理当前已实现能力、新增功能项、仍需硬化的系统边界，以及后续可持续优化路线。

## 1. 当前结论

当前项目已经从早期规划推进到接近 1.0 MVP 的 macOS 原生 mihomo 客户端。主 App 使用 SwiftUI 为主、AppKit 为辅的架构，已经形成概览、活动、策略、配置、规则、资源、高级、日志、诊断、设置等完整工作台；特权操作已从主 App 收口到 XPC Helper；配置生成、资源更新、Profile 编辑、备份同步、应用内更新等高级能力也已落地。

但当前项目还不应直接定义为“稳定公开发行版”。它更接近“可长期自用和小范围测试的 Beta 前状态”。核心原因不是功能不足，而是以下几个系统性硬化点仍需要继续收敛：

- 网络接管状态仍需要更严格的状态机，尤其是系统代理、系统 DNS、TUN 快照之间的边界。
- Helper 已承担高权限操作，但授权校验、操作审计、失败回滚还需要面向真实分发继续硬化。
- 项目功能面已经较宽，后续重点应从“继续横向加功能”转向测试、可观测性、迁移兼容、发布流程和用户可理解性。
- 当前未看到独立测试目录，核心配置合并、更新校验、备份恢复、Helper 客户端协议等模块需要补充自动化验证。

## 2. 当前工程状态

| 维度 | 当前状态 | 依据 |
| --- | --- | --- |
| 工程组织 | SwiftPM 工程，包含主 App、Helper、Shared 协议三个 target | `Package.swift` |
| 平台要求 | macOS 14+，Swift 5.9+ | `Package.swift`、`README.md` |
| UI 技术 | SwiftUI 主体，AppKit 承接高密度表格、日志文本视图、窗口细节 | `Sources/Mihomo/Views` |
| 主界面 | Sidebar 分区覆盖概览、活动、策略、配置、规则、资源、高级、日志、诊断、设置 | `AppSection`、`RootView` |
| Controller 能力 | 封装版本、模式、策略组、连接、流量、Provider、延迟测试等 API | `MihomoControllerClient.swift`、`AppStore.swift` |
| 特权能力 | XPC Helper 执行 core 启停、配置校验、系统代理、系统 DNS、TUN 快照、LaunchDaemon 管理 | `MihomoHelper`、`HelperClient.swift` |
| 配置生成 | 使用 Yams 结构化合并 YAML，清理 App 管理键，支持 YAML/JS 覆写、禁用规则、候选配置与回滚 | `RuntimeConfigBuilder.swift`、`ProfileStore.swift` |
| 发布链路 | release 脚本、固定 ad-hoc identifier、Ed25519 manifest 签名、GitHub Latest Release 更新入口 | `script/*`、`SoftwareUpdateManager.swift` |
| 本地数据 | App Support 保存设置、Profile、runtime、Core、Geo、External UI、Backups、Tools；日志进入 `~/Library/Logs/Mihomo` | `AppPaths.swift` |

## 3. 第二版识别的新增功能项

以下功能已经在当前代码中具备入口或主要实现，属于第一版规划后继续补齐的新能力。

### 3.1 核心与运行时

| 功能项 | 当前状态 | 说明 |
| --- | --- | --- |
| 三种 core 来源 | 已实现 | 支持托管远程、随包内置、本地外部，设置页作为统一入口。 |
| 托管 core 下载 | 已实现 | 从配置 URL 下载到 App Support 的 Core 目录，作为优先 core 来源。 |
| release 包内置 core | 已实现 | 构建脚本可准备并打包 `Contents/Resources/Core/mihomo`。 |
| 启动前 dry-run | 已实现 | Helper 通过 `mihomo -t` 校验 runtime config 后再启动。 |
| runtime 候选配置与回滚 | 已实现 | 生成 `config.candidate.yaml`，启动失败时恢复上一份 runtime 配置。 |
| 核心异常重启 | 已实现 | 支持异常退出后按次数上限自动恢复。 |
| LaunchDaemon 托管 core | 已实现 | 支持安装、卸载、启动、停止核心 LaunchDaemon。 |

### 3.2 Helper、权限与网络接管

| 功能项 | 当前状态 | 说明 |
| --- | --- | --- |
| XPC Helper | 已实现 | 主 App 通过 `dev.codex.Mihomo.Helper` 调用高权限能力。 |
| Helper 注册、卸载、修复 | 已实现 | 高级页和诊断页提供注册、审计、修复入口。 |
| Helper 授权检查 | 已增强 | Helper 校验调用方来自 Mihomo App bundle，检查签名 identifier，并通过 SecStaticCode requirement 绑定当前 ad-hoc bundle identifier；未来 Developer ID 可扩展 Team ID / designated requirement。 |
| 系统代理设置与恢复 | 已实现 | Helper 通过 `networksetup` 设置 HTTP/HTTPS/SOCKS 代理并恢复快照。 |
| 系统 DNS 临时设置 | 已实现 | 核心启动时可临时写入系统 DNS，停止或退出时恢复。 |
| TUN 快照与回滚 | 已实现 | 捕获网络服务 DNS 基线、IPv4/IPv6 路由、默认路由，支持停止或手动回滚；当前回滚路径只恢复 DNS 与路由，不恢复系统代理开关。 |
| Helper 审计 | 已实现 | 检查 bundle 布局、plist、签名 identifier、SMAppService 状态、公证说明、root 可达性。 |
| 网络接管状态机 | v1.1 已实现 | 概览和诊断页显示系统代理、系统 DNS、TUN 的用户期望、系统实际、最近 Helper 操作和恢复动作。 |
| 网络修复中心 | v1.1 已实现 | 诊断页集中提供恢复代理、恢复 DNS、恢复 TUN 路由和清理快照。 |

### 3.3 Profile 与配置维护

| 功能项 | 当前状态 | 说明 |
| --- | --- | --- |
| 本地、远程、拖入、深链导入 | 已实现 | 支持本地 YAML、远程订阅、文件导入、`mihomo://` 导入。 |
| 远程订阅证书指纹校验 | 已实现 | 首次记录 HTTPS 证书 SHA-256，刷新时校验。 |
| 订阅自动刷新队列 | 已实现 | 支持刷新间隔、最大并发、失败状态和通知。 |
| Profile 存储目录迁移 | 已实现 | 可修改 Profile 存储路径并迁移已有文件。 |
| Profile 统计摘要 | 已实现 | 默认展示规则、策略组、节点、Provider、行数、大小等统计。 |
| 独立 Profile 编辑窗口 | 已实现 | 编辑器与主配置列表分离，减少主界面拥挤。 |
| 结构化策略组编辑 | 已实现 | 可新增、修改、删除 `proxy-groups`。 |
| 删除策略组引用处理 | 已实现 | 删除被规则引用的策略组时，可替换目标或删除引用规则。 |
| 结构化规则编辑 | 已实现 | 可新增、修改、删除 Profile 中的 `rules`。 |
| Age Profile 加密 | 已实现基础链路 | 可安装 `age` 工具、生成 identity，并透明加解密本地 Profile YAML。 |

### 3.4 规则、策略、活动与日志

| 功能项 | 当前状态 | 说明 |
| --- | --- | --- |
| Surge 风格规则表 | 已实现 | ID、类型、值、策略、使用计数、注释列，支持搜索与编辑。 |
| 禁用规则持久化 | 已实现 | 禁用规则在 runtime config 生成时被过滤。 |
| 规则命中统计 | 已实现基础版 | 通过 Controller 连接信息回填命中数据。 |
| 策略组与节点表格 | 已实现 | 支持搜索、排序、节点选择、状态展示。 |
| 延迟测试 | 已实现并修复内置出站 | 支持单节点、单组、全部节点，并可配置并发和测试 URL；v1.0.4 起 DIRECT 使用 App 侧直连 URLSession 兜底测速，REJECT 作为不可测速出站跳过，不再污染失败统计。 |
| 连接列表与 Inspector | 已实现 | 支持连接过滤、分组、关闭单连接、关闭全部连接和详情窗口。 |
| 实时流量采样 | 已实现 | 概览和活动页可显示上下行速率与图表。 |
| 日志过滤、暂停、落盘与轮转 | 已实现 | 支持暂停、缓冲、保留天数、单文件大小和 App/Core 分离日志。 |

### 3.5 资源、备份、更新与分发

| 功能项 | 当前状态 | 说明 |
| --- | --- | --- |
| Rule/Proxy Provider 本地解析 | 已实现 | 从 Profile YAML 解析 Provider、引用数、URL、path、interval 等信息。 |
| Controller Provider 更新 | 已实现 | core 运行时可通过 Controller 请求更新 Provider。 |
| Provider 直接下载更新 | 已实现 | 不依赖 core 运行，可按本地配置 URL 下载到 runtime provider path。 |
| 一键更新外部资源 | 已实现 | 同时更新 Provider 和 Geo 数据。 |
| GeoIP/GeoSite 更新与同步 | 已实现 | 启动、dry-run、LaunchDaemon 安装前同步到 runtime，并在 Geo 失败后重试。 |
| External UI 管理 | 已实现 | 支持下载 zashboard/metacubexd 类 zip，并写入 runtime config。 |
| 本地 zip 备份恢复 | 已实现 | 可备份设置、Profile、片段、禁用规则等状态。 |
| WebDAV 备份恢复 | 已实现 | 支持上传和下载恢复。 |
| Gist 同步恢复 | 已实现 | 使用 JSON payload 同步设置、Profile、片段、禁用规则。 |
| Local secret vault | 已实现 | Controller/WebDAV/Gist secret 不再写入 `settings.json` 明文。 |
| Ed25519 更新 manifest | 已实现 | 应用内更新先验签 manifest，再校验 SHA-256、bundle id、签名 identifier。 |
| GitHub Release 更新入口 | 已实现 | 设置页、菜单栏、App 菜单可检查 GitHub Latest Release。 |

## 4. 功能完成度审计

| 范围 | 完成度 | 当前判断 |
| --- | --- | --- |
| P0 基础 MVP | 高 | 核心启停、Profile、系统代理、TUN、策略、活动、日志、诊断、菜单栏均已具备。 |
| P1 强烈建议项 | 高 | 订阅刷新、用量信息、配置预览、规则/Provider、Geo、登录项、轻量模式等均已落地。 |
| P2 高级项 | 中高 | 证书 pinning、Age 加密、WebDAV/Gist、外部 UI、自动系统 DNS、远程 API 已实现；仍需安全和体验硬化。 |
| P3 后置项 | 低到中 | JS 覆写已提前实现；Sub-Store、浮动窗口、快捷键、复杂主题、自定义托盘图标仍后置。 |
| 分发与更新 | 中 | 已有无 Developer ID 的固定 ad-hoc 分发路径和签名 manifest，但未公证，仍需真实 release 验证。 |
| 自动化测试 | 低 | 当前仓库未见独立 Tests 目录，核心逻辑主要依赖手动验证和运行时诊断。 |

## 5. 当前主要风险与不一致点

| 风险 | 影响 | 建议处理 |
| --- | --- | --- |
| 网络接管快照已开始拆分，但状态机还不够清晰 | 代码已有独立 `system-proxy-snapshot.json`、`system-dns-snapshot.json`、`tun-recovery-snapshot.json`，但 UI 仍主要显示用户侧开关，不一定能解释系统实际状态 | 继续把代理、DNS、TUN 的捕获、恢复、清理动作做成显式状态机和可审计事务。 |
| TUN、系统 DNS、系统代理的用户心智仍易混淆 | 用户同时开启 TUN 和系统代理时，仍可能误解“为什么恢复 DNS/路由会影响网络状态” | 在概览和诊断页增加互斥提示、实际系统状态检测和恢复动作说明。 |
| Helper 授权仍是本地分发友好版 | ad-hoc 场景下可用，但不是最终公开发行强度 | 引入 audit token / SecCode requirement 校验；Developer ID 后增加 Team ID 和 designated requirement。 |
| JS 覆写安全边界偏弱 | JavaScriptCore 可修改配置文本，但沙盒和资源限制不充分 | 默认继续关闭；增加执行超时、内存限制、API 白名单和明显风险提示。 |
| 更新安装脚本仍需真实回滚验证 | 应用替换涉及退出、移动、签名校验、失败恢复 | 建立 release smoke test，覆盖损坏 zip、签名不匹配、版本不匹配、回滚失败。 |
| Secret vault 可用性与可迁移性冲突 | 当前本机派生密钥适合本机使用，但跨机器恢复 secret 不方便 | 备份恢复时提供 secret 不同步、手动输入、用户口令二次加密三种模式。 |
| 配置 schema 校验不足 | 结构化编辑可能写入 mihomo 不接受的组合 | 为 rule、provider、dns、sniffer、tun 增加 schema 级校验和 UI 预警。 |
| 缺少自动化测试 | 功能越多，手动回归成本越高 | 优先补单元测试和 Helper/Controller mock 集成测试。 |

## 6. 可持续优化路线

### 6.1 v1.1 网络接管与 Helper 硬化

目标：让系统代理、系统 DNS、TUN 的状态变化可解释、可恢复、可测试。

| 优先级 | 优化项 | 验收标准 |
| --- | --- | --- |
| P0 | 完成网络接管状态机 | 系统代理、系统 DNS、TUN 均显示“用户期望状态、系统实际状态、最近一次 Helper 操作、可执行恢复动作”。 |
| P0 | Helper 操作事务 | set/restore 失败时返回已完成步骤和回滚建议，不只返回 shell 错误。 |
| P1 | Helper 授权升级 | 使用 audit token / SecCode 校验调用方，准备 Developer ID requirement 路径。 |
| P1 | 网络修复中心 | 诊断页集中提供恢复代理、恢复 DNS、恢复 TUN 路由、清理快照四个明确动作。 |

v1.1.0 完成状态：

| 优化项 | 完成状态 | 主要落点 |
| --- | --- | --- |
| 网络接管状态机 | 已实现 | `NetworkTakeoverState` 覆盖系统代理、系统 DNS、TUN；`AppStore.refreshNetworkTakeoverStates()` 读取系统实际代理/DNS、快照和 TUN 路由差异；概览卡片和诊断结果展示“用户期望、系统实际、最近 Helper 操作、恢复动作”。 |
| Helper 操作事务 | 已实现基础事务 | Helper 的核心启停、代理、DNS、TUN 操作返回 `transactionSteps` 和 `rollbackSuggestion`；App 记录最近 Helper 操作并展示到网络接管状态。 |
| Helper 授权升级 | 已增强 | Helper listener 保留 bundle 路径与 signing identifier 检查，并新增 `SecStaticCode` requirement 校验；当前无 Developer ID，requirement 绑定 ad-hoc bundle identifier，后续可扩展 Team ID。 |
| 网络修复中心 | 已实现 | 诊断页新增网络修复中心，集中执行恢复代理、恢复 DNS、恢复 TUN 路由、清理快照，并可刷新三类接管状态。 |

### 6.2 v1.2 配置质量与可维护性

目标：降低订阅质量、覆写片段和结构化编辑带来的配置失败概率。

| 优先级 | 优化项 | 验收标准 |
| --- | --- | --- |
| P0 | mihomo rule schema 校验 | 新增/编辑规则时能发现字段缺失、目标策略不存在、Provider 类型不匹配。 |
| P0 | Runtime Config Inspector | 展示最终生效的端口、DNS、TUN、Provider、规则数量和来源。 |
| P1 | 覆写片段 diff 分层 | 能区分 Profile 原文、YAML 片段、JS transform、App overlay 各自造成的变化。 |
| P1 | 配置迁移器 | 设置结构变更时有版本号、迁移日志和失败回滚。 |
| P2 | Profile 健康评分 | 对订阅过期、Provider URL 不可达、规则引用缺失、节点为空给出警告。 |

v1.2.0 完成状态：

| 优化项 | 完成状态 | 主要落点 |
| --- | --- | --- |
| mihomo rule schema 校验 | 已实现 | 结构化规则编辑保存前检查类型、payload、目标策略、RULE-SET Provider 引用和 CIDR 前缀；错误阻断保存，警告保存后提示。 |
| Runtime Config Inspector | 已实现 | 配置页新增质量 Inspector，展示最终 mixed/socks/controller、DNS、TUN、Provider、规则和策略组数量及来源说明。 |
| 覆写片段 diff 分层 | 已实现 | `ProfileQualityAnalyzer` 区分 Profile 原文、JS Transform、YAML 片段、App overlay 四层变化摘要。 |
| 配置迁移器 | 已实现基础版本 | `AppSettings.settingsSchemaVersion` 升级到 v2；启动时迁移旧设置，保存迁移日志，失败回滚内存设置。 |
| Profile 健康评分 | 已实现 | 对订阅过期、URL 无效、节点为空、规则为空、Provider 来源缺失、本地 Provider 文件不存在、规则引用缺失给出扣分和告警。 |

### 6.3 v1.3 发布、测试与回归体系

目标：让项目从“能打包”变成“可持续发版”。

| 优先级 | 优化项 | 验收标准 |
| --- | --- | --- |
| P0 | 单元测试 | 覆盖 `RuntimeConfigBuilder`、`ProfileYAMLStructureEditor`、`SoftwareUpdateManager`、`LocalSecretVault`。 |
| P0 | Mock Controller 集成测试 | 无需真实 core 即可验证策略、连接、Provider、规则命中刷新逻辑。 |
| P1 | Mock Helper 集成测试 | 验证 AppStore 在 Helper 成功、失败、部分失败时的状态变化。 |
| P1 | release smoke test | 自动验证 zip、manifest、Ed25519 签名、SHA-256、bundle id、signing identifier。 |
| P2 | 许可证与 SBOM | 对内置 mihomo、Yams、age、外部 UI 等产物生成许可证清单。 |

### 6.4 v1.4 体验与专业工具打磨

目标：在不继续堆叠复杂功能的前提下，让日常使用更接近成熟网络工具。

| 优先级 | 优化项 | 验收标准 |
| --- | --- | --- |
| P0 | TUN / 系统代理 / 系统 DNS 解释与互斥提示 | 用户同时开启 TUN 和系统代理时，App 明确提示冗余和可能的恢复行为。 |
| P1 | 诊断包导出 | 一键导出脱敏设置、runtime 摘要、日志片段、Helper 审计结果，方便排障。 |
| P1 | Provider 更新历史 | 记录每次资源更新的时间、结果、文件路径、错误信息。 |
| P1 | 连接与规则联动 | 从连接详情跳转到命中的规则、策略组和 Provider。 |
| P2 | 快捷键 | 提供打开主窗口、启停核心、切换系统代理、切换模式等可配置快捷键。 |

## 7. 建议新增功能池

这些不是为了立刻扩张功能面，而是围绕当前项目的长期可维护性和专业体验补短板。

| 功能 | 价值 | 建议优先级 |
| --- | --- | --- |
| 网络安全中心 | 把系统代理、系统 DNS、TUN、路由、快照、修复动作集中管理 | P0 |
| 配置 Inspector | 让用户知道最终 runtime config 从哪里来、哪些字段被 App 接管 | P0 |
| 诊断包导出 | 大幅降低远程排障成本 | P1 |
| Provider 更新历史和回滚 | 资源更新失败时能回到上一份可用文件 | P1 |
| Controller WebSocket 事件流 | 减少轮询，提高连接、日志、流量实时性 | P1 |
| Profile 健康评分 | 帮用户提前发现订阅、规则、Provider、DNS 问题 | P2 |
| 发布通道管理 | Stable/Beta/Canary 三通道配合签名 manifest | P2 |
| Sub-Store 集成 | 订阅转换能力很强，但维护成本高，建议主体验稳定后再做 | P3 |

## 8. 第二版里程碑建议

| 阶段 | 目标 | 关键产出 |
| --- | --- | --- |
| M1 硬化网络接管 | 解决代理、DNS、TUN 快照边界和状态解释问题 | 独立快照、状态机、网络修复中心、回归用例 |
| M2 配置质量提升 | 减少 Profile 和覆写造成的启动失败 | schema 校验、配置 Inspector、分层 diff |
| M3 测试与发版体系 | 支撑可持续迭代 | 单元测试、mock 集成测试、release smoke test、许可证清单 |
| M4 专业体验打磨 | 提升长期使用效率 | 诊断包导出、Provider 历史、连接规则联动、快捷键 |
| M5 高级生态扩展 | 仅在主链路稳定后推进 | Sub-Store、发布通道、更多同步后端 |

## 9. 当前推荐的下一步

最建议下一轮不要继续大规模增加功能，而是优先完成三件事：

1. 完善网络接管快照边界和状态机，解决系统代理、系统 DNS、TUN 状态解释不清的问题。
2. 为配置生成、结构化编辑、更新校验、Secret vault 补测试，先覆盖最容易造成用户网络中断或数据丢失的路径。
3. 做一次真实 release 演练，从打包、上传 GitHub Release、应用内检查、验签、替换、回滚完整跑通。

完成这三件事后，项目会从“功能很多的 MVP”进入“可以持续发布和长期维护的 Beta”状态。

## 10. 小版本发布记录

| 版本 | 变更 | 验证 |
| --- | --- | --- |
| v1.0.4 | 修复 DIRECT 延迟无法测出的问题：DIRECT 不再直接依赖 mihomo Controller `/delay` 对内置出站的支持，而是由 App 使用禁用系统代理的直连 `URLSession` 对配置的测速 URL 进行兜底测速；REJECT 明确标记为不可测速并从失败统计中跳过。 | 使用 `./script/build_and_run.sh --verify`、release package、manifest、签名和线上更新清单校验作为小版本发布门禁。 |
| v1.1.0 | 完成网络接管与 Helper 硬化：新增三类网络接管状态机、诊断页网络修复中心、独立 DNS 恢复入口、Helper 事务步骤/回滚建议、SecStaticCode requirement 校验。 | 使用 `./script/build_and_run.sh --verify`、概览截图检查、release package、manifest、签名和线上更新清单校验作为小版本发布门禁。 |
| v1.2.0 | 完成配置质量与可维护性：新增规则 schema 校验、配置质量评分、Runtime Config Inspector、Profile/JS/YAML/App overlay 分层 diff 和 settings schema v2 迁移日志。 | 使用 `./script/build_and_run.sh --verify`、`git diff --check`、release package、manifest、签名和线上更新清单校验作为小版本发布门禁。 |

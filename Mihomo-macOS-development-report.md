# Mihomo macOS 原生客户端开发报告（第三版）

生成日期：2026-07-07
报告定位：基于当前仓库状态，对第二版开发报告进行更新。第三版重点跟进 v1.4.2 之后的阶段推进：M1 网络安全中心、M2 配置 Inspector 字段来源、DNS/TUN/Provider/Sniffer schema 风险检查、v1.6.0 Provider 更新备份与回滚、v1.7.0 Controller WebSocket 事件流，以及 v1.8.0 许可证清单打包门禁。

## 1. 当前结论

当前项目已经从早期规划推进到 v1.8.0 许可证清单打包发布候选阶段。主 App 使用 SwiftUI 为主、AppKit 为辅的架构，已经形成概览、网络安全、活动、策略、配置、规则、资源、高级、日志、诊断、设置等完整工作台；特权操作已从主 App 收口到 XPC Helper；配置生成、资源更新、Profile 编辑、备份同步、应用内更新等高级能力也已落地。

本轮修复后，项目的日常可用性更接近成熟网络工具：日志入口不再绑定单一页面，策略页在核心未启动时也能读取本地配置结构，资源页改为高密度表格并支持 Provider 并发下载、上一版本备份和手动回滚，活动页可通过 Controller WebSocket 实时接收流量、日志和连接事件并保留轮询降级，网络安全中心集中展示系统代理、系统 DNS、TUN、快照边界和修复动作，配置 Inspector 能解释 runtime 字段来自 Profile、JS Transform、YAML 片段还是 App overlay。但当前项目还不应直接定义为“稳定公开发行版”。它更接近“可长期自用和小范围测试的 Beta 前状态”。核心原因不是功能不足，而是以下几个系统性硬化点仍需要继续收敛：

- 网络接管状态机和快照边界已集中到网络安全中心，但还需要更多真实系统场景回归。
- Helper 已承担高权限操作，但授权校验、操作审计、失败回滚还需要面向真实分发继续硬化。
- 项目功能面已经较宽，后续重点应从“继续横向加功能”转向测试、可观测性、迁移兼容、发布流程和用户可理解性。
- 当前已有 SwiftPM XCTest 基础覆盖，但 UI、Helper 高权限事务、备份恢复和真实更新安装仍需要继续补充自动化验证。

## 2. 当前工程状态

| 维度 | 当前状态 | 依据 |
| --- | --- | --- |
| 工程组织 | SwiftPM 工程，包含主 App、Helper、Shared 协议三个 target | `Package.swift` |
| 平台要求 | macOS 14+，Swift 5.9+ | `Package.swift`、`README.md` |
| UI 技术 | SwiftUI 主体，AppKit 承接高密度表格、日志文本视图、窗口细节 | `Sources/Mihomo/Views` |
| 主界面 | Sidebar 分区覆盖概览、网络安全、活动、策略、配置、规则、资源、高级、日志、诊断、设置 | `AppSection`、`RootView` |
| Controller 能力 | 封装版本、模式、策略组、连接、流量、Provider、延迟测试等 API | `MihomoControllerClient.swift`、`AppStore.swift` |
| 特权能力 | XPC Helper 执行 core 启停、配置校验、系统代理、系统 DNS、TUN 快照、LaunchDaemon 管理 | `MihomoHelper`、`HelperClient.swift` |
| 配置生成 | 使用 Yams 结构化合并 YAML，清理 App 管理键，支持 YAML/JS 覆写、禁用规则、候选配置与回滚 | `RuntimeConfigBuilder.swift`、`ProfileStore.swift` |
| 发布链路 | release 脚本、固定 ad-hoc identifier、Ed25519 manifest 签名、GitHub Latest Release 更新入口 | `script/*`、`SoftwareUpdateManager.swift` |
| 本地数据 | App Support 保存设置、Profile、runtime、Core、Geo、External UI、Backups、Tools；日志进入 `~/Library/Logs/Mihomo` | `AppPaths.swift` |

## 3. 已实现与新增功能项

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
| 网络安全中心 | v1.4.3 已实现 | 独立页面集中管理接管开关、接管状态、代理/DNS/TUN 快照边界、修复动作和诊断导出。 |

### 3.3 Profile 与配置维护

| 功能项 | 当前状态 | 说明 |
| --- | --- | --- |
| 本地、远程、拖入、深链导入 | 已实现 | 支持本地 YAML、远程订阅、文件导入、`mihomo://` 导入。 |
| 远程订阅证书指纹校验 | 已实现 | 首次记录 HTTPS 证书 SHA-256，刷新时校验。 |
| 订阅自动刷新队列 | 已实现 | 支持刷新间隔、最大并发、失败状态和通知。 |
| Profile 存储目录迁移 | 已实现 | 可修改 Profile 存储路径并迁移已有文件。 |
| Profile 统计摘要 | 已实现 | 默认展示规则、策略组、节点、Provider、行数、大小等统计。 |
| 配置 Inspector 字段来源 | v1.5.0 已实现 | 配置质量区展示 runtime 字段来源，标记 App 接管字段，并说明 Profile/JS/YAML/App overlay 的覆盖关系。 |
| 配置 schema 风险检查 | v1.5.0 已实现 | 对 DNS enhanced-mode/nameserver、TUN enable/dns-hijack、Sniffer 端口、Provider type/url/path/interval 做质量告警。 |
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
| 离线策略预览 | 本轮已实现 | 核心未启动或 Controller 未返回策略组时，从当前激活 Profile 解析 `proxy-groups` 并展示组、候选节点和 Provider 引用。 |
| 延迟测试 | 已实现并修复内置出站 | 支持单节点、单组、全部节点，并可配置并发和测试 URL；v1.0.4 起 DIRECT 使用 App 侧直连 URLSession 兜底测速，REJECT 作为不可测速出站跳过，不再污染失败统计。 |
| 连接列表与 Inspector | 已实现 | 支持连接过滤、分组、关闭单连接、关闭全部连接和详情窗口。 |
| 实时流量采样 | 已实现 | 概览和活动页可显示上下行速率与图表；v1.7.0 起优先使用 Controller WebSocket traffic 事件，降级时保留轮询。 |
| 日志过滤、暂停、落盘与轮转 | 已实现 | 支持暂停、缓冲、保留天数、单文件大小和 App/Core 分离日志。 |
| 全局日志浮层 | 本轮已实现 | 任意主界面顶部显示最近事件胶囊，点击展开最近日志面板，点击背景收起。 |
| Controller WebSocket 事件流 | v1.7.0 已实现 | 新增 traffic、logs、connections 三路 WebSocket 消费，活动页显示事件流状态；断线或 endpoint 不支持时自动保留轮询。 |

### 3.5 资源、备份、更新与分发

| 功能项 | 当前状态 | 说明 |
| --- | --- | --- |
| Rule/Proxy Provider 本地解析 | 已实现 | 从 Profile YAML 解析 Provider、引用数、URL、path、interval 等信息。 |
| Controller Provider 更新 | 已实现 | core 运行时可通过 Controller 请求更新 Provider。 |
| Provider 直接下载更新 | 已实现 | 不依赖 core 运行，可按本地配置 URL 下载到 runtime provider path。 |
| 一键更新外部资源 | 已实现 | 同时更新 Provider 和 Geo 数据。 |
| Provider 并发更新 | 本轮已实现 | 批量下载 Provider 时按设置并发数限流执行，避免多资源场景串行等待。 |
| Provider 更新备份与回滚 | v1.6.0 已实现 | 下载前自动备份现有 Provider 文件，资源页展示持久化历史，并提供上一版本手动回滚入口。 |
| 外部资源表格化 | 本轮已实现 | 资源页改为“类型、最后更新、路径、状态”高密度表格，并提供未就绪过滤、全部更新和完成入口。 |
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
| 自动化测试 | 中 | 已有 `Tests/MihomoTests` 覆盖配置生成、YAML 编辑、更新校验、Secret vault、Controller/Helper mock 解析；UI、Helper 高权限事务和真实安装流程仍需扩展。 |

## 5. 当前主要风险与不一致点

| 风险 | 影响 | 建议处理 |
| --- | --- | --- |
| 网络接管真实系统回归仍不足 | v1.4.3 已集中代理、DNS、TUN 状态和快照边界，但真实网络服务名称变化、无快照恢复、默认路由异常等场景仍依赖手动验证 | 为 Helper 网络事务增加更多 mock 和受控命令输出测试，并沉淀真实系统 smoke checklist。 |
| TUN、系统 DNS、系统代理的用户心智仍需继续压实 | 网络安全中心已明确代理快照、DNS 快照、TUN 快照互不混用，但长期使用中仍可能需要更强的单选接管模式 | 下一阶段可把“接管模式”升级为系统代理、TUN、DNS-only、手动的显式单选模型。 |
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

v1.3.0 完成状态：

| 优化项 | 完成状态 | 主要落点 |
| --- | --- | --- |
| 单元测试 | 已实现 | 新增 `MihomoTests`，覆盖 `RuntimeConfigBuilder`、`ProfileYAMLStructureEditor`、`SoftwareUpdateManager`、`LocalSecretVault`。 |
| Mock Controller 集成测试 | 已实现 | `MihomoControllerClient` 抽出 JSON 解析函数，测试代理组、连接、Provider 响应映射，无需真实 core。 |
| Mock Helper 集成测试 | 已实现 | 测试 `HelperOperationResult` 对成功 payload、事务步骤、回滚建议和失败错误的解析。 |
| release smoke test | 已实现 | 新增 `script/release_smoke_test.sh`，验证 app codesign、bundle id、manifest、latest manifest、Ed25519 元数据和 zip SHA-256。 |
| 许可证与 SBOM | v1.8.0 已实现 | `THIRD_PARTY_NOTICES.md` 记录 mihomo、Yams、CryptoKit、age、zashboard、meta-rules-dat 等来源和授权注意事项，并随 release app bundle 打入 `Contents/Resources/`；smoke test 会校验 bundle 和 zip 内均存在。 |

### 6.4 v1.4 体验与专业工具打磨

目标：在不继续堆叠复杂功能的前提下，让日常使用更接近成熟网络工具。

| 优先级 | 优化项 | 验收标准 |
| --- | --- | --- |
| P0 | TUN / 系统代理 / 系统 DNS 解释与互斥提示 | 用户同时开启 TUN 和系统代理时，App 明确提示冗余和可能的恢复行为。 |
| P1 | 诊断包导出 | 一键导出脱敏设置、runtime 摘要、日志片段、Helper 审计结果，方便排障。 |
| P1 | Provider 更新历史 | 记录每次资源更新的时间、结果、文件路径、错误信息。 |
| P1 | 连接与规则联动 | 从连接详情跳转到命中的规则、策略组和 Provider。 |
| P2 | 快捷键 | 提供打开主窗口、启停核心、切换系统代理、切换模式等可配置快捷键。 |

v1.4.0 完成状态：

| 优化项 | 完成状态 | 主要落点 |
| --- | --- | --- |
| TUN / 系统代理 / 系统 DNS 解释与互斥提示 | 已实现 | 概览页在 TUN、系统代理、系统 DNS 同时启用时显示冗余/恢复提示；诊断包也记录 advisory。 |
| 诊断包导出 | 已实现 | 诊断页新增导出入口，生成脱敏摘要、runtime 配置、App 日志尾部、core 日志和 Provider 历史 zip，并在 Finder 中定位。 |
| Provider 更新历史 | 已实现 | 资源页展示最近 Provider Controller 更新、下载、批量下载的时间、结果、目标路径和错误信息。 |
| Provider 回滚 | v1.6.0 已实现 | Provider 直接下载和批量下载覆盖前备份上一版本；资源页选中 Provider 后可从最近可用备份手动回滚。 |
| 连接与规则联动 | 已实现 | 活动页连接详情新增“查看规则”和“Provider”跳转；规则页接收连接命中规则并自动过滤/选中。 |
| 快捷键 | 已增强 | 主菜单新增 TUN、系统 DNS 接管、导出诊断包快捷入口，并保留主窗口、核心启停、系统代理、订阅刷新、检查更新、诊断等快捷键。 |

v1.4.3 / M1 发布候选完成状态：

| 修缮项 | 完成状态 | 主要落点 |
| --- | --- | --- |
| 全局日志入口 | 已实现 | `RootView` 增加全局日志胶囊和展开面板，任何主界面都能查看最近事件，展开后点击背景收起。 |
| 离线策略组展示 | 已实现 | `AppStore.refreshConfigArtifacts()` 从激活 Profile 生成 `offlineProxyGroups`；`PoliciesView` 在 Controller 无数据时自动切换为离线预览，并禁用测速/切换动作。 |
| 配置质量 UI 压缩 | 已实现 | `ProfileQualityPane` 改为评分头、问题、Runtime Inspector、分层 Diff 三列密集布局，降低配置页纵向占用。 |
| 外部资源表格 | 已实现 | `ResourcesView` 参考 Surge 式表格重做，展示名称、类型、最后更新、路径、状态，并提供未就绪过滤和底部操作栏。 |
| Provider 更新速度 | 已优化 | `updateAllExternalResources()` 改为按 `profileRefreshMaxConcurrent` 限流的并发下载，完成后统一刷新配置和 Geo 状态。 |
| 网络安全中心 | 已实现 | 新增 `NetworkSecurityView`，集中展示接管开关、接管状态表、快照边界表、修复中心和诊断导出。 |
| 网络快照回归测试 | 已实现 | 新增 `NetworkSecurityCenterTests`，验证代理、DNS、TUN 快照说明互不混用，并验证整体健康状态优先级。 |

v1.5.0 / M2 发布候选完成状态：

| 修缮项 | 完成状态 | 主要落点 |
| --- | --- | --- |
| 配置字段来源 Inspector | 已实现 | `ProfileQualityReport.sourceItems` 和配置页字段来源表展示 runtime 顶层字段的最终值、来源和 App 接管说明。 |
| App 接管字段解释 | 已实现 | mixed/socks/allow-lan/mode/log/controller/secret/dns/sniffer/tun/external-ui 等字段标记为 App overlay，并提示同名 Profile/YAML 字段会被移除重写。 |
| Runtime schema 风险检查 | 已实现 | `ProfileQualityAnalyzer` 新增 DNS、TUN、Sniffer、Provider 的 schema 风险检查，进入健康评分。 |
| 配置质量回归测试 | 已实现 | 新增 `ProfileQualityAnalyzerTests`，覆盖字段来源识别和 schema 风险告警。 |

## 7. 建议新增功能池

这些不是为了立刻扩张功能面，而是围绕当前项目的长期可维护性和专业体验补短板。

| 功能 | 价值 | 建议优先级 |
| --- | --- | --- |
| 网络安全中心 | 把系统代理、系统 DNS、TUN、路由、快照、修复动作集中管理 | v1.4.3 已完成 |
| 配置 Inspector | 让用户知道最终 runtime config 从哪里来、哪些字段被 App 接管 | v1.5.0 已完成 |
| 诊断包导出 | 大幅降低远程排障成本 | v1.4.0 已完成 |
| Provider 更新历史和回滚 | 资源更新失败时能回到上一份可用文件 | v1.6.0 已完成 |
| Controller WebSocket 事件流 | 减少轮询，提高连接、日志、流量实时性 | v1.7.0 已完成 |
| Profile 健康评分 | 帮用户提前发现订阅、规则、Provider、DNS 问题 | v1.2.0 已完成，v1.5.0 扩展 schema 风险 |
| 发布通道管理 | Stable/Beta/Canary 三通道配合签名 manifest | P2 |
| Sub-Store 集成 | 订阅转换能力很强，但维护成本高，建议主体验稳定后再做 | P3 |

## 8. 里程碑建议

| 阶段 | 目标 | 关键产出 |
| --- | --- | --- |
| M1 硬化网络接管 | 解决代理、DNS、TUN 快照边界和状态解释问题 | v1.4.3 已完成：独立快照、状态机、网络安全中心、网络修复中心、回归用例 |
| M2 配置质量提升 | 减少 Profile 和覆写造成的启动失败 | v1.5.0 已完成：schema 校验、字段来源 Inspector、分层 diff、健康评分 |
| M3 测试与发版体系 | 支撑可持续迭代 | v1.8.0 完成：单元测试、mock 集成测试、release smoke test、许可证清单打包门禁 |
| M4 专业体验打磨 | 提升长期使用效率 | v1.7.0 基本完成：诊断包导出、Provider 历史与回滚、连接规则联动、快捷键、Controller WebSocket |
| M5 高级生态扩展 | 仅在主链路稳定后推进 | Sub-Store、发布通道、更多同步后端 |

## 9. 当前推荐的下一步

最建议下一轮围绕真实分发后的稳定性收口，不继续横向堆功能，而是优先完成三件事：

1. 增加真实更新安装后的 manifest、签名 identifier、Helper 通信 smoke 验证记录。
2. 为 WebSocket 断线重连、Provider 回滚和更新安装路径补更细的集成测试。
3. 做一轮真实系统网络场景回归：系统代理、系统 DNS、TUN、退出恢复、崩溃恢复。

完成这三件事后，项目会从“功能很多的 MVP”进入“可以持续发布和长期维护的 Beta”状态。

## 10. 小版本发布记录

| 版本 | 变更 | 验证 |
| --- | --- | --- |
| v1.0.4 | 修复 DIRECT 延迟无法测出的问题：DIRECT 不再直接依赖 mihomo Controller `/delay` 对内置出站的支持，而是由 App 使用禁用系统代理的直连 `URLSession` 对配置的测速 URL 进行兜底测速；REJECT 明确标记为不可测速并从失败统计中跳过。 | 使用 `./script/build_and_run.sh --verify`、release package、manifest、签名和线上更新清单校验作为小版本发布门禁。 |
| v1.1.0 | 完成网络接管与 Helper 硬化：新增三类网络接管状态机、诊断页网络修复中心、独立 DNS 恢复入口、Helper 事务步骤/回滚建议、SecStaticCode requirement 校验。 | 使用 `./script/build_and_run.sh --verify`、概览截图检查、release package、manifest、签名和线上更新清单校验作为小版本发布门禁。 |
| v1.2.0 | 完成配置质量与可维护性：新增规则 schema 校验、配置质量评分、Runtime Config Inspector、Profile/JS/YAML/App overlay 分层 diff 和 settings schema v2 迁移日志。 | 使用 `./script/build_and_run.sh --verify`、`git diff --check`、release package、manifest、签名和线上更新清单校验作为小版本发布门禁。 |
| v1.3.0 | 完成测试与发版体系：新增 SwiftPM 测试目标、8 个核心 XCTest、Controller/Helper mock 解析测试、release smoke 脚本和第三方清单。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.3.0` 和线上更新清单校验作为小版本发布门禁。 |
| v1.4.0 | 完成专业工具体验打磨：新增网络接管互斥提示、诊断包导出、Provider 更新历史、连接到规则/资源联动和更多主菜单快捷键。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.4.0` 和线上更新清单校验作为小版本发布门禁。 |
| v1.4.1 | 根据稳定性审查完成修缮：连接详情独立窗口化、菜单核心状态实时刷新、日志批量发布、表格差异刷新、配置页纵向滚动、Helper 启动前自修复、系统代理/TUN 互斥和 TUN 关闭前路由恢复。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.4.1`、manifest、签名和线上更新清单校验作为补丁版本发布门禁。 |
| v1.4.2 | 完成 UI 性能全量审查与修复：Controller 轮询改为差异发布，网络接管系统命令改为节流刷新，配置统计/质量分析加入指纹缓存，日志和 AppKit 表格避免重复渲染，同时纳入策略无启动空态、配置页滚动和主窗口尺寸稳定性修复。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.4.2`、manifest、签名和线上更新清单校验作为补丁版本发布门禁。 |
| v1.4.3 | 完成 M1 网络安全中心，并纳入全局日志浮层、离线策略预览、配置质量区压缩、外部资源表格化和 Provider 并发更新。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.4.3`、manifest、签名和线上更新清单校验作为阶段版本发布门禁。 |
| v1.5.0 | 完成 M2 配置质量提升：字段来源 Inspector、App 接管字段解释、DNS/TUN/Provider/Sniffer schema 风险检查和配置质量回归测试。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.5.0`、manifest、签名和线上更新清单校验作为阶段版本发布门禁。 |
| v1.6.0 | 完成 Provider 更新备份与回滚：直接下载和批量下载会在覆盖前备份上一版本，资源页展示持久化更新历史，并提供手动回滚入口；诊断包同步记录备份与恢复来源。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.6.0`、manifest、签名和线上更新清单校验作为阶段版本发布门禁。 |
| v1.7.0 | 完成 Controller WebSocket 事件流：新增 traffic/logs/connections 实时通道，活动页展示事件流状态，断线或 endpoint 不支持时自动降级到轮询，并补充事件解析回归测试。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.7.0`、manifest、签名和线上更新清单校验作为阶段版本发布门禁。 |
| v1.8.0 | 完成许可证清单打包门禁：`THIRD_PARTY_NOTICES.md` 随 App bundle 打入 Resources，release smoke test 校验 bundle 与 zip 内均存在清单。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/build_and_run.sh --verify`、`script/release_smoke_test.sh 1.8.0`、manifest、签名和线上更新清单校验作为阶段版本发布门禁。 |

## 11. 稳定性与性能审查记录

本轮审查针对活动详情、菜单状态、滚动性能、应用内更新后的 Helper 通信、核心启动稳定性、系统代理/TUN 互斥和配置页布局进行。

| 类别 | 发现 | 本轮处理 | 后续建议 |
| --- | --- | --- | --- |
| UI 架构 | 活动页把连接详情内嵌在右侧，挤压连接列表，也限制后续高级功能承载。 | 连接详情改为独立窗口面板，提供摘要、规则、链路分段，并由活动列表选中/双击打开。 | 后续可继续把 DNS、设备、请求历史、MITM 等高级详情挂入该独立面板。 |
| 菜单状态 | 菜单栏核心启停文本存在刷新不及时风险。 | 菜单栏内容增加核心状态行，并按核心、系统代理、TUN、模式状态生成稳定刷新标识。 | 如果后续菜单承载更多动态数据，应拆出轻量 MenuBar 状态模型，避免主 Store 高频刷新影响菜单。 |
| 概览性能 | 日志逐条追加会触发 `AppStore.objectWillChange`，概览滚动时容易随最新日志重绘。 | 日志仍即时落盘，但 UI 改为 350ms 批量发布，并保留日志暂停/缓冲行为。 | 中期应把日志流拆成独立 ObservableObject，避免单一 AppStore 高频通知所有页面。 |
| 表格滚动 | `AppKitTable.updateNSView` 每次 SwiftUI 更新都 `reloadData()`，策略/规则/活动滚动会被选择、日志、测速状态打断。 | 表格改为基于列和单元格内容签名的差异刷新；策略组列表也改用同一 AppKit 表格。 | 后续大规模连接列表可进一步做增量 row reload 或 Controller WebSocket diff。 |
| 配置页布局 | 配置页下方质量信息固定在主窗口底部，窗口高度不足时内容被裁切。 | 配置页主内容改为纵向滚动；配置表固定稳定高度；质量区改为自适应网格。 | 后续可把配置质量 Inspector 拆成独立 inspector 面板，支持更长的问题列表和 diff 详情。 |
| Helper / 更新稳定性 | 应用更新后 privileged Helper 可能仍指向旧 bundle 或旧签名，启动核心时报 `Couldn't communicate with a helper application`。 | 启动核心前先探测 Helper；失败时自动移除旧注册、注册当前 bundle Helper、等待后复查，必要时打开系统设置提示授权。 | 发布 Developer ID 后应把 Helper requirement 升级到 Team ID，并在应用更新完成后的首次启动记录 helper bundle build。 |
| 核心启动稳定性 | 启动流程在 Helper 不可用时直接失败，用户只能手动修复。 | `startCore()` 前置 Helper 预检与自修复，失败信息明确指向登录项与扩展授权。 | 后续加入核心启动状态机，将配置生成、Helper、geo 数据、进程启动、Controller ready 分阶段展示。 |
| 系统代理 / TUN | 系统代理和 TUN 同时开启会造成接管边界混乱，关闭 TUN 时还可能因先保存设置而跳过路由恢复。 | 开启 TUN 前自动关闭系统代理；开启系统代理前自动关闭 TUN；关闭 TUN 且核心运行时先恢复 TUN 快照再保存设置/重启。 | 后续网络安全中心应把“接管模式”做成单选：系统代理、TUN、DNS-only、手动。 |
| 残余风险 | `AppStore` 仍是大型单体状态源，任一 `@Published` 高频更新都会影响多个页面。 | 本轮已降低最高频的日志和表格刷新成本。 | 下一阶段建议拆分 `ConnectionStore`、`LogStore`、`ProfileStoreViewModel`、`NetworkTakeoverStore`，并为滚动列表加入性能基准。 |

v1.4.1 完成状态：

| 修缮项 | 完成状态 | 主要落点 |
| --- | --- | --- |
| 独立详情面板 | 已实现 | 活动页不再内嵌右侧详情，选中/双击连接打开独立连接详情窗口，并提供摘要、规则、链路分段。 |
| 菜单状态实时刷新 | 已实现 | 菜单栏新增核心状态行，并按核心、系统代理、TUN、出站模式生成刷新标识，避免启停状态显示滞后。 |
| 滚动性能 | 已优化 | 日志 UI 改为批量发布；`AppKitTable` 改为内容签名差异刷新；策略组列表迁移到 AppKit 表格，降低策略/规则滚动重载。 |
| 配置页布局 | 已修复 | 配置页主体改为纵向滚动，配置表使用稳定高度，质量 Inspector 使用自适应网格，窗口较矮时不再裁切。 |
| Helper 更新后启动失败 | 已修复路径 | `startCore()` 前先探测 Helper，通信失败时自动移除旧注册并注册当前 bundle Helper，必要时打开系统设置提示授权。 |
| 系统代理 / TUN 稳定性 | 已修复 | 开启 TUN 前关闭系统代理，开启系统代理前关闭 TUN；关闭 TUN 且核心运行时先恢复 TUN 路由快照再保存设置。 |

## 12. UI 性能全量审查记录

本轮审查针对主窗口、概览、活动、策略、配置、规则、资源、日志、诊断和菜单栏的刷新链路进行，重点检查 SwiftUI 观察范围、轮询发布频率、AppKit 桥接、YAML 解析、列表滚动和系统命令调用。

| 类别 | 发现 | 本轮处理 | 后续建议 |
| --- | --- | --- | --- |
| 观察范围 | 单一 `AppStore` 承载几十个 `@Published`，任一高频字段变化都会触发使用 `@EnvironmentObject` 的页面更新。 | Controller 轮询结果改为 `publishIfChanged` 差异发布，减少相同版本、模式、策略组、连接、速率、规则和 Provider 的重复通知。 | 中期拆分 `ConnectionStore`、`LogStore`、`ProfileAnalysisStore` 和 `NetworkTakeoverStore`，让页面订阅更窄的状态面。 |
| 主线程阻塞 | 普通 Controller 轮询会调用 `networksetup` 抓系统代理/DNS 快照，系统命令在主 actor 上执行，容易造成周期性 UI 卡顿。 | 网络接管状态增加 20 秒节流；启动、停止、切换系统代理/TUN、诊断等显式操作仍强制刷新。 | 后续把系统快照采集移入后台服务，并用异步结果回填 UI。 |
| 配置页解析 | 配置页每次重绘都会读取 profile、解析 YAML 结构并生成质量报告。 | `profileStats` 和 `profileQualityReport` 增加 profile/settings/fragments/disabledRules/migrationLog 指纹缓存。 | 后续把质量分析改成后台任务，展示上次分析时间和可取消状态。 |
| AppKit 表格 | SwiftUI 更新会进入 `updateNSView`，即使行数组未变也会构造单元格字符串签名。 | `AppKitTable` 要求行类型 `Hashable`，先比较行数组，只有行变化时才计算签名和 reload。 | 大连接量场景可进一步使用行级 diff reload。 |
| 日志渲染 | 日志 AppKit 文本视图每次更新都会先拼接全部日志字符串。 | `AppKitLogView` 先比较 `entries` 数组，日志未变时跳过字符串拼接和 NSTextView 更新。 | 日志流后续应拆成独立 store，避免日志新增影响非日志页面。 |
| 活动页分组 | 连接分组/排序在一次 body 中被多处读取。 | 活动页将本轮 `tableRows` 作为局部值传入表格，避免同一轮渲染重复分组。 | Controller WebSocket 事件流上线后可改为连接 diff，而不是全量轮询。 |
| 空态和窗口 | 策略未启动时仍渲染空表格骨架，配置页底部质量面板会被裁切，主窗口默认高度不稳定。 | 策略无启动态改为启动引导面板；配置页整页滚动并自适应表格高度；主窗口设置默认尺寸和内容最小尺寸。 | 继续保持 Surge 风格的密度，避免把状态面板做成大面积营销式空态。 |

v1.4.2 完成状态：

| 修缮项 | 完成状态 | 主要落点 |
| --- | --- | --- |
| 轮询差异发布 | 已实现 | `refreshController()` 对版本、模式、策略组、连接、速率和核心状态使用差异发布，连接未变时跳过规则/Provider 命中重算。 |
| 网络接管节流 | 已实现 | 普通轮询下网络接管状态 20 秒节流，显式网络操作和诊断强制刷新。 |
| 配置分析缓存 | 已实现 | profile 统计和质量报告按指纹缓存，避免配置页因无关状态变化重复读盘和解析 YAML。 |
| AppKit 渲染优化 | 已实现 | 表格先比较行数组再计算签名；日志视图先比较日志 entries 再拼接文本。 |
| 活动页渲染收敛 | 已实现 | 连接表格行在一次 body 内只计算一次。 |
| UI 布局稳定性 | 已实现 | 策略启动空态、配置页可滚动和主窗口尺寸稳定修复纳入 1.4.2。 |

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
| Helper 授权检查 | 已增强 | Helper 校验调用方来自 Mihomo App bundle，检查签名 identifier，通过 SecStaticCode requirement 绑定当前 ad-hoc bundle identifier，并要求调用方 app 与 Helper 所属 app bundle 一致；未来 Developer ID 可扩展 Team ID / designated requirement。 |
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
| 分发与更新 | 中 | 已有无 Developer ID 的固定 ad-hoc 分发路径和签名 manifest；v1.8.33 增加更新包安装前失败路径测试，v1.8.34 修复替换复制失败时的旧 app 恢复，v1.8.40 增加 Developer ID/Team ID/notarization 可选强门禁，但本地包仍未公证，仍需受保护发布环境验证。 |
| 自动化测试 | 中 | 已有 `Tests/MihomoTests` 覆盖配置生成、YAML 编辑、更新校验、更新包安装前校验失败、安装脚本复制失败与签名失败回滚、Secret vault、Settings Codable 兼容、Controller/Helper mock 解析、Controller WebSocket 解析与重连退避、Helper 路径策略、备份恢复、Provider 回滚边界、诊断脱敏、网络 timeout 策略和下载 artifact checksum 失败不替换；v1.8.4 增加 GitHub Actions 基础 CI；UI、Helper 高权限事务和真实安装流程仍需扩展。 |

## 5. 当前主要风险与不一致点

| 风险 | 影响 | 建议处理 |
| --- | --- | --- |
| 网络接管真实系统回归仍不足 | v1.4.3 已集中代理、DNS、TUN 状态和快照边界；v1.8.41 增加只读 `network_takeover_smoke.sh`，可采集真实 network services、代理/DNS、默认路由、utun、route table 和 Mihomo snapshot，并用 `--assert-clean` 检测恢复后残留；v1.8.49 增加 TSV summary 与 `--baseline` 前后比对，让手动开关/退出/崩溃恢复演练能证明是否回到测试前状态；v1.8.55 增加 `--scenario` 和可重复 `--note`，把手动代理/DNS/TUN/退出/崩溃恢复演练的操作上下文写入 Markdown 报告且不污染 TSV baseline；v1.8.59 增加 `--phase`，让 before/enabled/after-stop/after-quit/after-crash/recovered 等阶段随 Markdown 证据保存且不污染 TSV baseline | 继续用 smoke 脚本沉淀系统代理、系统 DNS、TUN、退出恢复、崩溃恢复的前后报告，并逐步把可控场景变成 Helper mock 或受保护实机 gate。 |
| TUN、系统 DNS、系统代理的用户心智仍需继续压实 | 网络安全中心已明确代理快照、DNS 快照、TUN 快照互不混用，但长期使用中仍可能需要更强的单选接管模式 | 下一阶段可把“接管模式”升级为系统代理、TUN、DNS-only、手动的显式单选模型。 |
| Helper 授权仍是本地分发友好版 | v1.8.2 已增加同 bundle 绑定和 user-home 路径 allowlist；v1.8.40 让受保护发布机可以通过 `MIHOMO_CODESIGN_IDENTITY`、`MIHOMO_EXPECTED_TEAM_ID` 和 notarization 开关强制验证 Developer ID/Team ID/designated requirement，但本地 ad-hoc 包仍不具备 Team ID 级身份强度 | 在真实 Developer ID 发布环境执行 identity gate，并把 Helper runtime requirement 从 ad-hoc identifier 升级到 Team ID/designated requirement。 |
| 外部网络请求超时策略需持续维护 | v1.8.3 已把 Provider、managed core、Age、External UI、Geo、WebDAV/Gist、更新检查、证书 pinning Profile fetch 和 Controller API 收口到 `NetworkClient`；WebSocket 事件流和延迟测试保留专用 session | 后续网络功能默认走 `NetworkClient`，需要长连接或测速时必须显式说明 timeout 策略。 |
| 外部资源 provenance 的上游取证仍需维护 | v1.8.6 已要求 managed core、Age、External UI 和 Geo 下载均提供 SHA-256，缺失或不匹配时拒绝替换现有内容；External UI/Geo 默认 URL 指向可变上游，用户更新前必须填写与当前发布物匹配的 checksum | 后续引入受签名的项目 manifest 或固定版本 URL，并沉淀统一 ArtifactInstaller。 |
| JS 覆写仍属于显式信任的高级能力 | v1.8.7 已移入独立 `MihomoJSWorker`，限制每段脚本、输入、输出和片段数量，并以 1.5 秒 wall-clock timeout、CPU/地址空间 rlimit 终止失控执行；但脚本语义本身仍可任意改写配置 | 默认继续关闭；后续提供结构化 YAML patch DSL、API 白名单和更明显的信任提示。 |
| 更新安装脚本仍需真实回滚验证 | v1.8.33 已把下载后包校验抽成安装前边界，并用 XCTest 覆盖 SHA-256 不匹配、zip 缺少 `Mihomo.app`、bundle id 不匹配均不会写入安装脚本；v1.8.34 让 `ditto` 复制失败和签名验证失败共用 backup 恢复分支；v1.8.37 已用临时 app 执行脚本验证复制失败和替换后 codesign 失败都会恢复旧 app；v1.8.42 增加基于真实 release zip 的临时 app 替换 smoke，覆盖成功替换和坏候选回滚；v1.8.47 让 Helper XPC version 回传授权 App path/version/build，并在诊断中标记运行中 Helper 是否仍绑定当前 App；v1.8.50 让替换 smoke 同步校验 manifest build、嵌入 Helper 和 JS worker 签名 identifier | 继续在受保护 release 环境演练 `/Applications` 真实替换、版本升级、Helper 通信和用户授权路径。 |
| Secret vault 可用性与可迁移性冲突 | v1.8.44 保持普通备份 redacted 默认边界，同时新增用户口令二次加密的 portable secret bundle，可把 Controller/WebDAV/Gist secret 显式迁移到另一份 vault；v1.8.45 已在高级页备份区提供导入/导出入口；v1.8.46 修复 redacted Gist payload 恢复时误清空本机 vault 的边界，错误口令和 redacted restore 都不会覆盖现有 secret；v1.8.53 增加高级页“应用人工输入 Secret”，只把非空手填 secret 写回 vault，空字段保留当前本机 secret；v1.8.54 增加 Controller/WebDAV/Gist secret 的脱敏已就绪/缺失状态 | 后续继续把 restore wizard 的用户引导做得更完整。 |
| 配置 schema 校验不足 | v1.5.0 已覆盖 rule、provider、DNS、TUN、Sniffer 基础风险；v1.8.43 继续增加 DNS resolver scheme、TUN stack、Sniffer domain 和 Rule Provider behavior 的细粒度告警；v1.8.48 增加 rule type 拼写和 DOMAIN/GEOSITE payload URL 误填预检；v1.8.51 继续覆盖 IP-CIDR/IP-CIDR6 地址族混用、端口规则越界和 NETWORK payload 可疑样本；v1.8.52 增加 proxy-groups 节点、策略组和 Proxy Provider use 引用完整性预检；v1.8.57 继续补 SRC-IP-CIDR/SRC-IP-CIDR6、GEOIP、IP-ASN、PROCESS-NAME 和 PROCESS-PATH payload sanity checks，并补 XCTest | 后续继续把真实 `mihomo -t` 错误样本沉淀为 analyzer 回归用例。 |
| 发布环境的完整签名 smoke 仍需受保护执行 | v1.8.8 已在 PR/push CI 加入无 GUI release bundle gate，验证 app/Helper/JS worker/notices、Info.plist identity、嵌套签名和 zip 内容；v1.8.33 覆盖安装前包校验失败路径；v1.8.34 覆盖复制失败回滚；v1.8.38 让 release smoke 对 Ed25519 manifest 做真实验签；v1.8.39 增加篡改 manifest 必须验签失败的负向门禁；v1.8.40 增加 release identity gate；v1.8.58 增加只读 `protected_release_checklist.sh`，记录 Developer ID/notarization/stapler 发布环境 readiness 和受保护机器命令模板；v1.8.60 增加 `release_provenance_report.sh` 并由 release smoke 自动产出 artifact provenance 摘要；manifest 签名仍需要私钥 | 继续在受保护发布环境执行 Developer ID 签名、公证、stapler、`package_release.sh` 与完整 `release_smoke_test.sh`，并增加真实应用替换回滚演练。 |
| AppKit bridge 的实机辅助功能 QA 仍待补充 | v1.8.9 为通用表格和日志 bridge 增加 VoiceOver 标签、table/text-area role、帮助文本与 Return/Enter/Space 激活；已用 XCTest 验证语义和键盘入口；v1.8.56 增加只读 `accessibility_qa_checklist.sh`，为 VoiceOver、键盘-only 和 Accessibility Inspector 人工检查生成带版本/场景/页面清单的 Markdown 证据 | 后续在真实窗口中执行清单并把发现转为具体 UI 修复或自动化测试。 |
| AppStore 单体风险已明显收敛，剩余大型 View/Service 仍需拆分 | v1.8.10-1.8.25 已拆分服务、模型、备份同步、Profile、Provider/Geo 资源、网络接管、core lifecycle、配置片段/规则编辑、日志/诊断、策略延迟测试、高级资源安装、软件更新、Helper 管理、深链导入和设置迁移协调域；`AppStore.swift` 由 3,126 行降至 308 行。v1.8.26 将 `ProfileQualityAnalyzer` 的规则/Runtime schema 校验和 YAML helper 拆到 dedicated extensions，主 analyzer 降至 344 行。v1.8.27-v1.8.32 持续拆分 Profile、Policy、Advanced、Resources 和 Settings 支撑视图；v1.8.61 增加 `maintainability_audit.sh`，CI release gate 会非阻塞生成 350/500 行阈值报告；v1.8.62 将 `ProfileQualityAnalyzer+Validation.swift` 的 helper 拆入 `ProfileQualityAnalyzer+ValidationHelpers.swift`，over-max 文件从 1 个降为 0 个；v1.8.63 将 Controller WebSocket 事件流和流量采样协调拆入 `AppStore+ControllerStreams.swift`；v1.8.64 将 rule payload validation 拆入 `ProfileQualityAnalyzer+RuleValidation.swift`；v1.8.65 将高级页备份/同步和 Secret Bundle 面板拆入 `AdvancedBackupGroup.swift`；v1.8.66 将证书 pinning 和诊断脱敏拆入独立服务文件；v1.8.67 将日志缓冲、落盘、轮转和保留清理拆入 `AppStore+Logging.swift`；v1.8.68 将 Profile 结构编辑器规则面板拆入 `ProfileStructureRuleEditorView.swift`；v1.8.69 将规则编辑 sheet 拆入 `RuleEditorSheet.swift`；v1.8.70 将连接详情窗口拆入 `ConnectionDetailPanelView.swift`；v1.8.71 将 TUN recovery 路由和快照处理拆入 `HelperTunRecoveryTool.swift`，warning 文件降为 4 个，最大文件降至 374 行；v1.8.72 将概览 dashboard helper 与自定义 sidebar 拆入 `OverviewDashboardViews.swift`、`MihomoSidebarView.swift`，并将活动页收敛为连接表格面板，warning 文件维持 4 个 | 下一步继续拆剩余 350-500 行级 SwiftUI/Service 文件，并在触碰 warning 文件时优先拆分或补直接行为测试。 |

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
| Helper 授权升级 | 已增强 | Helper listener 保留 bundle 路径与 signing identifier 检查，使用 `SecStaticCode` requirement 校验，并在 v1.8.2 增加调用方 app 与 Helper 所属 app bundle 一致性校验；当前无 Developer ID，requirement 仍绑定 ad-hoc bundle identifier，后续可扩展 Team ID。 |
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
2. 为真实更新安装路径继续补受保护环境 smoke；WebSocket 断线重连退避状态已在 v1.8.35 增加 XCTest，Provider 回滚缺失备份与历史选择边界已在 v1.8.36 增加 XCTest，安装脚本复制失败和签名失败回滚已在 v1.8.34/v1.8.37 增加 XCTest。
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
| v1.8.1 | 完成审计整改第一批：Provider 直接下载拒绝绝对路径和 symlink 逃逸；本地/WebDAV zip 恢复改为 entry 预扫描、symlink 拒绝、临时目录解压和 allowlist copy；诊断包导出的 runtime config、app log、core log 统一脱敏并写入 redaction manifest。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 25 个 XCTest，通过 `git diff --check`、`./script/build_and_run.sh --verify`、`./script/package_release.sh 1.8.1` 和 `./script/release_smoke_test.sh 1.8.1`。 |
| v1.8.2 | 完成 Helper 高权限路径硬化：XPC 连接通过后按调用方 UID 绑定 user home，Helper 只接受该用户 `~/Library/Application Support/Mihomo/Runtime` 下的 runtime config/snapshot、`~/Library/Logs/Mihomo/mihomo-core.log`，core 仅允许来自该用户 App Support/Core 或同一 app bundle Resources/Core；同时要求调用方 app 与 Helper 所属 app bundle 一致。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 31 个 XCTest，通过 `git diff --check`、`./script/build_and_run.sh --verify`、`./script/package_release.sh 1.8.2` 和 `./script/release_smoke_test.sh 1.8.2`。 |
| v1.8.3 | 完成网络稳定性审计整改：新增 `NetworkClient` 和 `NetworkRequestKind`，为 API、下载和本地 Controller 请求设置统一 request/resource timeout；Provider、managed core、Age、External UI、Geo、WebDAV/Gist、GitHub 更新检查、证书 pinning Profile fetch 和深链远程 fragment 导入不再使用 `URLSession.shared.data/download`。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 33 个 XCTest；`rg "URLSession\\.shared\\.(data|download)" Sources/Mihomo` 无结果。 |
| v1.8.4 | 完成发布门禁审计整改第一步：新增 GitHub Actions CI，PR 和 push 到 `main`/`codex/**` 时执行 `git diff --check` 与 `swift test`，把已有本地单元测试纳入默认协作流程。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 33 个 XCTest，通过 `git diff --check`、`./script/package_release.sh 1.8.4` 和 `./script/release_smoke_test.sh 1.8.4`。 |
| v1.8.5 | 完成供应链整改第一批：新增 `ArtifactChecksum`，managed core 和 Age 工具下载必须提供 SHA-256；缺少 checksum 或校验不匹配时拒绝安装并保留现有可执行文件；设置页和高级页增加对应 checksum 字段，默认 Age v1.2.1 darwin arm64 包内置已验证 SHA-256。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 36 个 XCTest，通过 `git diff --check`、`./script/package_release.sh 1.8.5` 和 `./script/release_smoke_test.sh 1.8.5`。 |
| v1.8.6 | 完成供应链整改第二批：External UI、GeoIP 和 GeoSite 下载均要求 SHA-256；校验失败不替换当前内容。External UI 安装增加名称路径拒绝、解包后符号链接拒绝和暂存目录替换；Geo 数据更新通过暂存文件与备份恢复路径替换。默认 External UI/Geo URL 为可变上游，用户必须填写当前下载物的 checksum。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 39 个 XCTest，通过 `git diff --check`、`./script/package_release.sh 1.8.6` 和 `./script/release_smoke_test.sh 1.8.6`。 |
| v1.8.7 | 完成 JS override 稳定性整改：新增独立并签名的 `MihomoJSWorker`，主进程通过 JSON 管道执行 transform；每段脚本限 64 KiB、输入限 1 MiB、输出限 2 MiB、启用片段最多 8 个，单段执行 1.5 秒超时。worker 额外施加 CPU 和地址空间限制，超时直接终止且不写入 runtime config；release smoke test 校验 worker 随 app bundle 和 zip 分发。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 43 个 XCTest，通过 `git diff --check`、`./script/package_release.sh 1.8.7` 和 `./script/release_smoke_test.sh 1.8.7`。 |
| v1.8.8 | 完成发布 CI 整改第二步：新增无 GUI `ci_release_gate.sh`，在 GitHub Actions PR/push 中构建 release app bundle，验证主 app、Helper、JS worker、第三方清单、Info.plist identity、嵌套 ad-hoc 签名和 zip 内容；manifest 私钥签名仍只在受保护发布环境执行。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/ci_release_gate.sh`、`git diff --check`、`./script/package_release.sh 1.8.8` 和 `./script/release_smoke_test.sh 1.8.8`。 |
| v1.8.9 | 完成 AppKit bridge 可访问性整改：`NSTableView` 按列提供 VoiceOver label/help，详情表支持 Return/Enter/Space 激活选中行；日志 `NSTextView` 显式声明只读 text-area role、标签与复制帮助文本。新增 AppKit 层回归测试。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 45 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.9` 和 `./script/release_smoke_test.sh 1.8.9`。 |
| v1.8.10 | 完成可维护性整改第一批：将 `AdvancedServices.swift` 中的 `ConfigFragmentStore` 拆入 `ConfigFragmentStore.swift`，将 `ManagedCoreManager`、`ExternalUIManager`、`GeoUpdateManager` 拆入 `ArtifactInstallers.swift`；证书 pinning、backup/restore 与诊断脱敏保留在原服务文件。仅调整文件边界，不改变调用 API 或行为。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 45 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.10` 和 `./script/release_smoke_test.sh 1.8.10`。 |
| v1.8.11 | 完成可维护性整改第二批：将持久化 `AppSettings` 移入 `SettingsModels.swift`，将 Config fragment、Provider、Profile 质量、策略、连接、日志和诊断展示模型移入 `ProfileAndRuntimeModels.swift`；`AppModels.swift` 只保留导航、网络接管和 `ProfileItem`。仅调整文件边界，保持类型名与 settings JSON Codable schema 不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 45 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.11` 和 `./script/release_smoke_test.sh 1.8.11`。 |
| v1.8.12 | 完成可维护性整改第三批：将本地备份、WebDAV、Gist 的 AppStore 协调方法和持久化恢复辅助方法移入 `AppStore+Backup.swift`；主 Store 保留同名 public API 和 Published 状态，内部继续复用既有 `BackupManager`、`ProfileStore`、`ConfigFragmentStore`。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 45 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.12` 和 `./script/release_smoke_test.sh 1.8.12`。 |
| v1.8.13 | 完成可维护性整改第四批：新增 `AppSettingsCodableTests`，直接锁住 settings JSON round-trip、旧版本缺 checksum 字段 fallback、legacy `managedCoreEnabled` 到 `coreSource` 迁移，以及 `redactedSecretsForDisk` 落盘前移除 Controller/WebDAV/Gist secret 的契约。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.13` 和 `./script/release_smoke_test.sh 1.8.13`。 |
| v1.8.14 | 完成可维护性整改第五批：将 Profile 存储目录切换、远程/本地导入、订阅刷新队列、启用/编辑/删除、统计、质量报告和离线策略组生成移入 `AppStore+Profiles.swift`；主 `AppStore.swift` 降至 2,632 行，外部调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.14` 和 `./script/release_smoke_test.sh 1.8.14`。 |
| v1.8.15 | 完成可维护性整改第六批：将 Controller Provider 刷新/更新、Provider 直接下载、回滚、一键外部资源更新、Geo 数据同步和 Provider 更新历史持久化移入 `AppStore+Resources.swift`；主 `AppStore.swift` 降至 2,347 行，资源页调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.15` 和 `./script/release_smoke_test.sh 1.8.15`。 |
| v1.8.16 | 完成可维护性整改第七批：将系统代理、系统 DNS、TUN 开关/恢复、网络接管状态刷新、网络安全快照和 Helper 网络操作记录移入 `AppStore+NetworkTakeover.swift`；主 `AppStore.swift` 降至 2,049 行，网络安全中心调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.16` 和 `./script/release_smoke_test.sh 1.8.16`。 |
| v1.8.17 | 完成可维护性整改第八批：将 core 启停/重启、Controller 刷新、连接关闭、LaunchDaemon 安装卸载、managed core 状态、shutdown、Controller WebSocket 事件流和流量速率采样移入 `AppStore+CoreLifecycle.swift`；主 `AppStore.swift` 降至 1,578 行，核心控制调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.17` 和 `./script/release_smoke_test.sh 1.8.17`。 |
| v1.8.18 | 完成可维护性整改第九批：将配置预览生成、禁用规则持久化、Profile 规则增删改、配置片段保存和规则/Provider 命中统计移入 `AppStore+ConfigEditing.swift`；主 `AppStore.swift` 降至 1,365 行，规则页、配置片段窗口和资源/策略页调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.18` 和 `./script/release_smoke_test.sh 1.8.18`。 |
| v1.8.19 | 完成可维护性整改第十批：将诊断运行、诊断包导出、日志追加/暂停/清空、日志落盘/轮转/保留清理和 Helper 诊断提示移入 `AppStore+Diagnostics.swift`；主 `AppStore.swift` 降至 947 行，诊断页、网络安全页、日志页和菜单栏调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.19` 和 `./script/release_smoke_test.sh 1.8.19`。 |
| v1.8.20 | 完成可维护性整改第十一批：将模式切换、策略选择、单节点/分组/全量延迟测试、DIRECT 直连兜底测速、失败原因归类和测速结果回写移入 `AppStore+PolicyTesting.swift`；主 `AppStore.swift` 降至 640 行，策略页、菜单栏和主工具栏调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.20` 和 `./script/release_smoke_test.sh 1.8.20`。 |
| v1.8.21 | 完成可维护性整改第十二批：将 managed core 安装、External UI 安装、Geo 更新入口、Age 工具安装、Age identity 生成和 Profile 加密迁移移入 `AppStore+AdvancedArtifacts.swift`；主 `AppStore.swift` 降至 537 行，高级页、设置页和菜单栏调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.21` 和 `./script/release_smoke_test.sh 1.8.21`。 |
| v1.8.22 | 完成可维护性整改第十三批：将当前版本展示、更新源描述、GitHub Release 检查和应用内更新安装协调移入 `AppStore+SoftwareUpdates.swift`；主 `AppStore.swift` 降至 464 行，设置页、菜单栏、更新窗口和诊断包摘要调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.22` 和 `./script/release_smoke_test.sh 1.8.22`。 |
| v1.8.23 | 完成可维护性整改第十四批：将 Helper 状态刷新、本地审计、注册、卸载和修复注册协调移入 `AppStore+HelperManagement.swift`；主 `AppStore.swift` 降至 384 行，高级页和诊断页调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.23` 和 `./script/release_smoke_test.sh 1.8.23`。 |
| v1.8.24 | 完成可维护性整改第十五批：将 `mihomo://` Profile 导入和覆写片段导入协调移入 `AppStore+DeepLinks.swift`；主 `AppStore.swift` 降至 338 行，App URL 入口调用 API 保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.24` 和 `./script/release_smoke_test.sh 1.8.24`。 |
| v1.8.25 | 完成可维护性整改第十六批：将设置 schema 迁移、legacy `managedCoreEnabled` 同步、迁移失败回滚和迁移日志移入 `AppStore+SettingsMigration.swift`；主 `AppStore.swift` 降至 308 行，bootstrap 加载流程保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.25` 和 `./script/release_smoke_test.sh 1.8.25`。 |
| v1.8.26 | 完成可维护性整改第十七批：将 `ProfileQualityAnalyzer` 的规则校验、Profile 健康检查、Runtime schema 校验和 YAML normalization/summary helper 拆入 `ProfileQualityAnalyzer+Validation.swift` 与 `ProfileQualityAnalyzer+YAML.swift`；主 analyzer 降至 344 行，`analyze(...)` 与 `validateRule(...)` 调用面保持不变。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.26` 和 `./script/release_smoke_test.sh 1.8.26`。 |
| v1.8.27 | 完成可维护性整改第十八批：将 Profiles 页的配置质量评分、问题列表、Runtime Inspector、分层 Diff 和字段来源表拆入 `ProfileQualityPane.swift`；`ProfilesView.swift` 降至 505 行，父视图仅保留 Profile 列表、导入、摘要和覆写入口组合。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.27` 和 `./script/release_smoke_test.sh 1.8.27`。 |
| v1.8.28 | 完成可维护性整改第十九批：将 Profiles 页的 URL 导入 sheet、订阅刷新队列条、Profile 摘要 pane、覆写摘要 pane 和小型指标组件拆入 `ProfileSupportingPanes.swift`；`ProfilesView.swift` 降至 295 行，页面主文件聚焦存储路径、列表、详情组合和导入/drop 动作。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.28` 和 `./script/release_smoke_test.sh 1.8.28`。 |
| v1.8.29 | 完成可维护性整改第二十批：将策略页的 `PolicyNodeRow`、策略组列表/图标、状态条、启动空态、搜索空态和启动事实组件拆入 `PolicySupportingViews.swift`；`PoliciesView.swift` 降至 350 行，主文件聚焦策略搜索、选择、测速和节点应用流程。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.29` 和 `./script/release_smoke_test.sh 1.8.29`。 |
| v1.8.30 | 完成可维护性整改第二十一批：将高级页的 Profile 加密/Age 工具、External UI 安装、配置预览/Diff 和 Geo 数据更新 panes 拆入 `AdvancedArtifactPanes.swift`；`AdvancedView.swift` 降至 372 行，主文件继续保留 Helper、Controller、DNS、Sniffer、备份和深链入口组合。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.30` 和 `./script/release_smoke_test.sh 1.8.30`。 |
| v1.8.31 | 完成可维护性整改第二十二批：将资源页的 `ExternalResourceRow`、资源状态 enum、资源计数 badge、Provider 更新历史面板和历史行拆入 `ResourceSupportingViews.swift`；`ResourcesView.swift` 降至 249 行，主文件聚焦 Provider/Geo 资源筛选、表格、更新、回滚和 Controller 刷新动作。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.31` 和 `./script/release_smoke_test.sh 1.8.31`。 |
| v1.8.32 | 完成可维护性整改第二十三批：将设置页 tab、Controller 设置、网络接管设置、常驻/日志/软件更新 pane 和通用 `SettingsSection`/`SettingsRow`/`SettingsToggleRow` 拆入 `SettingsSupportingViews.swift`；`SettingsRootView.swift` 降至 240 行，主文件保留设置窗口布局、核心设置、保存栏和本地 core 文件选择。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 49 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.32` 和 `./script/release_smoke_test.sh 1.8.32`。 |
| v1.8.33 | 完成发布/更新稳定性整改：将 `SoftwareUpdateManager` 的下载后包校验抽成安装前验证边界，只有 SHA-256、zip 解包、`Mihomo.app` 定位、bundle id/version/signing 校验全部通过后才写入安装脚本并启动替换；新增坏 hash、缺 app、bundle id 不匹配均不进入安装脚本的 XCTest。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 52 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.33` 和 `./script/release_smoke_test.sh 1.8.33`。 |
| v1.8.34 | 完成更新安装脚本回滚修复：`install-update.sh` 增加统一 `restore_backup` 分支，`ditto` 复制失败和替换后 codesign 验证失败都会恢复 `.previous-update`；新增临时 app 执行脚本的 XCTest，验证候选 app 缺失导致复制失败时旧 app marker 仍被恢复。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 53 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.34` 和 `./script/release_smoke_test.sh 1.8.34`。 |
| v1.8.35 | 完成 Controller WebSocket 稳定性测试补强：抽出 `ControllerEventStreamRecoveryState`，让事件流断线后的“首连失败保留轮询、已有实时事件后降级、成功事件重置失败计数、重连退避 12 秒封顶”变成独立可测策略；`AppStore` 事件流循环复用同一状态机。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 56 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.35` 和 `./script/release_smoke_test.sh 1.8.35`。 |
| v1.8.36 | 完成 Provider 回滚边界测试补强：新增缺失备份回滚失败时保留当前 Provider 文件的测试，并覆盖 `latestProviderRollbackRecord` 会跳过已被清理的历史 backup path、选择最近仍存在的备份，降低资源页手动回滚误选失效记录的风险。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 58 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.36` 和 `./script/release_smoke_test.sh 1.8.36`。 |
| v1.8.37 | 完成更新安装脚本签名失败回滚测试：新增临时 app 执行 `install-update.sh` 的 XCTest，构造可复制但未签名的候选 app，验证 `ditto` 成功后 `codesign --verify` 失败会恢复旧 app marker，并清理 `.previous-update`。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 59 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.37` 和 `./script/release_smoke_test.sh 1.8.37`。 |
| v1.8.38 | 完成 release manifest 签名门禁补强：`sign_update_manifest.swift` 增加无私钥 `--verify` 模式，按 App 同样的 canonical JSON 规则移除 `signature` 后验 Ed25519；`release_smoke_test.sh` 不再只检查签名字段和 public key，而是对版本 manifest 做真实签名验证。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 59 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.38` 和 `./script/release_smoke_test.sh 1.8.38`。 |
| v1.8.39 | 完成 release manifest 篡改负向门禁：`release_smoke_test.sh` 会复制版本 manifest、用 `jq` 修改 `notes` 字段，再断言 `sign_update_manifest.swift --verify` 必须失败，证明 smoke 能捕获签名后 manifest 被改动的场景。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 59 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.39` 和 `./script/release_smoke_test.sh 1.8.39`。 |
| v1.8.40 | 完成 release identity gate：新增 `script/verify_release_identity.sh`，默认校验 app/Helper/JS worker 的 bundle id、codesign identifier 和严格签名；受保护发布机设置 `MIHOMO_EXPECTED_TEAM_ID`、`MIHOMO_REQUIRE_DEVELOPER_ID=1`、`MIHOMO_REQUIRE_NOTARIZATION=1`、`MIHOMO_REQUIRE_STAPLED_TICKET=1` 后会强制 Team ID/designated requirement、Developer ID、Gatekeeper 和 stapled ticket 验证。`build_and_run.sh` 同步支持 `MIHOMO_CODESIGN_IDENTITY` 和 runtime options。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 59 个 XCTest，通过 `git diff --check`、`./script/verify_release_identity.sh dist/Mihomo.app`、错误 `MIHOMO_EXPECTED_TEAM_ID` 负向验证、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.40` 和 `./script/release_smoke_test.sh 1.8.40`。 |
| v1.8.41 | 完成真实系统网络接管 smoke 证据采集入口：新增 `script/network_takeover_smoke.sh`，默认只读生成 `dist/smoke/network-takeover-*.md`，记录 network services、HTTP/HTTPS/SOCKS proxy、DNS override、默认路由、utun interfaces、route tables、resolver state 和 Mihomo proxy/DNS/TUN recovery snapshots；`--assert-clean` 可在手动开关测试后把残留 proxy、snapshot、TUN route 变成失败。 | 使用 `./script/network_takeover_smoke.sh` 在当前机器生成只读 smoke 报告并通过，通过 `bash -n script/network_takeover_smoke.sh`、`git diff --check`、`DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.41` 和 `./script/release_smoke_test.sh 1.8.41`。 |
| v1.8.42 | 完成更新替换 smoke 补强：新增 `script/update_replacement_smoke.sh`，用真实 release zip 解出候选 `Mihomo.app`，在临时 `Applications` 目录模拟 `.previous-update` 备份、`ditto` 替换、quarantine 清理和 `codesign --verify`，再用坏候选验证失败时恢复当前 app；`release_smoke_test.sh` 已接入该 smoke。 | 使用 `./script/update_replacement_smoke.sh 1.8.41` 和已接入的新 `./script/release_smoke_test.sh 1.8.41` 预验证，通过 `bash -n`、`git diff --check`、`DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.42` 和 `./script/release_smoke_test.sh 1.8.42`。 |
| v1.8.43 | 完成配置 schema 风险检查补强：`ProfileQualityAnalyzer` 增加 DNS resolver scheme、TUN stack、Sniffer force/skip domain 和 Rule Provider behavior 细粒度告警；`ProviderItem` 记录 `behavior` 供 analyzer 使用，并新增 XCTest 覆盖这些风险。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileQualityAnalyzerTests` 验证 4 个 analyzer 测试，通过 `git diff --check`、完整 `swift test`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.43` 和 `./script/release_smoke_test.sh 1.8.43`。 |
| v1.8.44 | 完成 Secret vault 可迁移性补强：`LocalSecretVault` 新增 passphrase-encrypted portable secret bundle 导出/导入，bundle 使用 PBKDF2-HMAC-SHA256 派生密钥和 AES-256-GCM 加密；普通备份继续默认不携带 secret，错误口令导入不会替换现有 vault。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter SoftwareUpdateAndSecretTests` 验证 9 个 Secret/Update 测试，通过完整 `swift test`、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.44`、`./script/release_smoke_test.sh 1.8.44` 和 `./script/update_replacement_smoke.sh 1.8.44`。 |
| v1.8.45 | 完成 Secret bundle 用户入口补强：高级页备份区新增临时口令输入、`导出 Secret Bundle` 和 `导入 Secret Bundle` 操作；导出前保存当前设置以刷新 vault，导入成功后把 secret 应用到当前 settings 并继续通过 redacted settings 保存路径落盘。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 63 个 XCTest，通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.45`、`./script/release_smoke_test.sh 1.8.45` 和 `./script/update_replacement_smoke.sh 1.8.45`。 |
| v1.8.46 | 完成 redacted 备份恢复与 Secret vault 边界修复：`BackupSecretPolicy` 在应用 Gist JSON payload 时会把当前本机 secret 合并回恢复后的 settings，避免普通 redacted payload 误清空 vault；legacy inline-secret payload 仍优先使用 payload 内 secret。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter AppSettingsCodableTests` 验证 6 个 settings/backup policy 测试，通过完整 `swift test` 65 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.46`、`./script/release_smoke_test.sh 1.8.46` 和 `./script/update_replacement_smoke.sh 1.8.46`。 |
| v1.8.47 | 完成更新后 Helper 绑定诊断补强：`MihomoHelper` 的 XPC version payload 回传授权 App bundle path、version 和 build；Helper 审计与诊断页新增“Helper 运行绑定”，当运行中 Helper 仍指向旧 app 或旧 build 时给出 warning。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ControllerAndHelperMockTests` 验证 5 个 Helper/Controller 测试，通过完整 `swift test` 67 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.47`、`./script/release_smoke_test.sh 1.8.47` 和 `./script/update_replacement_smoke.sh 1.8.47`。 |
| v1.8.48 | 完成 analyzer 真实规则错误样本补强：新增常见 mihomo rule type allowlist，拼写可疑的规则类型会被标记；DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、GEOSITE payload 若误填 URL scheme、路径或空白也会提前告警。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileQualityAnalyzerTests` 验证 5 个 analyzer 测试，通过完整 `swift test` 68 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.48`、`./script/release_smoke_test.sh 1.8.48` 和 `./script/update_replacement_smoke.sh 1.8.48`。 |
| v1.8.49 | 完成真实网络接管 smoke 前后比对补强：`network_takeover_smoke.sh` 默认生成 Markdown 报告旁的 TSV summary，并新增 `--summary`、`--baseline` 参数；受控实机测试可先采 baseline，再执行系统代理/DNS/TUN 开关、退出或崩溃恢复，最后用 `--baseline` 与 `--assert-clean` 同时验证状态是否回到测试前且没有残留。 | 使用 `bash -n script/network_takeover_smoke.sh`、`./script/network_takeover_smoke.sh --output dist/smoke/network-takeover-v1.8.49-baseline.md` 和 `./script/network_takeover_smoke.sh --baseline dist/smoke/network-takeover-v1.8.49-baseline.summary.tsv --output dist/smoke/network-takeover-v1.8.49-compare.md` 验证 baseline/compare，通过完整 `swift test` 68 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.49`、`./script/release_smoke_test.sh 1.8.49` 和 `./script/update_replacement_smoke.sh 1.8.49`。 |
| v1.8.50 | 完成更新替换 smoke identity 补强：`update_replacement_smoke.sh` 在临时 Applications 替换成功和坏候选回滚后，除 app bundle id/version/signing 外，还校验 `CFBundleVersion` 与 manifest build 一致，并确认嵌入 `MihomoHelper` 与 `MihomoJSWorker` 存在且签名 identifier 正确。 | 使用 `bash -n script/update_replacement_smoke.sh` 和 `./script/update_replacement_smoke.sh 1.8.49` 预验证，通过完整 `swift test` 68 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.50`、`./script/release_smoke_test.sh 1.8.50` 和 `./script/update_replacement_smoke.sh 1.8.50`；发布包 SHA-256 为 `a47a7ec591571c8f9282a65ae82fc725f01c5db87e83bdf4a8c8f4118b027638`。 |
| v1.8.51 | 完成 analyzer 真实规则 payload 样本补强：`ProfileQualityAnalyzer` 对 `IP-CIDR` / `IP-CIDR6` 地址族混用、域名误填 CIDR、`SRC-PORT` / `DST-PORT` 越界和 `NETWORK` 非 tcp/udp payload 给出预警，减少运行 `mihomo -t` 前才暴露的常见规则错误。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileQualityAnalyzerTests` 验证 6 个 analyzer 测试，通过完整 `swift test` 69 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.51`、`./script/release_smoke_test.sh 1.8.51` 和 `./script/update_replacement_smoke.sh 1.8.51`；发布包 SHA-256 为 `f7a86ba1aba8ef0a508c3dcae40c4ae6ef66911cb5eed160a6bc52d16ffeb7cd`。 |
| v1.8.52 | 完成 analyzer 策略组引用完整性补强：`ProfileQualityAnalyzer` 会检查 `proxy-groups.proxies` 中不存在的节点/策略组，以及 `use` 误引用 Rule Provider 或不存在的 Proxy Provider，让策略组成员和 Provider 类型错误在运行 `mihomo -t` 前暴露。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileQualityAnalyzerTests` 验证 7 个 analyzer 测试，通过完整 `swift test` 70 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.52`、`./script/release_smoke_test.sh 1.8.52` 和 `./script/update_replacement_smoke.sh 1.8.52`；发布包 SHA-256 为 `208fc63e45c0646a41867123fbc667add6f825ba0d5ae47925703c74aa67b47b`。 |
| v1.8.53 | 完成 Secret vault 人工输入恢复补强：高级页备份区新增“应用人工输入 Secret”，用户在 Controller/WebDAV/Gist secret 字段手填凭据后可显式写入本机 vault；`BackupSecretPolicy` 只应用非空手填字段，空字段继续保留当前 vault secret，避免恢复 redacted 备份后误清空凭据。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter AppSettingsCodableTests` 验证 7 个 settings/backup policy 测试，通过完整 `swift test` 71 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.53`、`./script/release_smoke_test.sh 1.8.53` 和 `./script/update_replacement_smoke.sh 1.8.53`；发布包 SHA-256 为 `10acc47e737b80a65bd90eb0e73bdfd6358c8b31a29ad3c224e669bcd8adea31`。 |
| v1.8.54 | 完成 Secret restore wizard 状态补强：新增脱敏 `BackupSecretChecklistItem`，高级页备份区显示 Controller Secret、WebDAV 密码和 Gist Token 的已就绪/缺失状态，帮助用户在 redacted restore 后确认哪些凭据还需要手动补齐，同时不展示 secret 值。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter AppSettingsCodableTests` 验证 8 个 settings/backup policy 测试，通过完整 `swift test` 72 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.54`、`./script/release_smoke_test.sh 1.8.54` 和 `./script/update_replacement_smoke.sh 1.8.54`；发布包 SHA-256 为 `6773a1e518050b5361b744f6fdfe6841beaea38b0f54b102bc896455a3d735e2`。 |
| v1.8.55 | 完成真实网络接管 smoke 场景证据补强：`network_takeover_smoke.sh` 新增 `--scenario` 和可重复 `--note`，Markdown 报告会记录手动演练名称和操作备注；TSV summary 仍只保留可比对的网络状态，避免备注差异干扰 `--baseline` 前后对比。 | 使用 `bash -n script/network_takeover_smoke.sh` 和 `./script/network_takeover_smoke.sh --scenario proxy-dns-tun-manual-evidence --note "baseline capture before manual takeover" --note "no system mutation performed by this smoke" --output dist/smoke/network-takeover-v1.8.55-scenario.md` 验证脚本与报告输出，通过完整 `swift test` 72 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.55`、`./script/release_smoke_test.sh 1.8.55` 和 `./script/update_replacement_smoke.sh 1.8.55`；发布包 SHA-256 为 `2bd42ef20af8eee9fc835883426c078302e07c6a8c3e9ed4675e85a0b9c7d011`。 |
| v1.8.56 | 完成实机辅助功能 QA 证据入口补强：新增只读 `accessibility_qa_checklist.sh`，可通过 `--scenario` 和可重复 `--note` 记录人工检查上下文，并生成覆盖 Overview、Profiles、Policies、Resources、Logs、Diagnostics、Advanced 和 Settings 的 VoiceOver、键盘-only、Accessibility Inspector Markdown 清单。 | 使用 `bash -n script/accessibility_qa_checklist.sh` 和 `./script/accessibility_qa_checklist.sh --scenario voiceover-main-tabs --note "checklist capture before manual VoiceOver pass" --output dist/accessibility/accessibility-qa-v1.8.56.md` 验证脚本与报告输出，打包后清单记录 `Version 1.8.56`；通过完整 `swift test` 72 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.56`、`./script/release_smoke_test.sh 1.8.56` 和 `./script/update_replacement_smoke.sh 1.8.56`；发布包 SHA-256 为 `2d8063db00cafa77599cd585d7eb853be338ed407f3bbc7ae297f1b89ef692b3`。 |
| v1.8.57 | 完成 analyzer 真实规则 payload 样本补强：`ProfileQualityAnalyzer` 继续覆盖 SRC-IP-CIDR/SRC-IP-CIDR6 地址格式、GEOIP payload URL/path 误填、IP-ASN 非数字 ASN、PROCESS-NAME 误填路径和 PROCESS-PATH 误填进程名等常见配置错误。 | 使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileQualityAnalyzerTests` 验证 8 个 analyzer 测试，通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.57`、`./script/release_smoke_test.sh 1.8.57` 和 `./script/update_replacement_smoke.sh 1.8.57`；发布包 SHA-256 为 `bdb7d6e92a1fc8d44655a13320e440b5da157658c7e7df9264834cd681d673fc`。 |
| v1.8.58 | 完成受保护发布环境 checklist 补强：新增只读 `protected_release_checklist.sh`，可用 `--version`、`--scenario` 和可重复 `--note` 生成 Developer ID、Team ID、notarytool、stapler、manifest 私钥和 release gate 环境 readiness 报告，并附受保护发布机命令模板。 | 使用 `bash -n script/protected_release_checklist.sh` 和 `./script/protected_release_checklist.sh --version 1.8.58 --scenario developer-id-notarization-dry-run --note "readiness capture without protected credentials" --output dist/release-checks/protected-release-v1.8.58.md` 验证脚本与报告输出，通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.58`、`./script/release_smoke_test.sh 1.8.58` 和 `./script/update_replacement_smoke.sh 1.8.58`；发布包 SHA-256 为 `3b4bc8dd8a93a029555f3013f1cc41d1fca86e3046f39a3d7244c00dc867b4cf`。 |
| v1.8.59 | 完成真实网络接管 smoke 阶段证据补强：`network_takeover_smoke.sh` 新增 `--phase`，可把 before、enabled、after-stop、after-quit、after-crash、recovered 等人工演练阶段写入 Markdown header 和 Manual Scenario Notes；TSV summary 继续只保留可比对网络状态，避免阶段标签干扰 baseline diff。 | 使用 `bash -n script/network_takeover_smoke.sh` 和 `./script/network_takeover_smoke.sh --scenario proxy-dns-tun-manual-evidence --phase before --note "phase metadata capture without system mutation" --output dist/smoke/network-takeover-v1.8.59-phase.md` 验证脚本与报告输出；当前机器仍有系统代理和 snapshot 残留，因此未运行 `--assert-clean`；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.59`、`./script/release_smoke_test.sh 1.8.59` 和 `./script/update_replacement_smoke.sh 1.8.59`；发布包 SHA-256 为 `6639acb6b058d3d1e235ea41d8810621ce88e2ab9e687f8b7b9c088200999637`。 |
| v1.8.60 | 完成发布 artifact provenance 摘要补强：新增只读 `release_provenance_report.sh`，记录 release zip、version/latest manifest、Package.resolved、THIRD_PARTY_NOTICES 的 SHA-256，manifest 字段和 Ed25519 验签状态，App/Helper/JS worker/core 签名摘要，以及 zip 关键条目；`release_smoke_test.sh` 通过后会自动生成 `Mihomo-<version>-provenance.md`。 | 使用 `bash -n script/release_provenance_report.sh`、`bash -n script/release_smoke_test.sh` 和 `./script/release_provenance_report.sh 1.8.59 --output dist/releases/Mihomo-1.8.59-provenance.md` 验证脚本与报告输出；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.60`、`./script/release_smoke_test.sh 1.8.60` 和 `./script/update_replacement_smoke.sh 1.8.60`；`dist/releases/Mihomo-1.8.60-provenance.md` 已记录 zip SHA、manifest parity、签名摘要和关键 zip entries；发布包 SHA-256 为 `04aa6f5072b3d53226201cdb88455b1f558c9cdfab328c2bb683ba9f6a4c39c1`。 |
| v1.8.61 | 完成维护性文件大小阈值报告补强：新增只读 `maintainability_audit.sh`，默认扫描 `Sources` 和 `Tests` 的 Swift 文件，按 350 行 warning、500 行 over-max 输出 Markdown 和 TSV；`ci_release_gate.sh` 会非阻塞生成 `dist/ci/maintainability.md`，让大型文件回归风险在 CI/release gate 中可见。 | 使用 `bash -n script/maintainability_audit.sh`、`bash -n script/ci_release_gate.sh` 和 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.61.md --summary dist/maintainability/maintainability-v1.8.61.summary.tsv` 验证脚本与报告输出；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.61`、`./script/release_smoke_test.sh 1.8.61` 和 `./script/update_replacement_smoke.sh 1.8.61`；`dist/ci/maintainability.md` 记录 100 个 Swift 文件、12 个 warning 文件和 1 个 over-max 文件；发布包 SHA-256 为 `0b42418ec05768f8215b58a9314321bbdd0f9d2c6b9cabae8d83007a974e5785`。 |
| v1.8.62 | 完成维护性 over-max 文件拆分：将 `ProfileQualityAnalyzer+Validation.swift` 中的 validator helper/predicate 函数拆入 `ProfileQualityAnalyzer+ValidationHelpers.swift`，主 validation 文件从 636 行降至 461 行，新增 helper 文件 179 行；maintainability audit 的 over-max 文件从 1 个降为 0 个，剩余 13 个 warning 文件继续跟踪。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.62.md --summary dist/maintainability/maintainability-v1.8.62.summary.tsv` 验证 101 个 Swift 文件、0 个 over-max 文件；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileQualityAnalyzerTests` 验证 8 个 analyzer 测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.62`、`./script/release_smoke_test.sh 1.8.62` 和 `./script/update_replacement_smoke.sh 1.8.62`；发布包 SHA-256 为 `c1ee2f9bd27fdbe44ff4beee982a2c7507446580fda38e5c6c23cb3816f72943`。 |
| v1.8.63 | 完成维护性 warning 文件拆分：将 Controller WebSocket event stream、流量速率采样、traffic sample 保留和 controller polling interval 协调从 `AppStore+CoreLifecycle.swift` 拆入 `AppStore+ControllerStreams.swift`；`AppStore+CoreLifecycle.swift` 从 476 行降至 329 行，新增 stream extension 150 行；maintainability audit 的 warning 文件从 13 个降为 12 个，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.63.md --summary dist/maintainability/maintainability-v1.8.63.summary.tsv` 验证 102 个 Swift 文件、12 个 warning 文件、0 个 over-max 文件，最大文件为 `ProfileQualityAnalyzer+Validation.swift` 461 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ControllerEventStreamTests` 验证 6 个 controller event stream 测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.63`、`./script/release_smoke_test.sh 1.8.63` 和 `./script/update_replacement_smoke.sh 1.8.63`；`dist/releases/Mihomo-1.8.63-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `828decb7915a159de72c8240dcb9a12241b9b27bd6701aedf10c6b752476ec7f`。 |
| v1.8.64 | 完成维护性 warning 文件继续拆分：将单条规则类型、payload、CIDR、端口、GEOIP、IP-ASN、PROCESS 和 NETWORK payload sanity checks 从 `ProfileQualityAnalyzer+Validation.swift` 拆入 `ProfileQualityAnalyzer+RuleValidation.swift`；主 validation 文件从 461 行降至 302 行，新增 rule validation extension 162 行；maintainability audit 的 warning 文件从 12 个降为 11 个，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.64.md --summary dist/maintainability/maintainability-v1.8.64.summary.tsv` 验证 103 个 Swift 文件、11 个 warning 文件、0 个 over-max 文件，最大文件为 `AdvancedView.swift` 444 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileQualityAnalyzerTests` 验证 8 个 analyzer 测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.64`、`./script/release_smoke_test.sh 1.8.64` 和 `./script/update_replacement_smoke.sh 1.8.64`；`dist/releases/Mihomo-1.8.64-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `52c32b73189277ca7fe05696a906f6864afaea72a71a5b9624049bf66ae554ae`。 |
| v1.8.65 | 完成高级页维护性拆分：将备份/同步、WebDAV/Gist secret checklist、人工 Secret 写回、Secret Bundle 导入导出和本地备份文件面板从 `AdvancedView.swift` 拆入 `AdvancedBackupGroup.swift`；`AdvancedView.swift` 从 444 行降至 276 行，新增备份面板 203 行；maintainability audit 的 warning 文件从 11 个降为 10 个，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.65.md --summary dist/maintainability/maintainability-v1.8.65.summary.tsv` 验证 104 个 Swift 文件、10 个 warning 文件、0 个 over-max 文件，最大文件为 `AdvancedServices.swift` 424 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter AppSettingsCodableTests` 验证 8 个 settings/secret 测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.65`、`./script/release_smoke_test.sh 1.8.65` 和 `./script/update_replacement_smoke.sh 1.8.65`；`dist/releases/Mihomo-1.8.65-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `b3ee9a8145a01082b9f1329e7419795dd4c6e5dddc41dda746e13de111247073`。 |
| v1.8.66 | 完成高级服务维护性拆分：将证书 pinning session 从 `AdvancedServices.swift` 拆入 `CertificatePinningSession.swift`，将诊断脱敏器拆入 `DiagnosticRedactor.swift`；`AdvancedServices.swift` 从 424 行降至 298 行，新增证书 pinning 文件 70 行、诊断脱敏文件 58 行；maintainability audit 的 warning 文件从 10 个降为 9 个，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.66.md --summary dist/maintainability/maintainability-v1.8.66.summary.tsv` 验证 106 个 Swift 文件、9 个 warning 文件、0 个 over-max 文件，最大文件为 `AppStore+Diagnostics.swift` 423 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter BackupAndDiagnosticSecurityTests` 验证 6 个备份/诊断安全测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.66`、`./script/release_smoke_test.sh 1.8.66` 和 `./script/update_replacement_smoke.sh 1.8.66`；`dist/releases/Mihomo-1.8.66-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `f91ebfd7e13489e8dac42f460e3fda8211d5c4afaa08310a6818d105561103e1`。 |
| v1.8.67 | 完成诊断与日志维护性拆分：将日志追加、暂停/恢复、可见日志清空、缓冲 flush、日志落盘、轮转和保留清理从 `AppStore+Diagnostics.swift` 拆入 `AppStore+Logging.swift`；`AppStore+Diagnostics.swift` 从 423 行降至 303 行，新增日志 extension 123 行；maintainability audit 的 warning 文件从 9 个降为 8 个，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.67.md --summary dist/maintainability/maintainability-v1.8.67.summary.tsv` 验证 107 个 Swift 文件、8 个 warning 文件、0 个 over-max 文件，最大文件为 `ProfileStructureEditorView.swift` 399 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter AppKitAccessibilityTests` 验证 2 个 AppKit bridge 测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.67`、`./script/release_smoke_test.sh 1.8.67` 和 `./script/update_replacement_smoke.sh 1.8.67`；`dist/releases/Mihomo-1.8.67-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `cf9cd530aa0d3ea6f0f3e8d7954ec014746fdc4bba8c1e27d7036214d21efe1d`。 |
| v1.8.68 | 完成 Profile 结构编辑器维护性拆分：将规则列表、规则编辑表单、规则目标 Picker 和规则增删改按钮从 `ProfileStructureEditorView.swift` 拆入 `ProfileStructureRuleEditorView.swift`；主结构编辑器从 399 行降至 321 行，新增规则面板 extension 81 行；maintainability audit 的 warning 文件从 8 个降为 7 个，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.68.md --summary dist/maintainability/maintainability-v1.8.68.summary.tsv` 验证 108 个 Swift 文件、7 个 warning 文件、0 个 over-max 文件，最大文件为 `RulesView.swift` 391 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileYAMLStructureEditorTests` 验证 2 个 Profile YAML 结构编辑测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.68`、`./script/release_smoke_test.sh 1.8.68` 和 `./script/update_replacement_smoke.sh 1.8.68`；`dist/releases/Mihomo-1.8.68-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `941ecb025cc4e48ab941805109d2180a1d47cd5acf84dd9e60923c6e437def6b`。 |
| v1.8.69 | 完成规则页维护性拆分：将规则编辑 sheet 从 `RulesView.swift` 拆入 `RuleEditorSheet.swift`；`RulesView.swift` 从 391 行降至 324 行，新增 sheet 68 行；maintainability audit warning 7 -> 6，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.69.md --summary dist/maintainability/maintainability-v1.8.69.summary.tsv` 验证 109 个 Swift 文件、6 个 warning 文件、0 个 over-max 文件，最大文件为 `ActivityView.swift` 387 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter ProfileYAMLStructureEditorTests` 验证 2 个 Profile YAML 结构编辑测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.69`、`./script/release_smoke_test.sh 1.8.69` 和 `./script/update_replacement_smoke.sh 1.8.69`；`dist/releases/Mihomo-1.8.69-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `073b88d3b5c37806340f12e769a3686e401ade490501dd0ebc30a6e16f53d4d5`。 |
| v1.8.70 | 完成活动页维护性拆分：将连接详情窗口、tab、inspector、流量 tile 和详情行从 `ActivityView.swift` 拆入 `ConnectionDetailPanelView.swift`；`ActivityView.swift` 从 387 行降至 223 行，新增详情窗口文件 165 行；maintainability audit warning 6 -> 5，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.70.md --summary dist/maintainability/maintainability-v1.8.70.summary.tsv` 验证 110 个 Swift 文件、5 个 warning 文件、0 个 over-max 文件，最大文件为 `HelperNetworkTools.swift` 384 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter AppKitAccessibilityTests` 验证 2 个 AppKit bridge 测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.70`、`./script/release_smoke_test.sh 1.8.70` 和 `./script/update_replacement_smoke.sh 1.8.70`；`dist/releases/Mihomo-1.8.70-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `fbb42730294497ee6eb1cb39c5002e905f6eb8896450b1aa9e896763e04741db`。 |
| v1.8.71 | 完成 Helper 网络工具维护性拆分：将 TUN recovery 路由快照、默认路由恢复、utun 新增路由筛选和回滚描述从 `HelperNetworkTools.swift` 拆入 `HelperTunRecoveryTool.swift`；`HelperNetworkTools.swift` 从 384 行降至 222 行，新增 TUN recovery 文件 163 行；maintainability audit warning 5 -> 4，over-max 继续为 0 个。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.71.md --summary dist/maintainability/maintainability-v1.8.71.summary.tsv` 验证 111 个 Swift 文件、4 个 warning 文件、0 个 over-max 文件，最大文件为 `HelperService.swift` 374 行；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test --filter HelperPathPolicyTests` 验证 6 个 Helper path/snapshot 测试；通过完整 `swift test` 73 个 XCTest、`git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.71`、`./script/release_smoke_test.sh 1.8.71` 和 `./script/update_replacement_smoke.sh 1.8.71`；`dist/releases/Mihomo-1.8.71-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `58da8bd78337549c9c5c65ed17e62f85c93453425ff55423a0a3da8364700fad`。 |
| v1.8.72 | 完成参考图 UI refresh：全局日志菜单移入标题右侧并加宽；新增 ClashMac 风格 `MihomoSidebarView` 和概览 dashboard helper；活动页收敛为单一连接表格面板并复用无边框 `AppKitTable`。maintainability audit 维持 113 个 Swift 文件、4 个 warning 文件、0 个 over-max 文件，最大文件为 `HelperService.swift` 374 行。 | 使用 `./script/maintainability_audit.sh --output dist/maintainability/maintainability-v1.8.72.md --summary dist/maintainability/maintainability-v1.8.72.summary.tsv` 验证维护性报告；使用 `DEVELOPER_DIR="/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer" swift test` 验证 73 个 XCTest；通过 `git diff --check`、`./script/ci_release_gate.sh`、`./script/package_release.sh 1.8.72`、`./script/release_smoke_test.sh 1.8.72` 和 `./script/update_replacement_smoke.sh 1.8.72`；`dist/releases/Mihomo-1.8.72-provenance.md` 已记录 manifest 验签和 artifact checksums；发布包 SHA-256 为 `d92723f8ae62c655d250d177b5d33bcc7c9422257b96247c0db8cc219dda9465`。 |

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

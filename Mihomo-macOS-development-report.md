# Mihomo macOS 原生客户端软件开发报告

生成日期：2026-07-05  
目标：设计一款 macOS 原生 UI 的 mihomo 客户端，功能参考 Sparkle 但不照搬，界面风格参考本机 Surge 6.7.0 的专业网络工具体验。

## 1. 参考对象与学习结论

| 对象 | 本次检查依据 | 关键结论 |
| --- | --- | --- |
| `xishang0128/sparkle` | `d561e27739771251e682afef4384524f33718cb2`，Electron + React + TypeScript | 功能面完整，覆盖订阅、代理组、规则、连接、日志、TUN、DNS、嗅探、覆写、Sub-Store、备份、更新、托盘、轻量模式。适合作为功能参考，不适合作为 macOS 原生 UI 的架构模板。 |
| `UruhaLushia/sparkle-service` | `5acde12bde599553ffa3a95179897da60aaaf8a5`，Go service | 清晰承担特权能力：核心进程托管、系统代理、DNS、服务启停、事件推送、安全认证。macOS 版本建议借鉴职责划分，但使用更原生的 Helper/XPC/LaunchDaemon 方案。 |
| 本机 Surge | `/Applications/Surge.app`，版本 6.7.0 | UI 是原生 macOS 专业工具风格：Sidebar、Toolbar、Split View、Table、Inspector、Popover、状态卡片、菜单栏状态项，强调状态、开关、诊断、列表，而非装饰性页面。 |

两套 Sparkle 参考仓库均为 GPL-3.0。若直接复制、修改或链接分发相关代码，需要提前处理 GPL 开源义务。建议本项目仅吸收产品能力和架构思想，重新实现 Swift/SwiftUI 代码与 macOS 原生交互。

## 2. 产品定位

建议定位为“面向 macOS 用户的专业 mihomo 控制台”。核心差异不是堆功能，而是把 mihomo 的复杂配置收敛为可理解、可诊断、可恢复的原生体验。

目标用户：

- 需要长期运行代理/TUN 的 macOS 用户。
- 使用多个订阅、策略组、规则集、DNS/TUN 配置的进阶用户。
- 希望接近 Surge 信息密度，但底层使用 mihomo 的用户。

产品原则：

- 原生优先：SwiftUI + AppKit，使用系统 Sidebar、Toolbar、Table、Settings、Menu Bar Extra、Notifications。
- 状态优先：主界面第一屏展示接管状态、核心状态、当前 Profile、出站模式、实时流量、连接数。
- 可恢复：核心、系统代理、DNS、TUN 任一环节失败时，要能一键诊断和回滚。
- 不照搬 Sparkle：功能可参考，信息架构、交互、代码实现、视觉语言重新设计。

## 3. 推荐技术架构

```mermaid
flowchart LR
  A["macOS App<br/>SwiftUI + AppKit"] --> B["App Services<br/>Profile / Config / Controller"]
  B --> C["mihomo Controller<br/>Unix Socket / localhost"]
  B --> D["Privileged Helper<br/>SMAppService / LaunchDaemon"]
  D --> E["mihomo Core Process"]
  D --> F["System Proxy / DNS / TUN Privilege"]
  B --> G["Local Storage<br/>YAML / SQLite / Secret Vault"]
  B --> H["Subscription / Provider Updater"]
  A --> I["Menu Bar Extra<br/>Status / Quick Switch"]
```

建议模块：

| 模块 | 职责 | 建议实现 |
| --- | --- | --- |
| macOS 主 App | UI、状态展示、用户操作、偏好设置 | SwiftUI 为主，AppKit 承接 NSTableView、NSStatusItem、窗口细节 |
| Core Manager | 生成运行配置、启动/停止 mihomo、连接 controller | Swift service 层，必要时委托 Helper |
| Privileged Helper | TUN、DNS、系统代理、核心进程托管、权限修复 | SMAppService 注册 helper，XPC 或本地 Unix Socket 通信 |
| Profile Store | 订阅、本地配置、覆写片段、当前配置 | YAML 文件 + SQLite 元数据，敏感信息放本机加密 Secret Vault |
| Controller API | `/proxies`、`/rules`、`/connections`、`/traffic`、`/logs` 等 | 封装为 typed client，UI 不直接拼 API |
| Event Bus | 流量、连接、日志、核心事件、系统代理状态 | Combine / AsyncSequence |
| Updater | mihomo core、Geo 数据、外部资源更新 | 独立任务队列，支持失败重试 |

## 4. Surge 风格的 macOS 原生界面建议

主窗口建议采用三栏/两栏自适应结构：

| 区域 | 设计建议 |
| --- | --- |
| Sidebar | 固定主分区：概览、活动、策略、规则、Profile、资源、DNS、日志、设置。避免 Sparkle 那种卡片式导航，改为原生列表与分组。 |
| Toolbar | 放置核心开关、系统代理/TUN 状态、出站模式、当前 Profile、快速诊断按钮。 |
| Content | 使用 Table、Outline、Form、Split View。代理组、规则、连接都应是高密度可排序列表。 |
| Inspector | 选中连接、规则、代理节点时显示详情、延迟、链路、进程、最近日志。 |
| Menu Bar | 显示上下行速率、当前策略/模式；提供启停、切换 Profile、切换出站模式、打开窗口、退出。 |
| Settings | 使用 macOS Settings Scene：通用、内核、网络接管、订阅、更新、备份、高级。 |

视觉基调：

- 使用系统材质、系统颜色、SF Symbols、标准控件。
- 表格和列表优先，卡片只用于概览状态块或重复资源项。
- 重要状态用短文本 + 色点/图标，例如 Running、System Proxy On、TUN On、Controller Connected。
- 避免大面积渐变、营销式首页和 Web UI 组件感。

## 5. 功能候选表

优先级说明：P0 为 MVP 必需，P1 为首版强烈建议，P2 为进阶功能，P3 为可后置或插件化。

| 选择 | 功能 | 参考来源 | 建议设计 | 优先级 | 复杂度 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| 待选 | mihomo 内置核心 | Sparkle 内置 stable/alpha core | App Bundle 携带 stable core，alpha 作为高级更新通道 | P0 | 中 | 分发时注意 mihomo 许可证与签名。 |
| 待选 | 使用系统 mihomo | Sparkle `system` core | 设置页选择外部二进制，启动前校验版本和权限 | P1 | 中 | 适合高级用户。 |
| 待选 | 核心启动/停止/重启 | Sparkle Core Manager / service | Toolbar 与菜单栏提供主开关，失败时进入诊断页 | P0 | 中 | 要保存启动日志和最近错误。 |
| 待选 | Helper 托管核心 | sparkle-service | 用原生 Helper/LaunchDaemon 管理特权启动和崩溃恢复 | P1 | 高 | macOS 上比普通提权更稳定。 |
| 待选 | 系统代理开关 | Sparkle sysproxy / Surge 概览 | 概览与菜单栏均可启停，显示当前网络服务状态 | P0 | 中 | 需支持恢复用户原设置。 |
| 待选 | TUN 模式 | Sparkle TUN | 设置页配置，概览页只显示开关和健康状态 | P0 | 高 | 权限、路由、DNS 回滚是重点。 |
| 待选 | 出站模式切换 | Sparkle outbound switcher / Surge 活动页 | Rule / Global / Direct 三段式控件 | P0 | 低 | 与 mihomo `mode` 对齐。 |
| 待选 | Profile 管理 | Sparkle Profiles | 原生列表 + 编辑器，支持本地/远程/拖入导入 | P0 | 中 | 首版不必完全复制高级字段。 |
| 待选 | 订阅自动更新 | Sparkle profile updater | 每 Profile 设置更新周期、失败通知、手动刷新 | P1 | 中 | 任务队列化，避免 UI 卡顿。 |
| 待选 | 订阅流量信息 | Sparkle 解析 `subscription-userinfo` | Profile 列表显示用量、到期、更新时间 | P1 | 低 | 需要兼容不同机场头格式。 |
| 待选 | 证书指纹校验 | Sparkle remote profile | 远程 Profile 可选 pinning | P2 | 中 | 安全高级项，默认隐藏。 |
| 待选 | Age 加密 Profile | Sparkle profile encryption | 敏感配置加密存储，密钥走 Secret Vault 或未来稳定签名后的 Keychain | P2 | 中 | 可简化为“加密本地配置”。 |
| 待选 | 运行配置生成 | Sparkle factory merge | 订阅 + 控制配置 + 片段合成 runtime config | P0 | 高 | 这是稳定性的核心。 |
| 待选 | YAML 覆写片段 | Sparkle override YAML | 以“配置片段”形式管理，支持预览 diff | P1 | 中 | 比脚本覆写更安全。 |
| 待选 | JS 脚本覆写 | Sparkle override JS | 作为高级实验功能，默认关闭，沙盒运行 | P3 | 高 | 风险高，建议后置。 |
| 待选 | 配置预览/Diff | Sparkle raw/current/override/runtime views | 显示原始、合并后、最终运行配置，可导出 | P1 | 中 | 对排错很有价值。 |
| 待选 | 策略组管理 | Sparkle Proxies / Surge Proxy | 分组列表 + 节点表格 + 搜索 + 延迟排序 | P0 | 中 | 首版核心体验。 |
| 待选 | 节点延迟测试 | Sparkle group/proxy delay | 单节点、单组、全部并发测试，可配置 URL 和并发 | P0 | 中 | 需限制并发，避免压垮 controller。 |
| 待选 | 自动关闭连接 | Sparkle 切换策略后 close connections | 切换节点时可选择关闭相关连接 | P1 | 低 | 放在设置中。 |
| 待选 | 连接列表 | Sparkle Connections / Surge Activity | NSTableView 风格：进程、域名、链路、速率、规则、时间 | P0 | 高 | 信息密度要接近 Surge。 |
| 待选 | 连接详情 Inspector | Surge Activity | 选中连接显示请求链路、进程、规则、流量详情 | P1 | 中 | 比弹窗更原生。 |
| 待选 | 连接过滤/分组 | Sparkle advanced filter | 按进程、域名、策略、规则、连接状态过滤 | P1 | 中 | 适合专业用户。 |
| 待选 | 实时流量图 | Sparkle traffic monitor / Surge Activity | 概览页小图 + 活动页详细图 | P0 | 中 | 菜单栏显示上下行速率。 |
| 待选 | 日志流 | Sparkle Logs | 按 level、来源、关键词过滤，支持暂停和复制 | P0 | 中 | 使用 ring buffer 控内存。 |
| 待选 | 核心运行日志落盘 | sparkle-service log writer | 可配置保留天数和单文件大小 | P1 | 中 | 诊断必备。 |
| 待选 | 规则查看 | Sparkle Rules / Surge Rule table | 表格显示类型、值、策略、命中次数、注释 | P1 | 中 | Surge 风格很适合这里。 |
| 待选 | 禁用规则 | Sparkle `rules/disable` | 可选高级项，支持临时禁用和恢复 | P2 | 中 | 需确认 mihomo 版本兼容。 |
| 待选 | Rule Provider 管理 | Sparkle Resources | 外部资源页显示状态、类型、路径、最后更新 | P1 | 中 | 与 Surge 外部资源页类似。 |
| 待选 | Proxy Provider 管理 | Sparkle Resources | Provider 列表、手动更新、状态提示 | P1 | 中 | 首版可只做查看和刷新。 |
| 待选 | DNS 设置 | Sparkle DNS / Surge DNS | Form + 表格：nameserver、policy、fake-ip、hosts | P1 | 高 | 配置项多，要分基础/高级。 |
| 待选 | 自动设置系统 DNS | Sparkle TUN DNS | TUN 开启时可由 Helper 设置公共 DNS，关闭时恢复 | P2 | 高 | 回滚机制必须可靠。 |
| 待选 | Sniffer 设置 | Sparkle Sniffer | 基础开关 + 协议端口表 + 跳过域名/IP | P1 | 中 | 默认使用 mihomo 推荐值。 |
| 待选 | 外部控制器/UI | Sparkle external-controller/UI | 允许启用 zashboard/metacubexd，但不作为主体验 | P2 | 中 | 原生 App 是主控制面。 |
| 待选 | Geo 数据更新 | Sparkle upgrade geo | 一键更新 GeoIP/GeoSite/MMDB/ASN | P1 | 中 | 显示数据版本与更新时间。 |
| 待选 | mihomo Core 更新 | Sparkle core upgrade | stable/alpha 通道，下载校验，失败回滚 | P1 | 高 | 签名、校验、回滚要做。 |
| 待选 | WebDAV 备份恢复 | Sparkle backup | 备份 Profile、设置、片段；恢复前生成本地快照 | P2 | 中 | 可以先做本地导入导出。 |
| 待选 | Gist 同步 | Sparkle Gist | 高级同步选项 | P3 | 中 | 不是 macOS 首版刚需。 |
| 待选 | Sub-Store 集成 | Sparkle Sub-Store | 可作为“订阅工具箱”或插件入口 | P2 | 高 | 功能强但会拉高维护成本。 |
| 待选 | 深链导入 | Sparkle deep link | `mihomo://install-profile`、`mihomo://install-override` | P1 | 中 | 导入前必须确认来源。 |
| 待选 | 菜单栏快速操作 | Sparkle tray / Surge menu bar | 状态、速率、Profile、模式、策略快捷切换 | P0 | 中 | macOS 体验关键。 |
| 待选 | 浮动窗口 | Sparkle floating window | 小流量窗或 mini panel | P3 | 中 | 容易打扰，建议后置。 |
| 待选 | 快捷键 | Sparkle shortcut | 打开窗口、切换代理、启停系统代理 | P2 | 低 | 放在高级设置。 |
| 待选 | 开机启动/静默启动 | Sparkle startup | 登录项、启动后最小化到菜单栏 | P1 | 中 | 使用 macOS Login Item API。 |
| 待选 | 轻量模式 | Sparkle auto lightweight | 关闭主窗口但保留核心/菜单栏 | P1 | 中 | 很适合 macOS 常驻工具。 |
| 待选 | 主题系统 | Sparkle themes | 首版只跟随系统浅/深色 | P3 | 中 | 原生 UI 不建议早期做复杂主题。 |
| 待选 | 自定义托盘图标 | Sparkle custom tray icon | 后置 | P3 | 低 | 对核心价值影响小。 |
| 待选 | 远程 HTTP API | Surge 设置参考 | 可选开启本地 API，默认关闭 | P3 | 中 | 安全风险高。 |
| 待选 | 网络诊断 | Surge Activity/Diagnostics | 检测 controller、系统代理、TUN、DNS、外网延迟、权限 | P0 | 高 | 建议做成首版亮点。 |

## 5.1 v0.5.0 实现状态

当前仓库已经从“开发报告”推进到可运行的第五版 MVP。新增功能没有复制 Sparkle 的 Electron/Go 代码，而是在 SwiftUI/AppKit 和 Swift service 层重新实现。

| 功能 | v0.5.0 状态 | 主要落点 |
| --- | --- | --- |
| 内置 mihomo core | 已实现 release bundle 路径 | `script/prepare_core_bundle.sh` 下载 `vendor/mihomo`，`script/build_and_run.sh` 打入 `Contents/Resources/Core/mihomo`，App 启动时可作为有效 core。 |
| mihomo Core 更新 | 已实现托管更新 | 高级页下载 core 到 `~/Library/Application Support/Mihomo/Core/mihomo`，并可启用托管 core。 |
| Helper/LaunchDaemon 托管核心 | 已实现 LaunchDaemon 路径 | 通过管理员授权安装/卸载 `/Library/LaunchDaemons/dev.codex.Mihomo.core.plist`，使用当前 runtime config 托管核心。 |
| 自动设置系统 DNS | 已实现 | 启动 core 前使用 `networksetup` 设置 DNS，停止/退出时通过快照恢复。 |
| 外部控制器/UI | 已实现 UI 管理 | 支持下载 zashboard/metacubexd 类 zip，写入 `external-ui`、`external-ui-name`、`external-ui-url`。 |
| 远程 HTTP API | 已实现默认关闭与显式启用 | 默认绑定 `127.0.0.1`，开启后使用指定 bind address；Controller 客户端支持 Bearer secret。 |
| 证书指纹校验 | 已实现 | 远程 Profile 首次导入记录 HTTPS 证书 SHA-256，刷新时校验 pin。 |
| YAML 覆写片段 | 已实现 | 高级页管理片段，runtime config 生成时追加启用的 YAML 片段。 |
| JS 脚本覆写 | 已实现高级开关 | 使用 JavaScriptCore 执行启用片段中的 `transform(config)`，默认关闭。 |
| 配置预览/Diff | 已实现 | 高级页显示合并后的 runtime config 与原始配置的行级 diff。 |
| 规则查看 | 已实现 | 规则页解析当前 Profile 的 `rules`。 |
| 禁用规则 | 已实现 | 禁用列表持久化，runtime config 生成时过滤对应规则。 |
| Rule Provider 管理 | 已实现 | 资源页本地解析 `rule-providers`，Controller 可用时读取/更新。 |
| Proxy Provider 管理 | 已实现 | 资源页本地解析 `proxy-providers`，Controller 可用时读取/更新。 |
| DNS 设置页 | 已实现 | 高级页管理系统 DNS、mihomo DNS enhanced-mode、nameserver、fallback。 |
| Sniffer 设置 | 已实现 | 高级页管理开关、端口、force-domain、skip-domain，并写入 runtime config。 |
| Geo 数据更新 | 已实现 | 高级页下载 GeoIP/GeoSite 到 App Support 的 Geo 目录。 |
| WebDAV 备份恢复 | 已实现 | 支持本地 zip 备份、WebDAV PUT 上传、WebDAV 下载并恢复。 |
| Gist 同步 | 已实现 | 使用 `mihomo-backup.json` 同步设置、Profile、片段和禁用规则。 |
| 深链导入 | 已实现 | 注册 `mihomo://`，支持导入 Profile 和覆写片段。 |

## 5.2 v0.6.0 Helper 架构状态

第六版 MVP 的路线是保留 LaunchDaemon 托管 mihomo core，同时新增 XPC Helper 承担高权限操作。主 App 回到 UI、状态和普通文件管理职责，不再直接执行管理员 shell。

| 第六版要求 | v0.6.0 状态 | 主要落点 |
| --- | --- | --- |
| 保留 LaunchDaemon 托管 core | 已保留并收口 | `/Library/LaunchDaemons/dev.codex.Mihomo.core.plist` 仍用于长期运行、KeepAlive、开机启动，但安装/卸载/启动/停止由 Helper API 执行。 |
| 增加 XPC Helper | 已实现 | 新增 `MihomoShared` XPC 协议目标和 `MihomoHelper` 可执行目标，Mach service 为 `dev.codex.Mihomo.Helper`。 |
| Helper 安装/注册 | 已实现 | App bundle 内包含 `Contents/Library/LaunchDaemons/dev.codex.Mihomo.Helper.plist` 与 `Contents/Library/LaunchServices/MihomoHelper`，高级页使用 `SMAppService.daemon` 注册/卸载。 |
| 安装/卸载 LaunchDaemon | 已迁移到 Helper | `HelperService.installCoreLaunchDaemon`、`uninstallCoreLaunchDaemon`、`startCoreLaunchDaemon`、`stopCoreLaunchDaemon`。 |
| 启停 mihomo core | 已迁移到 Helper | `prepareAndStartCore` 先 dry-run 校验，再由 Helper 启动 core 并写入 core log；`stopCore` 负责停止和回滚。 |
| 设置/恢复系统 DNS | 已迁移到 Helper | Helper 通过 `networksetup` 捕获快照、设置 DNS、恢复快照。 |
| 设置/恢复系统代理 | 已迁移到 Helper | Helper 通过 `networksetup` 设置 HTTP/HTTPS/SOCKS 代理并恢复原状态。 |
| TUN 路由快照与回滚 | 已迁移到 Helper | Helper 捕获网络代理/DNS、IPv4/IPv6 路由、默认路由，并在停止/修复时删除新增 utun 路由和恢复默认路由。 |
| 权限修复/验证 | 已迁移到 Helper | 主 App 调用 `verifyPrivileges`，Helper 检查自身是否 root 运行。 |
| 校验 runtime config 后再启动 | 已实现 | Helper 的 `prepareAndStartCore` 调用 `mihomo -t -d ... -f ...` 成功后才启动核心。 |
| 主 App 只做 UI 和状态管理 | 已收口 | `AppStore` 生成候选配置、保存设置、刷新 UI；高权限操作统一通过 `MihomoHelperClient`。旧 `PrivilegedShell` 已移除。 |

## 5.3 v0.7.0 分发、安全与配置合并状态

第七版聚焦“可长期自用分发”和诊断硬化：在没有 Apple Developer 账号的前提下，不伪装成已公证软件，而是采用固定 ad-hoc identifier、首次移除隔离属性、后续应用内校验更新的路径。

| 第七版要求 | v0.7.0 状态 | 主要落点 |
| --- | --- | --- |
| 配置页/设置页 UI 修复 | 已优化 | 配置页重做为紧凑 Header、订阅条、队列状态和稳定 Split View；设置页改为原生分段设置面板，减少 Form 变形和底部按钮裁切。 |
| 固定签名安装/更新 | 已实现基础链路 | `build_and_run.sh` 为 App、Helper、内置 core 使用固定 ad-hoc signing identifier；`package_release.sh` 生成 zip 和 update manifest；高级页支持 manifest 检查、SHA-256 校验、bundle id/signing identifier 校验后退出替换。 |
| 无公证分发边界 | 已明确 | 无 Apple Developer ID 时不能 notarize。首次下载仍需 `xattr -dr com.apple.quarantine /Applications/Mihomo.app`；后续应用内更新会在替换后清理隔离属性。 |
| Helper 签名/授权审计 | 已增强 | 诊断与高级页可审计 Helper bundle 布局、plist、SMAppService 状态、App/Helper 签名 identifier、公证状态说明和 root XPC 可达性。 |
| Helper XPC 授权边界 | 已增强 | Helper listener 校验连接方进程必须来自 `dev.codex.Mihomo` app bundle，并通过 `codesign` identifier 检查后才接受连接。 |
| Helper 恢复体验 | 已增强 | 高级页新增 Helper 审计与修复注册入口，可重建 SMAppService 注册并跳转诊断结果。 |
| Secret 存储 | 已改为非 Keychain vault | 因 ad-hoc 更新会导致 Keychain 反复授权，Controller/WebDAV/Gist secret 改存 `secrets.vault`，使用 CryptoKit AES-GCM 与本机/用户派生密钥；`settings.json` 和 Gist payload 默认脱敏。 |
| YAML AST 合并 | 已实现 | 引入 Yams，runtime config 从结构化 YAML map 合并，移除 App 管理键、合并 YAML 片段、过滤禁用规则，再写入 App overlay。解析错误会阻止预览/启动。 |
| Provider/Rule 命中统计 | 已实现基础统计 | Controller 连接刷新后回填规则命中；Rule Provider 按 `RULE-SET` payload 统计；Proxy Provider 在 Controller 返回成员节点时按 chain 归属统计。 |
| Sub-Store | 后置 | 等主体验与分发链路稳定后再作为高级集成实现。 |

## 5.4 v0.8.0 配置编辑、Profile 加密与更新签名状态

第八版把“能运行”继续推进到“能维护配置”：用户不必只靠 YAML 文本编辑完成常见策略组/规则维护，同时更新链路不再只依赖托管源可信。

| 第八版要求 | v0.8.0 状态 | 主要落点 |
| --- | --- | --- |
| Ed25519 update manifest | 已实现 | `sign_update_manifest.swift` 使用本机私钥签名 manifest；App 内置公钥，在检查更新时先验证 Ed25519 签名，再校验 SHA-256、bundle id 和 signing identifier。 |
| 更新私钥管理 | 已实现本机方案 | 私钥读取自 `MIHOMO_UPDATE_PRIVATE_KEY` 或 `~/.mihomo-update-signing/ed25519.private`；仓库只保存公钥常量。 |
| 策略组 UI 增删改 | 已实现 | Profile 页新增“结构”编辑模式，可添加、修改、删除 `proxy-groups`，编辑类型、节点列表和 provider 引用。 |
| 删除策略组引用处理 | 已实现 | 删除被规则引用的策略组时会提示引用数量，可选择将相关规则替换到其他策略或删除引用规则。 |
| 规则 UI 增删改 | 已实现 | Profile 结构编辑可添加、修改、删除 `rules`，支持设置规则类型、匹配 payload、目标策略组和附加参数。 |
| Age Profile 加密 | 已实现基础链路 | 高级页可安装托管 `age`/`age-keygen`、生成 identity/recipient，并在 ProfileStore 读写 Profile YAML 时透明加解密。启用后磁盘 Profile 可为标准 Age armor。 |
| 备份与运行时兼容 | 已实现 | 运行时配置生成使用解密后的 Profile；Gist payload 保存磁盘原文，因此启用 Age 后不会把 Profile 明文写入云端 JSON。 |

## 5.5 v0.9.0 规则表、核心来源与 GitHub 更新入口

第九版把“能维护配置”推进到“更像成熟 macOS 网络工具”：Profile 与 Rules 页面都改成更接近 Surge 的密集工作台布局，同时清理核心来源和软件更新的入口混乱。

| 第九版要求 | v0.9.0 状态 | 主要落点 |
| --- | --- | --- |
| Profile 上下布局 | 已实现 | Profile 页改为上方配置列表、下方配置编辑器，并把覆写片段移动到配置编辑器下方，减少高级页跳转。 |
| Surge 风格规则表 | 已实现 | Rules 页使用 ID、类型、值、策略、使用计数、注释列，支持搜索、启用/禁用、添加、编辑、删除和重置计数。 |
| 保存不隐藏窗口 | 已修复 | `saveSettings` 不再因轻量模式开关而调用隐藏主窗口；轻量模式只由显式入口或启动行为触发。 |
| 核心来源统一 | 已实现 | 新增托管远程、随包内置、本地外部三种 core source；Settings 为唯一切换入口，高级页只保留 Helper/LaunchDaemon 运维。 |
| 软件更新入口 | 已简化 | 应用不再要求用户填写 manifest URL；检查更新固定读取 GitHub Latest Release 中的 `mihomo-update.json`。 |
| 菜单栏更新 | 已实现 | App 菜单和菜单栏都新增检查更新入口；发现新版后可直接触发安装。 |

## 5.6 v1.0.0 配置管理、资源离线更新与 LaunchDaemon 稳定性

1.0 MVP 版收口到“可日常使用”的操作体验：配置页不再默认展开大段 YAML，资源更新不再强依赖当前 mihomo 进程，LaunchDaemon 安装前也会主动处理 Geo 数据可用性。

| 1.0 要求 | v1.0.0 状态 | 主要落点 |
| --- | --- | --- |
| 配置页滚动工作台 | 已实现 | 配置页改为类似高级页的可滚动布局，列表、配置摘要和覆写摘要按区域排列。 |
| 默认显示统计信息 | 已实现 | 选中配置后显示规则、策略组、节点、Provider、行数和大小等统计；不再默认展示完整 YAML。 |
| 独立编辑窗口 | 已实现 | 点击“编辑”打开独立配置编辑窗口，可切换 YAML/结构化模式；覆写片段也通过独立窗口管理。 |
| 配置删除与启用标志 | 已实现 | 配置列表新增状态列显示当前启用配置，并提供删除按钮；至少保留一个配置。 |
| 一键更新资源 | 已实现 | 资源页新增一键更新 Provider 与 Geo 数据；Provider 可按本地配置中的 URL 直接下载到 runtime provider path，不要求 Controller 可用。 |
| Controller 更新保留 | 已实现 | mihomo 运行时仍可通过 Controller 更新 Provider，但这不再是唯一更新路径。 |
| 重复字段清理 | 已修复 | 高级页 DNS Enhanced Mode 隐藏 Picker 内部 label，避免字段重复显示。 |
| LaunchDaemon GeoSite 失败 | 已缓解 | dry-run、核心启动和 LaunchDaemon 安装前同步 GeoIP/GeoSite 到 runtime 目录；遇到 Geo 数据下载/损坏错误时会先更新 Geo 数据再重试一次。 |

## 6. 建议 MVP 范围

第一版建议控制在“稳定运行 + 高质量原生体验”：

| MVP 功能 | 说明 |
| --- | --- |
| 核心管理 | 内置 mihomo stable、启动/停止/重启、运行状态、最近错误。 |
| Profile | 本地/远程订阅导入、切换、手动更新、基础用量显示。 |
| 网络接管 | 系统代理、TUN、出站模式、权限检查、失败回滚。 |
| 策略组 | 策略组列表、节点选择、延迟测试、搜索排序。 |
| 活动 | 实时流量、连接列表、连接关闭、基础过滤。 |
| 日志 | 实时日志、级别过滤、复制、保存最近日志。 |
| 诊断 | 一键检查核心、controller、系统代理、TUN、DNS、订阅可达性。 |
| 菜单栏 | 速率、开关、当前 Profile、出站模式、打开主窗口。 |

早期建议将 Sub-Store 深度集成、复杂主题和自定义图标后置。v0.5.0 已把 JS 覆写、WebDAV/Gist 同步和远程 HTTP API 做成高级页能力；v0.6.0 已加入 XPC Helper 边界；v0.7.0 已完成无 Apple Developer 账号路径下的固定签名更新、Helper 审计、非 Keychain secret vault、Yams 合并和命中统计；v0.8.0 已补上 Ed25519 更新签名、策略组/规则结构化编辑和 Age Profile 加密；v0.9.0 已完成 Profile/Rules 工作台重排、核心来源统一和 GitHub Release 更新入口；v1.0.0 已收口配置管理、资源离线更新和 LaunchDaemon Geo 数据稳定性。

## 7. 数据与配置设计

建议目录：

| 类型 | 建议位置 |
| --- | --- |
| 用户配置 | `~/Library/Application Support/<AppName>/config.yaml` |
| Profiles | `~/Library/Application Support/<AppName>/Profiles/*.yaml` |
| Runtime config | `~/Library/Application Support/<AppName>/Runtime/config.yaml` |
| Logs | `~/Library/Logs/<AppName>/` |
| Helper 配置 | `/Library/Application Support/<AppName>/` 或 Helper 自有目录 |
| 密钥/Token | 无 Apple Developer 账号分发时使用本机派生密钥加密的 `secrets.vault`；若未来改用 Developer ID 稳定签名，可迁回 Keychain |

运行配置生成流程：

1. 读取当前 Profile 原始 YAML。
2. 应用安全的配置片段和 UI 控制项。
3. 清理空字段、平台不兼容字段和危险字段。
4. 输出 runtime config。
5. 启动 mihomo，并通过 controller 验证可用性。
6. 若失败，恢复上一个可用 runtime config。

## 8. 关键风险

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| macOS 权限与 TUN 稳定性 | 无法接管网络或关闭后残留路由/DNS | Helper 执行特权操作，所有操作记录原状态并支持回滚。 |
| GPL-3.0 合规 | 分发风险 | 不复制 Sparkle/service 代码；若内置 mihomo 或 GPL 组件，准备源代码和许可证说明。 |
| mihomo controller 版本差异 | API 不兼容 | 启动时读取 `/version`，按版本启用功能开关。 |
| 订阅质量不可控 | 配置生成失败 | 导入时校验 YAML，运行前 dry-run 或启动失败回滚。 |
| JS 覆写安全 | 任意代码风险 | 不进 MVP；若实现，必须沙盒、权限限制、明确警告。 |
| 菜单栏常驻资源占用 | 长期运行耗电 | WebSocket 自动重连节流，连接/日志列表虚拟化，后台采样降频。 |
| 系统代理/DNS 残留 | 用户网络异常 | 保存原配置，退出/崩溃恢复，提供“修复网络设置”按钮。 |

## 9. 开发里程碑

| 阶段 | 目标 | 产出 |
| --- | --- | --- |
| M0 原型 | 验证 mihomo core 启动、controller 连接、菜单栏速率 | SwiftUI App、core wrapper、基础 controller client |
| M1 核心 MVP | Profile、系统代理、TUN、策略组、日志、连接 | 可日常使用的本地版本 |
| M2 原生体验 | Surge 风格活动页、诊断页、Settings、Inspector | 完整主窗口和菜单栏体验 |
| M3 稳定性 | Helper、权限修复、失败回滚、更新、崩溃恢复 | 可分发 Beta |
| M4 高级功能 | DNS 细项、资源管理、配置 diff、备份、Sub-Store 可选集成 | 面向进阶用户的功能扩展 |

## 10. 下一步决策

后续建议围绕稳定性、体验打磨和真实使用反馈继续收敛，而不是继续横向扩功能。最推荐的下一轮组合是：

- 对 v0.8.0 的更新替换流程做真实 release 验证，包括从 GitHub Release manifest 更新到下一版。
- 继续打磨配置页、设置页和高级页的信息密度，减少 GroupBox/Form 造成的视觉膨胀。
- 为结构化配置编辑增加更完整的 mihomo rule schema 校验，例如规则参数合法性、provider 类型约束和 proxy 节点存在性。
- Sub-Store 作为独立高级集成，而不是主体验依赖。

这样可以把当前“像 Surge 一样专业，但底层是 mihomo”的 macOS 原生产品骨架，继续推进到可长期分发和日常托管的 Beta 质量。

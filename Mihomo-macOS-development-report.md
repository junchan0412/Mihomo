# Mihomo macOS 开发文档

更新日期：2026-08-05
对应版本：`v1.24.1 (79)`

本文档描述当前架构、关键数据流、页面职责、开发约束和发布流程。历史版本流水账不再作为主体；需要追溯时使用 Git history 和各版本 Release Notes。

## 当前状态与目标

- 当前状态：发布基线推进至 `v1.24.1 (79)`；配置资源的“全部更新”“更新所选”和“回滚所选”共用 Store 层有界并发队列，受 `resourceUpdateMaxConcurrent` 的 1-12 上限约束，worker 结果按输入顺序归并，避免 113 项资源的所选操作退化为串行等待；不可更新资源不会进入队列，运行中会禁用重复批量动作。远程覆写的所选/全部刷新复用订阅刷新并发设置，下载结果稳定归并后只写入一次覆写存储，同样阻止重复请求。软件更新使用结构化阶段状态：检查、下载、校验、准备网络、准备 Helper、安装与重启入口共用可取消任务；下载显示真实字节数、总量和速率，进度事件至多每 100 ms 发布一次；更新包通过 SHA-256、签名与 bundle 校验后才显示重启安装入口，取消或失败会清理临时目录并保留旧状态。连接、DNS、流量统计、概览时间轴以及配置、覆写、规则、日志、资源的无数据/无匹配结果统一使用明确空状态，不初始化空 AppKit 表格；筛选变化通过可测试的 selection reconciliation 清理隐藏选区；高频连接表、日志、流量和列表 presentation 均使用窄状态或单一 snapshot，减少重复计算与无关刷新。
- 近期目标：保持高频界面只更新必要范围，并以 350 行 warning、500 行 over-max、完整 `swift test`、可复现的并发上限测试和逐页实机回归作为持续门禁；继续审计批量任务取消、策略历史、路由解释和版本恢复的可发现性，根据真实使用反馈确定下一次发布范围。

## 1. 产品原则

1. 日常操作优先：核心启停、系统代理、TUN、策略切换和连接观察必须少步骤完成。
2. 设置与工具分离：设置描述长期偏好；高级工具只承载安装、维护、备份、安全与排障。
3. 配置优先：用户 Profile 和覆写是事实来源，应用设置只是默认值。
4. 状态可解释：网络接管、资源更新、配置合并和失败恢复都要显示来源、结果和下一步。
5. 安全失败：下载、路径、更新和恢复在校验失败时保留旧状态，不做破坏性替换。
6. macOS 原生：优先使用 SwiftUI scene、Toolbar、List、split view、标准菜单命令和 accessibility 语义。

## 2. 架构边界

```text
SwiftUI / AppKit Views
        ↓ 用户意图与展示状态
AppStore + domain extensions
        ↓ 协调
Services / Managers
        ↓
Profile files · Runtime files · Controller · XPC Helper · Network
```

### 2.1 Views

View 负责布局、绑定和短生命周期交互状态，不直接实现下载、文件替换、YAML 合并或特权命令。

主要页面职责：

| 页面 | 职责 | 不应承载 |
| --- | --- | --- |
| Overview | 运行摘要与高频入口 | 复杂设置 |
| Activity | 最近请求、活动连接、DNS 观测与流量统计 | DNS 配置逻辑、独立日志 |
| Logs | App/Core 日志筛选、表格浏览与落盘入口 | 连接工作区、脚本事件 |
| Policies | 策略组浏览、节点切换、GUI 策略组编辑入口 | Controller 实现 |
| Rules | 规则浏览、命中、GUI 编辑 | YAML 文件 IO |
| Profiles | Profile、覆写、质量与来源 | 网络接管 |
| Network | 系统代理/TUN/DNS 模式、运行时 DNS、域名嗅探与恢复 | Artifact 安装 |
| Resources | 独立节点提供商、配置 Provider、本地规则集、Geo 更新与回滚 | Web Controller |
| Advanced | Helper、LaunchDaemon、Artifact、备份、安全、诊断 | 常用设置重复项 |
| Settings | 通用、远程管理、局域网代理和高级默认值 | 内部控制通道、备份与维护动作 |

维护类页面统一使用“标题与状态 → 分段导航 → 单一内容列”的结构。网络使用自适应接管卡片；高级工具按运行、数据、备份、检查分区；诊断严格区分只读检查与有副作用的修复；设置只保存偏好，不重复放置维护动作。

App 图标的矢量源位于 `Assets/`，构建前生成的 light/dark PNG、菜单栏模板图和 `Mihomo.icns` 位于 `Assets/Generated/`。`build_and_run.sh` 负责将这些资源复制到 App bundle，菜单栏图片必须设置 `isTemplate = true` 以适配系统外观。

设置是主窗口侧栏中的稳定目的地。`Command-,`、菜单栏和侧栏统一选择 `.settings` 并显示主窗口，不再创建与主导航状态分离的独立设置窗口。

主窗口使用原生 Source List 与可自定义 Toolbar。导航、搜索、刷新和常用控制通过菜单命令与 `FocusedValues` 路由到当前工作区。Profile 编辑器和覆写快速查看使用 value-based `WindowGroup`；覆写列表仍以 Space 触发预览，但 YAML/JavaScript 不再交给系统 Quick Look。覆写列表由单个 `ConfigFragmentListPresentation` 派生可见项、选区、表高和 columns；`ConfigFragmentListPane` 只接收显式 actions，不持有 `AppStore`。

### 2.2 AppStore

`AppStore.swift` 保存共享低频状态和 service 实例。领域行为按 extension 拆分，例如：

- `AppStore+CoreLifecycle`
- `AppStore+Bootstrap`
- `AppStore+DerivedState`
- `AppStore+ControllerStreams`
- `AppStore+ControllerPolling`
- `AppStore+Profiles`
- `AppStore+ConfigEditing`
- `AppStore+Resources`
- `AppStore+NetworkTakeover`
- `AppStore+Backup`
- `AppStore+SoftwareUpdates`
- `AppStore+PolicyIcons`

高频连接、流量和日志不直接堆在 AppStore：

- `RuntimeActivityStore`：活动连接、最近请求、速率、分组流量样本与 event stream 状态。
- `LogStore`：可见日志、暂停缓冲与增量发布。
- `LogPersistenceWriter`：串行、批量持久化，避免每条日志触发磁盘 IO。

### 2.3 Services

Service 应尽量可独立测试，并返回结构化结果：

- `RuntimeConfigBuilder`：合并最终配置。
- `ProfileYAMLStructureEditor`：策略组/规则的结构化增删改。
- `ProfileQualityAnalyzer`：字段来源、差异层级和 schema 风险。
- `ConfigFragmentAnalyzer`：覆写 YAML/JavaScript 语法、顶层结构、入口函数与 Sniffer 规则定位。
- `NodeProviderStore`：独立节点订阅及其 Profile 接入关系的持久化与校验。
- `ProviderResourceManager`：远程更新、本地校验、备份与回滚。
- `NetworkSecurityCenter`：接管与快照展示模型。
- `SoftwareUpdateManager`：版本发现、下载校验和替换脚本。
- `SpotlightIndexer`：索引 Profile 与 Provider，并使用内容指纹避免重复全量重建。

### 2.4 XPC Helper

Helper 执行需要权限的行为：

- core start/stop/restart；
- system proxy 与 system DNS 修改/恢复；
- TUN 路由和快照恢复；
- LaunchDaemon 管理；
- 权限与路径审计。

主 App 不应通过 shell 绕过 Helper。新增 Helper operation 时，需要同步：共享协议、client、service、transaction result、诊断和测试。

Helper 有两种受控部署模式：

- Developer ID + notarization 构建使用 `SMAppService`。Helper 或 plist 变化时必须等待异步 unregister 完成，再替换 App，并在新版本启动后 register。
- 无开发者账户构建只能使用管理员明确授权的传统兼容路径。App 检测到主程序与 Helper 没有匹配的稳定 Apple Team 签名时，会跳过无法生效的 SMAppService 批准流程。Helper 位于 `/Library/PrivilegedHelperTools`，LaunchDaemon 位于 `/Library/LaunchDaemons`，root 所有的授权文件绑定当前 App 路径与签名 CDHash。更新后必须重新绑定，不允许仅凭可伪造的 ad-hoc identifier 授权客户端。

发布用 `CFBundleVersion` 必须是数字；Git 短哈希只适合作为诊断元数据，不能作为 bundle build number。

## 3. 配置数据流

### 3.1 合并优先级

从低到高：

```text
应用默认 → Profile → JS Transform → YAML 覆写
```

等价表达：

```text
YAML 覆写 > JS Transform > Profile 配置 > 应用默认
```

控制通道是唯一例外：`external-controller` 与 `secret` 在所有合并完成后由应用强制写入，Profile、JS Transform 和 YAML 覆写不能改变客户端连接自己启动核心所需的地址与密钥。

`RuntimeConfigBuilder` 先生成应用默认 overlay，再用配置结果覆盖它。禁止重新引入“删除 Profile 同名字段后由 App 强制接管”的旧行为。

Profile 与 App 的编辑语义：启用或刷新 Profile 时，将其中声明的 `mixed-port`、`socks-port`、`allow-lan`、`log-level`、`tun`、`dns` 和 `sniffer` 载入 App；之后 App 中这些字段发生变化时，通过 `ProfileSettingsSynchronizer` 写回当前 Profile。JS/YAML 覆写不回写 Profile。

### 3.2 生成流程

1. 从 `ProfileStore` 读取当前 Profile。
2. 执行启用的 JS Transform，worker 有输入/输出限制和超时。
3. 合并启用的 YAML 覆写。
4. 用结果覆盖应用默认值。
5. 删除禁用规则，生成 candidate。
6. 执行 `mihomo -t`。
7. 校验通过后替换 runtime config；失败保留旧配置。

### 3.3 配置质量

质量总览、字段来源与合并层级共享一个连续分段容器。问题区与运行时摘要纵向排列，避免等高双栏在问题较少时产生大片空白。每条问题必须标注来源为当前 Profile、App 设置、覆写或最终配置。出站检查将 inline `proxies` 和 `proxy-providers` 视为等价来源，只有两者同时为空才发出警告。

覆写片段支持全局作用域和指定 Profile 作用域；Runtime 构建、Profile 保存与质量分析必须使用同一套 `applies(to:)` 过滤规则。

质量面板有三个视角：

- 质量总览：评分、问题与最终 Runtime 摘要。
- 字段来源：字段、来源、最终值、简要说明与 hover 详情。
- 合并层级：每一层是否改变配置以及变化摘要。

新增 runtime 字段时至少更新：

- `AppSettings`
- settings migration（如 schema 变化）
- `RuntimeConfigBuilder`
- `ProfileQualityAnalyzer`
- Runtime builder/analyzer tests

## 4. 网络模型

网络工作区分为：

- 概览：系统代理、TUN、系统 DNS 三种接管卡片。
- DNS：运行时 DNS 与 macOS 系统 DNS。
- 域名嗅探：HTTP/TLS/QUIC 识别范围、DNS 映射、纯 IP 识别、目标替换和例外规则。
- 恢复：代理、DNS、TUN 的独立快照和修复中心。

系统代理与 TUN 可以协同启用：系统代理覆盖遵守代理设置的应用，TUN 接管其余透明流量。系统 DNS 兼容改写可以独立启用，但必须使用独立快照；任何恢复逻辑都不能复用其他模式的 snapshot。

Activity 的 DNS 是连接工作区内的只读观测视图，数据来自最近连接中的域名、目标地址和来源信息；它不能跳转到 Network/Settings，也不能承担运行时 DNS 或 macOS 系统 DNS 的配置职责。Activity 顶部分段只保留“最近的请求 / 活动连接 / DNS / 流量统计”，设备与日志簿不属于该工作区。

独立 Logs 页面按“全部 / 常规 / 网络切换 / DHCP”筛选 App 与 core 事件，并使用“时间 / 分类 / 标题 / 详情”表格展示。Mihomo 没有脚本事件模型，因此不得为了模仿其他客户端而添加脚本分类。

客户端与核心之间的 Controller HTTP/WebSocket 只作为内部技术名存在。普通 UI 不展示“本机 Controller”或“刷新 Controller”，而使用“远程管理”“刷新核心状态”和“核心控制通道”。远程管理关闭时始终只监听本机；开启时才显示监听地址、端口和访问密钥，并在缺少密钥时自动生成。

域名嗅探参考 Sparkle 的独立功能入口，但使用 macOS 原生分段工作区而非可拖拽 Web 卡片。概览提供快速开关，详细页面解释其不解密 HTTPS、不是 DNS 查询，并将 `parse-pure-ip`、`force-dns-mapping`、`override-destination` 转换为用户可理解的描述。

流量时间轴只允许“直连”和“代理”两种路由颜色语义。具体色值必须同时满足 light/dark、Increase Contrast 和非颜色信息可理解性，不能再用第三种颜色表达未知或混合状态。

## 4.1 macOS 交互约定

- 主导航使用原生 sidebar list，Toolbar 使用系统 placement 与 customization。
- `Command-1…9` 导航工作区，`Command-F` 聚焦当前搜索，`Command-R` 刷新当前内容。
- 表格应支持 Command/Shift 多选、Return、Space、Delete 和选区感知的 Context Menu。
- 可恢复的模型编辑注册 Undo；网络连接关闭等不可恢复操作必须确认，不伪装成可 Undo。
- 动画尊重 Reduce Motion，半透明表面尊重 Reduce Transparency，状态色尊重 Increase Contrast。
- 通知权限只在用户开启对应能力时请求；拒绝后 UI 必须恢复为关闭状态并解释原因。
- 可发现内容优先接入 Spotlight、App Intents、Dock Menu、Quick Look 与 ShareLink，而不是重复创建应用内入口。
- 覆写快速查看是应用内代码预览窗口，必须保留 Space、行号、语法高亮和问题定位；系统 Quick Look 仅用于适合文件级预览的 Profile、资源与诊断产物。

## 5. 资源更新模型

远程订阅与外部资源批量更新使用独立并发设置。`profileRefreshMaxConcurrent` 共同控制远程 Profile 与远程覆写刷新；`resourceUpdateMaxConcurrent` 控制 Provider 批量更新，范围固定为 1–12。覆写刷新结果在同一轮下载完成后一次提交，资源页允许即时调整，持久化仍统一经过 `saveSettings`。

Proxy Provider 本地缓存可能是 Mihomo YAML、完整配置、Base64 订阅或分享链接列表。缓存展示层只提取节点名称，不承担协议转换；更新历史至少保留 500 条，以覆盖大规模 Rule Provider 批量刷新后的状态展示。

规则启用列由 `AppKitTable` 的 checkbox column bridge 提供。SwiftUI 保持 `disabledRules` 为唯一状态源，AppKit 仅通过窄回调触发 `toggleRuleDisabled`。分类条、表格 columns、bottom bar 与 context menu 由 `RuleTablePane` 统一展示，`RulesView` 只负责页面状态、命令路由与 store 写入。资源行右键菜单同样由表格 bridge 提供单一 action 回调。

资源统一建模为 `ProviderItem`，通过 `ExternalResourceRow` 形成展示状态。

更新规则：

- 有 `remoteURL`：下载到受限 runtime path，校验后备份并替换。
- 无 `remoteURL` 但有 path：执行本地重新载入/校验。
- 全部更新、更新所选与回滚所选：通过同一 Store 层有界并发队列处理 Provider，最多同时执行 `resourceUpdateMaxConcurrent`（1-12）项，结果和历史按输入顺序归并；全部更新最后更新 Geo 数据。

本地校验包括：路径约束、文件存在、非空和 mapped read 可读性。Profile、覆写与 Provider 的远程来源只能展示移除 user/password、query、fragment 与高熵 path token 的 URL，避免在界面、截图或 accessibility tree 中泄露凭据；描述性仓库路径与常见配置文件名保留，实际下载仍使用原始 URL。

## 6. GUI 结构编辑

### 6.1 策略组

策略页离线数据来自 Profile 结构和 Provider 本地缓存，不以 Controller 运行状态作为展示前提。策略组在当前页面展开节点，并保留 `hidden`、`icon` 与节点 `available` 元数据；页面级操作只提供折叠/展开、全量测速和筛选。

策略页“编辑策略组”加载当前 Profile 原文，使用 `ProfileStructureEditorView` 和 `ProfileYAMLStructureEditor` 修改：

- 名称、类型、proxies、use；
- 新增、保存、删除；
- 删除被规则引用的组时，选择替换策略或同时删除引用规则。

保存写回源 Profile，然后刷新配置 artifacts。运行中的 core 不会被静默重启，用户通过页面“应用”或明确操作决定何时加载。

### 6.2 规则

规则页支持新建、双击编辑、右侧 Inspector 编辑、禁用、删除和重置命中计数。保存前校验 rule type、payload、目标策略和 RULE-SET Provider 引用。

## 7. 网络稳定与性能约定

- 不使用进程级 `URLSession.shared` 作为所有请求的默认实现。
- Controller、订阅、Artifact、Provider、备份和更新分别使用有界 timeout。
- WebSocket 有 heartbeat、指数退避上限和 polling fallback。
- 高频事件只更新 focused store，避免整个窗口重新计算。
- 日志批量落盘；长列表使用 AppKit table/text bridge 和增量数据。
- 概览流量时间轴先二分定位可见策略样本，再按相邻流量采样中点单次分桶；禁止在每个柱形中重复 filter 全部历史样本。
- 配置资源的行模型、就绪计数、筛选和选区从同一 presentation snapshot 派生；文件存在状态每轮只读取一次。
- 规则解析、分类计数、命中总数、筛选和选区从同一 presentation snapshot 派生；禁止为 Header、Table、Bottom bar 分别解析全量规则。
- Activity 流量统计在一次样本遍历中同时累加今天、5/15/60 分钟、6/12 小时窗口，并将同一行数组传给计数与表格。
- 批量 Provider/测速任务必须使用并发上限，不能无界创建 Task。

## 8. 安全约定

- 所有下载替换先写 staging，再校验，再原子替换或恢复旧文件。
- 绝对路径、`..`、symlink escape 和非 allowlist 目标必须拒绝。
- Helper 验证调用方 bundle、signing identifier 和允许路径。
- Secret 不写入普通 settings backup；诊断导出和 UI 必须脱敏。
- Release 更新验证 Ed25519、SHA-256、bundle id 和 signing identifier。

## 9. 测试策略

最小本地门禁：

```bash
DEVELOPER_DIR='/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer' swift test
git diff --check
./script/maintainability_audit.sh
APP_VERSION=1.24.1 APP_BUILD=79 ./script/build_and_run.sh --verify
```

本轮 `v1.24.1 (79)` 核查证据：

- `DEVELOPER_DIR='/Volumes/TR 5000/macOS/Applications/Xcode-beta.app/Contents/Developer' swift test`：217 tests，0 failures。
- `git diff --check`：通过。
- `./script/maintainability_audit.sh --fail-on-max`：227 个 Swift 文件，warning 0，over-max 0。
- `APP_VERSION=1.24.1 APP_BUILD=79 ./script/build_and_run.sh --verify`：构建、ad-hoc 签名、bundle 严格校验和真实 `.app` 启动通过；窗口显示 `Mihomo v1.24.1 (79)`。

高风险改动补充验证：

| 改动 | 必要验证 |
| --- | --- |
| 网络接管/恢复 | `network_takeover_smoke.sh` + 手工 before/after |
| Helper | client/service mock、签名 identity、真实注册状态 |
| Provider | 下载、本地刷新、rollback 和 path escape tests |
| 更新器 | manifest、坏 zip、坏 hash、copy failure、codesign failure |
| AppKit bridge | XCTest accessibility + 人工 keyboard/VoiceOver checklist |
| UI 重构 | 构建最新绝对路径 App，逐页检查窗口、空态、滚动和操作入口 |

## 10. 发布流程

1. 确认版本和 Release Notes。
2. 全量测试、diff check、maintainability audit。
3. 使用指定 Xcode 构建并运行最新 `dist/Mihomo.app`。
4. 确认没有 `/Applications/Mihomo.app` 旧窗口抢占前台。
5. CI / 本机先执行不可发布的 ad-hoc 结构门禁：

```bash
./script/ci_release_gate.sh
```

6. Developer ID 发布机执行 `protected_release_checklist.sh --version <version>`；无开发者账户时必须显式设置 `MIHOMO_ALLOW_UNNOTARIZED_RELEASE=1`，生成标注未签名/未公证且由 manifest 固定 App/Helper CDHash 的 ad-hoc Release。
7. 检查 zip、versioned manifest、latest manifest 和 provenance。
8. 提交并 push branch。
9. 创建新版本 tag，不移动旧 tag。
10. push tag。
11. 创建 GitHub Release，上传 zip、versioned manifest、`mihomo-update.json` 与 provenance，正文使用对应 Release Notes。

## 11. 当前技术债务

- 当前维护者没有 Apple Developer 账户；发布物采用明确标注的 ad-hoc 模式，用户需自行移除 quarantine。Ed25519 manifest 同时固定 zip SHA-256 与主 App/Helper CDHash；特权能力使用需管理员授权且绑定 App CDHash 的传统 Helper。未来取得 Developer ID 后仍应切换到 notarized 发布路径。
- AppKit bridge 仍需定期做真实 VoiceOver/keyboard QA。
- 维护性审计继续以 350 行为 warning、500 行为 over-max 阈值，避免职责在后续迭代中重新聚合。
- 网络接管真实异常路径需要持续沉淀 before/after smoke 证据。

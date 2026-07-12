# Mihomo macOS 开发文档

更新日期：2026-07-11
对应版本：`v1.8.77`

本文档描述当前架构、关键数据流、页面职责、开发约束和发布流程。历史版本流水账不再作为主体；需要追溯时使用 Git history 和各版本 Release Notes。

## 1. 产品原则

1. 日常操作优先：核心启停、系统代理、TUN、策略切换和连接观察必须少步骤完成。
2. 设置与工具分离：设置描述长期偏好；高级工具只承载安装、维护、备份、安全与排障。
3. 配置优先：用户 Profile 和覆写是事实来源，应用设置只是默认值。
4. 状态可解释：网络接管、资源更新、配置合并和失败恢复都要显示来源、结果和下一步。
5. 安全失败：下载、路径、更新和恢复在校验失败时保留旧状态，不做破坏性替换。
6. macOS 原生：优先使用 SwiftUI scene、Toolbar、Settings、List、split view 和 accessibility 语义。

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
| Network | 系统代理/TUN/DNS 模式、DNS 与恢复 | Artifact 安装 |
| Resources | Provider、本地规则集、Geo 更新与回滚 | Web Controller |
| Advanced | Helper、LaunchDaemon、Artifact、备份、安全、诊断 | 常用设置重复项 |
| Settings | 通用、远程访问、高级默认值 | 备份与维护动作 |

### 2.2 AppStore

`AppStore.swift` 保存共享低频状态和 service 实例。领域行为按 extension 拆分，例如：

- `AppStore+CoreLifecycle`
- `AppStore+ControllerStreams`
- `AppStore+Profiles`
- `AppStore+ConfigEditing`
- `AppStore+Resources`
- `AppStore+NetworkTakeover`
- `AppStore+Backup`
- `AppStore+SoftwareUpdate`

高频连接、流量和日志不直接堆在 AppStore：

- `RuntimeActivityStore`：活动连接、最近请求、速率、分组流量样本与 event stream 状态。
- `LogStore`：可见日志、暂停缓冲与增量发布。
- `LogPersistenceWriter`：串行、批量持久化，避免每条日志触发磁盘 IO。

### 2.3 Services

Service 应尽量可独立测试，并返回结构化结果：

- `RuntimeConfigBuilder`：合并最终配置。
- `ProfileYAMLStructureEditor`：策略组/规则的结构化增删改。
- `ProfileQualityAnalyzer`：字段来源、差异层级和 schema 风险。
- `ProviderResourceManager`：远程更新、本地校验、备份与回滚。
- `NetworkSecurityCenter`：接管与快照展示模型。
- `SoftwareUpdateManager`：版本发现、下载校验和替换脚本。

### 2.4 XPC Helper

Helper 执行需要权限的行为：

- core start/stop/restart；
- system proxy 与 system DNS 修改/恢复；
- TUN 路由和快照恢复；
- LaunchDaemon 管理；
- 权限与路径审计。

主 App 不应通过 shell 绕过 Helper。新增 Helper operation 时，需要同步：共享协议、client、service、transaction result、诊断和测试。

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

`RuntimeConfigBuilder` 先生成应用默认 overlay，再用配置结果覆盖它。禁止重新引入“删除 Profile 同名字段后由 App 强制接管”的旧行为。

### 3.2 生成流程

1. 从 `ProfileStore` 读取当前 Profile。
2. 执行启用的 JS Transform，worker 有输入/输出限制和超时。
3. 合并启用的 YAML 覆写。
4. 用结果覆盖应用默认值。
5. 删除禁用规则，生成 candidate。
6. 执行 `mihomo -t`。
7. 校验通过后替换 runtime config；失败保留旧配置。

### 3.3 配置质量

质量总览、字段来源与合并层级共享一个连续分段容器。问题区与运行时摘要纵向排列，避免等高双栏在问题较少时产生大片空白。出站检查将 inline `proxies` 和 `proxy-providers` 视为等价来源，只有两者同时为空才发出警告。

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
- 恢复：代理、DNS、TUN 的独立快照和修复中心。

系统代理与 TUN 在交互上互斥。系统 DNS 可以独立启用，但必须使用独立快照。任何恢复逻辑都不能复用其他模式的 snapshot。

Activity 的 DNS 是连接工作区内的只读观测视图，数据来自最近连接中的域名、目标地址和来源信息；它不能跳转到 Network/Settings，也不能承担运行时 DNS 或 macOS 系统 DNS 的配置职责。Activity 顶部分段只保留“最近的请求 / 活动连接 / DNS / 流量统计”，设备与日志簿不属于该工作区。

独立 Logs 页面按“全部 / 常规 / 网络切换 / DHCP”筛选 App 与 core 事件，并使用“时间 / 分类 / 标题 / 详情”表格展示。Mihomo 没有脚本事件模型，因此不得为了模仿其他客户端而添加脚本分类。

## 5. 资源更新模型

资源统一建模为 `ProviderItem`，通过 `ExternalResourceRow` 形成展示状态。

更新规则：

- 有 `remoteURL`：下载到受限 runtime path，校验后备份并替换。
- 无 `remoteURL` 但有 path：执行本地重新载入/校验。
- 全部更新：按并发限制处理所有 Provider，最后更新 Geo 数据。

本地校验包括：路径约束、文件存在、非空和 mapped read 可读性。详情中不能展示 URL query/fragment，避免泄露 token。

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
APP_VERSION=1.8.80 ./script/build_and_run.sh --verify
```

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
5. 执行：

```bash
./script/package_release.sh 1.8.80
./script/release_smoke_test.sh 1.8.80
```

6. 检查 zip、versioned manifest、latest manifest 和 provenance。
7. 提交并 push branch。
8. 创建 `v1.8.80` tag，不移动旧 tag。
9. push tag。
10. 创建 GitHub Release，上传 zip 与 `mihomo-update.json`，正文使用 `docs/releases/v1.8.80.md`。

## 11. 当前技术债务

- ad-hoc 签名版本未 notarize；Developer ID 发布仍需受保护环境。
- AppKit bridge 仍需定期做真实 VoiceOver/keyboard QA。
- 350 行以上文件应在后续触碰时继续拆分，500 行为强优先级阈值。
- Profile 覆盖 `external-controller` 时，App 连接 endpoint 与最终 Runtime endpoint 的一致性仍需持续验证，避免配置与 UI 状态分离。
- 网络接管真实异常路径需要持续沉淀 before/after smoke 证据。

# Mihomo 网络数据面

本文描述当前网络接管的边界，避免把 macOS 系统 DNS、Mihomo 内置 DNS 和 TUN 路由误认为同一种功能。

## 数据路径

```text
遵守 macOS 代理的应用 ──> 系统 HTTP/HTTPS/SOCKS 代理 ──┐
                                                        │
不遵守系统代理的应用 ──> TUN + auto-route ──────────────┼─> mihomo
                                                        │
TUN 中的 UDP/TCP 53 ──> dns-hijack ──> Mihomo DNS Server ┘
                                      ├─ Fake-IP 映射
                                      ├─ nameserver / policy
                                      └─ 规则系统

TLS/HTTP/QUIC 握手 ──> Sniffer ──> Host/SNI/sniffHost ──> DNS 映射与规则重选
```

## 五个开关的职责

- 系统代理：只修改 macOS 网络服务的 HTTP/HTTPS/SOCKS 代理设置。启用与 TUN 相互独立。
- TUN：接管不遵守系统代理的透明 TCP/UDP 流量；开启时运行配置强制具备 Mihomo DNS 和 `dns-hijack: any:53`。
- Mihomo DNS：运行在核心内部，负责 Fake-IP、nameserver、nameserver-policy 和规则感知解析。
- macOS DNS 兼容模式：仅在特殊场景改写系统 DNS，拥有单独快照；不是 TUN DNS 的替代品。
- Sniffer：读取 HTTP Host、TLS SNI、QUIC 元数据及 DNS 映射，把 IP 连接补全为域名后交给规则系统。

## 恢复边界

系统代理、系统 DNS、TUN 路由分别使用独立快照和恢复动作：

- 恢复系统代理不会改写 DNS。
- 恢复系统 DNS 不会关闭代理端口。
- 恢复 TUN 只回滚 TUN 新增路由，并恢复 TUN 捕获的 DNS 基线。
- 应用退出时按独立计划执行各项恢复，避免一个功能覆盖另一个功能。

停止核心不是仅更新界面状态。Helper 的 core supervisor 在 daemon 生命周期内跨 XPC 连接共享，并会发现受信任 App Support 或 App Bundle 路径下的遗留 mihomo 进程。停止事务按 `SIGTERM`、`SIGINT`、`SIGKILL` 分级等待，只有确认 core 真实退出后才恢复 TUN/DNS 快照；任何阶段仍有受管 core 存活都会使停止事务失败，而不是提前显示“已停止”。

## Helper 部署边界

网络接管动作需要 root 权限，当前支持两种部署方式：

- 正式发行：Developer ID 签名并完成 Apple notarization 后，通过 `SMAppService` 注册 App Bundle 内的 LaunchDaemon。Helper 或 plist 更新前先等待旧服务完整注销，新 App 启动后再注册。
- 无开发者账户兼容路径：主 App 与 Helper 没有匹配的稳定 Apple Team 签名时，App 跳过无效的 SMAppService 批准等待；用户明确授权后，将 Helper、LaunchDaemon plist 和授权文件安装到 root 所有的 `/Library/PrivilegedHelperTools` 与 `/Library/LaunchDaemons`。授权文件绑定当前 App 的绝对路径、bundle identifier 和签名 CDHash，避免其他同名 ad-hoc App 连接 root Helper；每次 App 更新后必须重新授权绑定。

`CFBundleVersion` 必须是一至三段数字，不能再使用 Git 短哈希。Developer ID 发布校验主 App、Helper 的 TeamIdentifier 与 notarization；显式启用的 ad-hoc Release 则由 Ed25519 manifest 固定 zip SHA-256 和主 App/Helper CDHash，用户需自行执行 `xattr -cr`，两种模式不能混淆。

## Sparkle 对照

本项目参考 `xishang0128/sparkle` 的公开实现：TUN 开启时联动 Mihomo DNS、Fake-IP 和 Hijacking；Connections 使用 `/connections?interval=500` 的完整快照；Sniffer 默认支持 HTTP/TLS/QUIC、纯 IP 解析和 DNS 映射。项目保留自身的 App 管理配置同步、Helper 事务快照、连接历史和策略流量统计能力。

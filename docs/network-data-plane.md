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

## Sparkle 对照

本项目参考 `xishang0128/sparkle` 的公开实现：TUN 开启时联动 Mihomo DNS、Fake-IP 和 Hijacking；Connections 使用 `/connections?interval=500` 的完整快照；Sniffer 默认支持 HTTP/TLS/QUIC、纯 IP 解析和 DNS 映射。项目保留自身的 App 管理配置同步、Helper 事务快照、连接历史和策略流量统计能力。

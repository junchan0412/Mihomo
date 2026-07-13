# Profile 与 App 设置同步设计

## 目标

Profile 是代理运行参数的配置来源，App 是这些常用参数的图形化编辑入口。两者不再维护相互独立、容易漂移的副本。

## Profile → App

启用、导入或刷新 Profile 时，Mihomo 读取其中已经声明的以下字段并更新 App：

- `mixed-port`、`socks-port`、`allow-lan`、`log-level`；
- `tun.enable`；
- `dns.enhanced-mode`、`dns.nameserver`、`dns.fallback`；
- `sniffer` 的启用状态、协议端口、识别方式和例外规则。

Profile 没有声明的字段继续保留 App 当前值，不会被空值覆盖。

## App → Profile

用户应用设置时，`ProfileSettingsSynchronizer` 比较保存前后的配置关联字段，只把发生变化的部分写回当前 Profile：

- 保留代理节点、策略组、规则、Provider 和未被 App 管理的嵌套字段；
- SOCKS 端口设为 `0` 时删除 `socks-port`；
- 关闭 TUN 或域名嗅探时写入明确的 `enable: false`；
- App-only 设置变化不会重写 Profile。

远程订阅修改的是本地缓存副本。下一次刷新订阅时，远端内容重新成为来源，并再次载入 App。

## Runtime 优先级

最终运行配置仍按以下顺序合并：

```text
App 默认 < Profile < JS Transform < YAML 覆写
```

同步不会把 JS Transform 或 YAML 覆写写回 Profile。`external-controller` 与 `secret` 为确保客户端能够连接自身核心，仍在最终合并后由 App 强制设置。

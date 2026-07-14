# 覆写来源与订阅设计

## 数据模型

每个 `ConfigFragment` 除名称、类型、状态、内容和作用范围外，还保存：

- `source`：`local` 或 `remote`。
- `location`：原始文件路径、远程 URL，或为空表示手动创建。
- `certificateFingerprint`：首次 HTTPS 下载观察到的叶证书 SHA-256 指纹。

旧 JSON 未包含这些字段时使用 `local`、空路径和空指纹，保证无损向后兼容。

## 导入与刷新

- 本地导入按扩展名识别 JavaScript，其余默认 YAML，并保留原始文件路径。
- URL 导入由用户明确选择 YAML 或 JavaScript；下载成功后保存 URL 和证书指纹。
- 远程刷新使用保存的指纹进行 TLS pinning，内容校验成功后才替换内存与磁盘数据。
- 单个刷新失败不会清除旧内容；全部刷新允许部分成功，并在页面显示成功和失败计数。
- 全局“刷新所有订阅”和自动刷新同时处理 Profile 与远程覆写。

## 运行时语义

来源只决定覆写如何导入和刷新，不改变合并优先级：

```text
App 默认 < Profile < JS Transform < YAML 覆写
```

`ConfigFragment` 数组顺序仍是应用顺序；后面的同类型覆写可以覆盖前面的结果。来源字段不会写入最终 mihomo YAML。

## UI 边界

- 覆写主页面负责选择、批量操作、导入、刷新、顺序和摘要。
- 独立编辑器窗口负责内容、类型、状态与作用范围，避免主页面恢复旧式左右分栏。
- URL 导入使用 sheet，因为它是短暂且有明确完成点的任务。
- 表格、上下文菜单、Return、Space、Delete、搜索和 Undo/Redo 保持 macOS 桌面交互一致性。

# Vault 逐条读取来源设计

已授权依据：完整目标要求继续完成原始计划；全量审计 V02/V03/V18 明确登记逐条版本/时间与混合 KV 版本缺口。仅完善现有 Vault 工具，不新增工具或生产连接。

保留现有 GET 白名单、非生产范围确认、KV 识别和整批失败规则。从同一响应取得业务配置与白名单 metadata，不额外请求 metadata endpoint。独立 metadata GET 会增加 ACL 和请求范围；把 metadata 当业务配置比较会产生无关差异，均不采用。

Rust 增加 inspectVaultRead：明确 kvVersion=1/2，严格解析整个响应及重复键，再提取配置根和可选版本、创建/删除时间、destroyed。返回独立 vaultMetadata DTO，业务配置仍是保留精确数值和 UTF-16 的文字。版本使用精确正整数字符串；时间须有效 RFC3339，错误不回显内容。custom_metadata 不进入来源信息。没有 metadata 时未知字段为 null；KV v1 不编造 secret 版本。已确认删除/销毁不输出业务配置，Reader 停止整批并给出明确错误。

VaultReader.Validator 统一接收 raw 和可选 KV 版本，返回 CoreResponse：LIST/识别仍走 validateJson，secret GET 走 inspectVaultRead。VaultCaptured 新增逐条观察记录，包含相对配对键、实际 namespace/path、KV 版本、元数据和本机该请求开始/结束时间。记录只用于来源展示/报告，不进入业务差异键。

App 成功结果保存两侧来源；范围变化/切工具/取消按现有生命周期清除，旧结果保持过期保护。选中业务行按两段 UTF-16 配对键定位 A/B 来源；全局来源列表最多显示前200条，完整 JSON 报告保留全部。MCP 来源绑定成功 session、独立来源范围及授权，分页保留，授权撤销拒绝返回，四会话驱逐同时释放来源。来源类型不包含 Token；默认 includeValues=false 继续不返回配置值。

证明：Rust 静态协议红绿覆盖 v1/v2、缺失/损坏 metadata、软删除/销毁、重复键、大数/UTF16；真实核心 Swift 覆盖两侧不同 URL/Token/namespace/mount/配置名与 KV v1/v2、App/MCP 比较不受 metadata差异影响、分页/撤销/清理、来源序列与 Token 不泄漏；本机 fixture/XPC/MCP 和实际 GUI 另留证。原12门禁及同候选 CC/DS 独立复审必执行。

边界：此增量不证明用户实际 Vault 部署、原子快照、未读 secret 存在性或完整设备/无障碍/性能验收。HTTP404/403 不变成删除/缺失；V11 的完整失败来源 GUI 与真实部署必须按实际证据另行判定。

执行修订：明确 HTTP 状态传到 Rust，成功类型改为 `(Node, ReadMetadata)`；删除／销毁直接错误，不再返回 ok+null。404 只对KVv2 secret读响应按标准外层包装、data仅data/metadata、显式null业务体、有效version/destroyed核对；未确认仍HTTP404。deletion_time可能计划未来删除，可读业务对象保持readable，原样展示删除／计划删除时间，不依赖本机时钟。来源列表放在右侧可滚动详情区，保持小窗口主差异表可点击。独立讨论CC与DS仅设计反馈，最终冻结实现仍需双评审。

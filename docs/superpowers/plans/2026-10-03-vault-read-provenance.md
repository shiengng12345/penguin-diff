# Vault 逐条读取来源实现计划

> 执行方式：本会话按 executing-plans 执行已授权范围，逐步留证，不提交/推送/发布。原始完整目标、91用例和双评审要求保持不变。

目标：补 V02/V03/V18 的逐条来源与混合 KV 纵向链路，metadata 不改变业务差异。

架构：Rust 严格解析；Swift 传输与来源生命周期；App 展示与 JSON 报告；MCP 按授权 session 返回。栈：现有 Rust/serde、SwiftUI/AppKit、XPC、stdio MCP，无新增运行依赖。

- [x] 1. 新建 crates/compare-core/tests/vault_provenance.rs。请求 `{"op":"inspectVaultRead","source":"{\"data\":{\"data\":{\"big\":9007199254740993,\"huge\":1e10000,\"s\":\"\\ud800\"},\"metadata\":{\"version\":7,\"created_time\":\"2026-10-03T01:02:03.123456789Z\",\"deletion_time\":\"\",\"destroyed\":false}}}","kvVersion":2,"httpStatus":200}`；独立断言 text 保留三种值、vaultMetadata.version="7"、custom_metadata 不输出。另加 v1、未知字段、删除/销毁、无效版本/日期、重复键。运行 `rtk proxy cargo test --locked -p compare-core --test vault_provenance`，保留旧实现 OPERATION_INVALID 的实际红。
- [x] 2. 新建 crates/compare-core/src/vault_input.rs，定义 `ReadMetadata { kvVersion:u8, version:Option<String>, createdTime:Option<String>, deletionTime:Option<String>, destroyed:Option<bool>, state:String }`。按白名单验证并返回 `(Node,ReadMetadata)`；lib.rs 注册 inspectVaultRead，使用既有 source20MiB/json_input100000节点/重复键/深度保护。运行同一 Rust 测试至绿，再 fmt/Clippy。
- [x] 3. CompareShared/WireModels.swift 添加 Codable/Sendable/Equatable VaultReadMetadata 与 CoreResponse.vaultMetadata；VaultReader.Validator 改为 `(String,Int?,HTTPStatus) async throws -> CoreResponse`。Workspace.makeVaultReader、MCPService.reader、validatedFixture 明确构造 validateJson 或 inspectVaultRead 请求；Reader.capture 将 text 作为 plain-object 配置并独立保存观察记录。预览仍返回 canonical JSON；metadata 不经过 Foundation 对业务数字重序列化。
- [x] 4. 新建 apps/macos/Tests/CompareTests/VaultProvenanceTests.swift：合成传输分别识别 v1/v2，每个 GET 核对 URL/Token/namespace/mount，返回相同值但不同 metadata；现有 MCPService.vault_compare 首次应缺少 vaultSources，保留运行期红。补 App 状态、同/混合 KV、精确值与 UTF16、错误/取消/授权撤销与四会话来源清理。实现 VaultReadObservation、两侧来源 DTO；App/MCP 同样保存来源，MCP report 分页附加来源并维持授权终态检查。
- [x] 5. ConfigCompareApp/新 VaultSourceView 显示两侧请求与实际版本；missing 元数据用本地化未知，成功结果的来源列表显示前200条且完整报告保留全部；详细行按 segments 两个 keyUnits 匹配。AppPreferences 增加中英文。Report 新增 vaultSources 和 snapshotAtomic=false；既有业务摘要/报告数值不变，Token 不出 DTO。
- [x] 6. 运行相关 Rust/Swift 红绿与已有 Vault/生命周期/MCP 测试。执行 `rtk proxy python3 scripts/verify-local.py` 的全部12门禁，冻结新清单并核验 App/ZIP；本机合成网络/包内 XPC/MCP 与实际 GUI 另留证，不连接实际 Vault/生产。CC/DS 对同一新候选独立接受前继续修复；保留原会话终态处理超时。
- [x] 7. 更新主计划、开发记录与全量审计；按实际证明逐项调整 V02/V03/V18，保留 V11 全矩阵、真实部署、设备/发行/IME/VoiceOver/性能未证明项，不宣称整个目标100%。

自审：所有来源字段有明确输入/输出和未知处理；不扩大请求范围或解释404为缺失；Token类型留在VaultTarget；DTO/真实核心/包/GUI/双评审分别证明，不互相冒充。

2026-10-03 进度：原始 Rust5运行期红及Swift MCP缺来源运行期红均留证；Rust5绿、Swift来源6专项绿及真实loopback App/MCPService混合KV流程通过。新增类型路径映射后完整12门禁进行中；任务4的完整取消/失败来源UI矩阵未全量关闭，任务6双评审/新包GUI仍待当前候选完成。

后续实际GUI暴露：合成KVv1根LIST路由遗漏已修正并保留404停止记录；来源区移到右侧详情，避免小窗口差异表被挤压。官方计划删除/404真实包装核验及CC/DS独立设计讨论后，增加显式HTTP状态、404包装白名单、计划删除可读和已删除/销毁直接错误；这不是实现接受。新增真实运行期Rust与Swift红绿，修复测试错误的空白期待，不改变业务值语义。当前完整门禁/新包GUI/冻结实现双评审仍需重新完成。

本增量执行完成：2026-10-03 · 1.7 当前来源增量：冻结候选 `e84a5f23b1f8a9e7c1f765b23ccbc3168fac3567e5ec5d04715751aff087b64f`（127文件）的[12项本机门禁](evidence/2026-10-03-vault-provenance-final-results.json)通过（Rust93 / Swift114 / Python17，共224项），真实HTTP/TLS11例、Debug/Release可信Node对照、188资源探针、包内XPC/stdioMCP继续通过。[新包GUI](evidence/2026-10-03-vault-provenance-final-gui-proof.json)验证混合KV、四笔来源、KVv1未知、KVv2计划删除可读、右侧展开不挤压表格、中英文整页设置返回、完整JSON来源、已删除/销毁/未确认404整批失败及恢复；重预览/重读取不保留旧行来源，原用户三行多变量结果已恢复。[包核验](evidence/2026-10-03-vault-provenance-final-package-check.json)通过。[CC/DS同一新候选独立接受](evidence/2026-10-03-vault-provenance-final-review-synthesis.json)；只接受本增量，完整91项、读期间修改/回退、真实非生产部署、完整GUI/IME/VoiceOver/性能、目标设备与正式发行仍OPEN。没有真实Vault或生产访问。

任务4列出的合成控制器/协议/生命周期样本已完成；这不关闭全量失败来源UI或实际部署。任务6是当前局部实现的完整12门禁、新包GUI、双评审；任务7已更新审计，完整目标仍active。

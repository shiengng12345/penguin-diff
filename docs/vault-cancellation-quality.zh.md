# Vault 取消、重试与迟到响应专项

> 2026-10-04 · 本地增量候选 `088678478a170a3d9b4283ea7f6f53dd9819c03200d52a098dc5f4fab5b710d6`，正式门禁运行 `cbb07a34-02e9-48cc-9956-f35d4faa493f`。

这轮只补 Vault 读取生命周期的本机证据，不连接任何真实或生产 Vault。`GatedVault` 是 `VaultTransport` 的进程内合成传输，故意把一个 data 回复挂起，再在取消或范围变更后释放它。

## 已验证

- `vaultLaterSecretFailureStopsBatchAndRetryStartsFresh`：KV v1/v2 各覆盖 403、404、429、503。前面的成功读取不会作为部分结果返回；失败后不读取后续 secret；同一计划重试会重新识别 mount，并从第一条 secret 开始。
- `vaultCaptureCancellationDiscardsPartialEntriesAndRetryStartsFresh`：首个 data 请求被挂起，取消任务后释放迟到回复，任务返回 `CancellationError`，没有部分 entries；随后重试得到完整两条结果。
- `vaultLateResponseAfterScopeChangeCannotRestoreStaleWorkspace`：Workspace 比较过程中修改 A 侧 environment 会清空计划、结果、来源和诊断；旧请求随后完成也不能恢复旧结果。

## 本轮门禁

- `verify-local.py`：15/15 通过；Swift 245 tests／30 suites；loopback HTTP/TLS 通过；`manifestStable=true`；`realVaultAccessed=false`；`formalReleasePassed=false`。
- 定向记录：[build/vault-cancellation-focused.log](../build/vault-cancellation-focused.log)。
- 主门禁证据明确绑定 `build/verification/candidate.manifest.sha256` 与 `final.manifest.sha256`，两者 SHA-256 都是 `088678478a170a3d9b4283ea7f6f53dd9819c03200d52a098dc5f4fab5b710d6`；结果 JSON 与定向测试源码的文件哈希也记录在[本轮证据](evidence/vault-cancellation-main-rerun.json)。
- 本地包的 NOTICE、资源、ad-hoc 签名和 packaged self-test 均通过；包 SHA-256：`4193302280d908217d9653b3b8ba282f1e3eb416ba5dd156386cd46168e0e084`。

## 边界

这些测试证明了 Reader／Workspace 的取消和 generation 守卫，不能代替真实非生产 Vault 的网络断开、代理超时、服务端限流或真实桌面操作。它们也不能代替打包后 worker 被外部终止、VoiceOver／输入法／真实剪贴板和正式发行验证。当前没有自动重试／退避策略；重试证据是调用方显式重新发起，并且必须使用干净批次。

本轮将 V15、V16 从纯 OPEN 调整为“本机模型部分通过”，不宣称完整关闭。全量 91 项严格分类为：51 项完整关闭、26 项部分证据、14 项纯 OPEN；完整关闭率仍为 56.0%。

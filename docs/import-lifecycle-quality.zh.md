# 导入生命周期 N2 修订记录

> 日期：2026-10-04。本文只记录导入取消与迟到完成的本地质量增量，不代表完整产品目标、真实 GUI、设备、非生产部署或正式发行验收。

## 结果

冻结候选源码清单 SHA-256 为 `d73132e2c1b6512054cfd99fc8015f82368eb368eb8f1852d254c6a04de8ec00`，331 个清单文件。隔离工作区执行 `rtk proxy python3 scripts/verify-local.py`，runID 为 `43db92fa-cc0d-41a8-af07-fb4ab0790e76`：15/15 命令退出码为 0，`passed=true`、`finished=true`、`manifestStable=true`、`realVaultAccessed=false`，正式 Release 字段保持 `formalReleasePassed=false`（本机门禁不会冒充设备或发行验收）。主工作区随后执行 `swift test --no-parallel --package-path apps/macos`，236 tests／30 suites 通过；导入专项 10/10 通过。

Claude Code 与 DeepSeek 审查的是同一个 SHA，均返回 `ACCEPT_LOCAL_CHANGE`、阻塞问题为空；评审记录见[Claude 证据](evidence/import-lifecycle-quality-cc.json)、[DeepSeek 证据](evidence/import-lifecycle-quality-ds.json)和[综合记录](evidence/import-lifecycle-quality-review-synthesis.json)。DeepSeek API 实际返回模型为 `deepseek-flash`；它只做文本审查，没有本机执行能力。

## 改动

- `Workspace` 新增默认空的 `@MainActor importFinished` 注入钩子。`importFile` 的 Task 用 `defer` 调用它，因此成功、读取失败、旧 token 被 guard 丢弃三种出口都在 Task 真正结束后通知。正式构造点不传该参数，生产运行时仍使用空闭包，不访问 Vault、网络或凭证。
- `ImportLifecycleTests` 新增 MainActor `ImportDeliveryProbe`。五处原来依靠固定 10ms 的等待改为等待 probe 完成计数精确增加，并同时断言迟到结果没有覆盖输入、文件 URL/标签、YAML 输出、notice/error 或新导入状态；双侧取消用例等待两个 Task 都结束。
- 既有 `importTokenA/B`、`stopImports`、`changed(side:)` 和成功/失败 token guard 未改变。覆盖了取消后的迟到成功、取消后的迟到失败、旧导入被新导入替换、双侧同时取消和工具切换后的迟到失败。

## 强度验证

为验证测试不是只等待 continuation `resume`，临时移除成功 token guard 后执行专项测试：10 个导入测试中 4 个按预期失败；突变源码随后恢复，当前候选源码与恢复副本逐字节一致。这个负向实验没有进入产品或最终清单。

包核验来自同一候选 Release 输出：`build/Config Compare Import Lifecycle Quality.app` 通过 `codesign --verify --deep --strict`，ZIP SHA-256 为 `7ae09c606a66eda3a248bb8eff467133d7676e671d7690a7b2d2869e947b3983`。15 项门禁中的 HTTP/TLS 是本机回环测试；打包 MCP 只使用合成输入，输出明确 `Vault I/O: NOT_RUN`。没有启动或切换用户 App，没有读取生产 Vault，没有使用真实 Token，也没有提交或推送。

## 尚未关闭

本轮只关闭 N2 导入等待测试强度。N4 Unicode 行／分组一致性、完整 GUI/键盘/IME/VoiceOver/性能、目标设备、获准非生产真实 Vault、正式签名发行和原始完整目标仍保持 active。

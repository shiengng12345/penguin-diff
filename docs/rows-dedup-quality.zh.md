# 行请求去重修订

2026-10-04 后续状态：N4 Unicode 行／分组显示一致性已由 e503684dc4c354c2b0c96bcd493e1a60ad187cb9fc1d41cbb617059a5d833154 关闭；本页 N3 证据仍保留为历史修订。

2026-10-04。本轮修复结果页在同一页、同一筛选条件下被重复请求的问题。SwiftUI 的筛选变化和比较完成回调都可能在同一轮主线程中请求第一页；现在只合并完全相同且仍在途的 rows 请求，结果提交、分页、错误和过期保护保持原行为。

## 实际修改

- `apps/macos/Sources/ConfigCompare/Workspace.swift` 增加 `RowsRequestKey`，键包含 `session`、页码、筛选、搜索文本和搜索范围。只有 key 完全相同的在途请求会被跳过；不同页、不同筛选、不同 session 仍会生成新请求。
- `rowsToken` 继续作为结果提交令牌；Task 的 `defer` 只在 token 仍属于当前请求时清除 `activeRowsRequest`。失败、取消、过期和停止路径不会把旧任务状态清到新请求上；停止操作会同步清除去重状态。
- `RowsTransactionTests.swift` 新增重复请求回归：旧实现先观察到两次 rows 请求，修订后相同在途调用只发送一次，完成后再次 `loadRows` 仍会发送新请求。原有行事务回归仍保留。
- `ResultNoticeExportTests.swift` 的重复故障等待改为等待 worker 的真实 rows 完成计数，避免已有 `error=true` 让第二次故障测试立即返回；没有改变产品逻辑。

## 验证与评审

冻结候选为 `8d0a33f5bf778c5941c545b04177d740e24d058e0ea74c5177403b553af5566a`，源码清单 331 项。隔离候选的正式门禁 runID `27fe237f-c48a-4f7d-9747-ff18f8b2337c` 为 15/15 命令 exit 0，`passed=true`、`finished=true`、`manifestStable=true`；Swift `236 tests in 30 suites passed`，Rust、JS 对照、报告、深度边界、loopback HTTP/TLS、Release ad-hoc XPC 和打包 MCP 均通过，`realVaultAccessed=false`、`formalReleasePassed=false`。正式 Swift 门禁使用 `--no-parallel`；主工作区按同一参数重跑 236/30 全绿。默认并行运行会让跨套件合成 CoreBridge 互相争用，因此其失败不计入产品门禁。

[门禁摘要](evidence/rows-dedup-quality-results.json)记录了当前 SHA、清单和包核验。[Claude Code](evidence/rows-dedup-quality-cc.json)与[DeepSeek](evidence/rows-dedup-quality-ds.json)均审阅同一 SHA 并给出 `ACCEPT_LOCAL_CHANGE`，`blockingIssues=[]`，`wholeGoalAccepted=false`；[综合记录](evidence/rows-dedup-quality-review-synthesis.json)保留评审边界。评审后的主源码、清单和专项测试由[完整性记录](evidence/rows-dedup-quality-post-review-integrity.json)核对。

本轮生成的本机包为 [`Config Compare Rows Dedup Quality.zip`](../build/Config%20Compare%20Rows%20Dedup%20Quality.zip)，SHA-256 为 `481e90eaf4c78d26e484ed942e1cda76b298a5667741524456054cff2a6771aa`。deep/strict codesign 与 `PACKAGED_XPC_SELF_TEST_OK`、`PACKAGED_SELF_TEST_WINDOW_COUNT=0` 均通过。包只用于本机验证，没有切换或关闭用户当前 App。

## 保持开放的边界

本轮没有连接任何生产 Vault，没有写入配置，没有启动、切换或关闭用户 App，也没有 commit 或 push。未把 GUI 的真实快速点击、键盘／IME／VoiceOver、目标设备、长时性能、获准非生产部署和正式签名／公证写成已验证。N2 导入取消等待、N3 重复 rows 请求与 N4 Unicode 行／分组显示均已由后续候选关闭；完整产品目标仍保持开放。详见[导入生命周期 N2 修订](import-lifecycle-quality.zh.md)与[Unicode 修订](unicode-groups-quality.zh.md)。

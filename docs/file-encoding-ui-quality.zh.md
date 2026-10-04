# 文件编码、中文路径与特殊值增量验收

> 候选源码：`a7d7f9714c8b50fedf8732dee368581387500cbf92163aa4428cb8554237008b`（331 个源码文件）
>
> 本记录只描述本轮本机自动化证据，不把它等同于完整 GUI、设备或正式发行验收。

## 本轮覆盖

本轮把两个历史上只有局部证据的边界推进到真实文件读取、匿名进程内 NSXPC 和 Workspace 行／详情模型：

- J18：UTF-8 BOM、无 BOM、LF、CRLF、中文键与中文路径；同时检查含 BOM 的首行字节列，以及两侧输入在 XPC 后仍能显示原文、警告和结果详情。
- C07：`null`、空字符串、`undefined`、缺失字段和仅一侧存在的字段保持不同状态；同时检查 String/Null、Null/Undefined、Undefined/String 的类型变化以及详情中的 `type`／`present`。

新增回归位于 `apps/macos/Tests/CompareTests/IPCLifecycleTests.swift` 与 `apps/macos/Tests/CompareTests/WorkspaceQualityTests.swift`：

```text
fileBomCrLfAndChineseWarningSurviveXPCIntoWorkspaceRows
fileLfWithoutBomAndChineseWarningKeepsByteColumnsOverXPC
bomBeforeFirstLineCodePreservesUtf8ByteOffsetOverXPC
bomAndLineEndingMatrixKeepsChineseWarningsAndDetailsOverXPC
missingNullUndefinedAndEmptyValuesRemainDistinctInRowsAndDetails
missingNullUndefinedAndEmptyValuesSurviveXPCIntoWorkspaceRowsAndDetails
```

4 个 J18 测试和新增的 C07 NSXPC 测试使用真实 `Workspace`、`WorkerClient` 和匿名进程内 `NSXPCListener`；C07 的 NSXPC 测试还覆盖 String→Null、Null→Undefined、Undefined→String 的 `TYPE_CHANGED` rows/details。另一个 C07 测试直接覆盖 `Workspace` 与进程内 `DirectCoreWorker` 的模型详情。两层证据都没有调用用户 App、真实 Vault 或生产地址。

## 已验证的门禁

| 项目 | 证据 |
| --- | --- |
| 正式本机门禁 | 15/15 命令通过，manifest 331 文件稳定 |
| Swift | 243 tests／30 suites 通过 |
| J18 组合 | BOM×LF/CRLF、无 BOM×LF/CRLF、中文警告、行与 UTF-8 字节列、行详情通过 |
| C07 特殊值 | Missing/null/undefined/empty 分离、undefined 与 Missing 分离、类型变化与详情字段通过 |
| 网络边界 | 临时 loopback only；`realVaultAccessed=false`、redirect sink 0、cookie 0、未改变证书信任 |
| 打包核验 | packaged XPC self-test、MCP、NOTICE、资源、ad-hoc codesign 均通过 |

完整机器输出见[本轮汇总](evidence/file-encoding-ui-quality-main-rerun.json)、[Swift/HTTP 日志](evidence/file-encoding-ui-quality-swift-http-tls.log)和[网络检查](evidence/file-encoding-ui-quality-network-check.json)。

## 仍然开放的边界

- 还没有把 J18/C07 标成完整关闭：SwiftUI 原生渲染、真实键盘／IME、VoiceOver、用户窗口截图和跨设备矩阵仍未完成。
- 独立打包 worker 的 GUI 压力、超深／超大文件的内存与超时验收仍是 J20 的开放项。
- malformed BOM+CRLF 的 EOF 解析错误本身没有可靠行列偏移（当前 `CoreError` 为 0/0）；本轮保留这个限制，没有伪造偏移。
- `formalReleasePassed=false`；没有 Developer ID、公证、Intel 或正式发布凭证。
- 所有 Vault 证据仍是合成 loopback；本工具继续禁止连接生产，不能把本轮结果当成真实环境连通性证明。

CC 与 DeepSeek 已各自审查同一个候选 SHA，均返回 `ACCEPT_LOCAL_CHANGE` 且 blocking 为空；DeepSeek 本次只做独立 API 评审，没有运行测试。完整差异与边界见[双审合成](evidence/file-encoding-ui-quality-review-synthesis.json)。旧候选的接受结果没有自动继承到本候选。

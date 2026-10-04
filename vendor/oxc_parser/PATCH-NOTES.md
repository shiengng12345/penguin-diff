# 本地 OXC 解析资源防护

仅 vendor crates.io 发布的 `oxc_parser 0.152.0`，其他 OXC crate 继续使用精确锁定的 registry 版本。`UPSTREAM.manifest.sha256` 保存全部 53 个发布文件的原始哈希，包括上游 Cargo.lock 和 git 元数据；`stack-budget.patch` 是仅修改 `src/lib.rs`、`src/cursor.rs`、`src/js/expression.rs` 的完整差异。`LICENSE` 从该发布版本 git 元数据中的确切上游 commit 取得，来源与哈希记录在 `UPSTREAM.json`；App 包内保留该许可。

上游默认选项保持不设预算。本项目仅在 `compare-core::process` 所创建的 8 MiB scoped 线程内调用解析器，显式配置 6 MiB 栈位移预算，给诊断、相邻 token 推进之间的调用、返回路径保留约 2 MiB。标记地址经 `black_box` 保留，比较整数地址的绝对差，无解引用、无新 unsafe。预算要求调用方提供足够栈；它不是任意调用线程的 OS 栈查询。

同时限制 3,000,000 次 token 推进、重新词法分析及 rewind 操作，包括 lookahead 的重试。早期 600,000 上限会误拒仍在原有节点/静态求值限制内的 40,000 个括号内 undefined 字段；修订预算并增加 40,000/99,000 字段回归，不降低原有支持。此限制约束宽输入的解析工作，独立于原有 20 MiB 文件、128 层静态值/语句及静态求值步骤限制。字符串、注释、正则模式中的括号不会被粗略统计为语法嵌套；正则依旧由原解析器按上下文扫描。项目关闭 OXC 正则 AST 解析 feature，正则 crate 仍可由其他 OXC 依赖引入；静态 helper 不执行正则或 JS。

检查覆盖普通推进、JSX、正则、模板、尖括号重词法分析、初始 token 与 rewind。超过任一预算后，`resource_exhausted` 持续为 true，不存入 checkpoint，rewind 不能将其清除或恢复输入位置。使用原有 fatal-error/EOF 流程退出，不用 panic、unwind、全局 hook 或自动扩栈。`js_input` 在处理语法诊断之前把该状态映射为 `RESOURCE_LIMIT`。

checkpoint 本身不改变当前 token。早期版本在 checkpoint 前注入 EOF，破坏箭头函数 lookahead 的既有状态假设，触发 `unreachable!`；该失败证据已归档，当前补丁改为在实际 token 操作及 rewind 时检查。

读取正则时若预算耗尽，EOF 不再是有效正则 span。`parse_literal_regexp` 必须在任何切片之前检查 `resource_exhausted`，沿原有 unexpected/dummy 路径退出。CC 在旧候选实测该越界 panic，Codex 复现；新增小预算全部相位、flags/前缀扫描和大输入偏移回归防止重现。Debug/Release 的具体语法嵌套拒绝点可能不同，因为实际编译栈帧不同；两者都须保留合法 128 层静态值与控制错误/恢复契约。

升级必须手动审计所有新增 token 写入点及递归路径，重新生成上游清单和补丁，运行 `scripts/check-depth-guards.py` 的 Debug/Release 隔离矩阵、完整 Swift/C ABI/XPC 回归，并取得 CC、DS 对同一冻结候选的复审。现有测试是本机证据，不证明尚未验证的 Intel、macOS 14 或完整设备资源门槛。

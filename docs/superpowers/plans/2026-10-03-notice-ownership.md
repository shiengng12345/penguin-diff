# 最新提示与错误归属

承接85ea候选CC发现的残余问题；用户所有原始功能和完整验收范围保留，禁止生产连接。

- [x] 五项回归在原85ea Workspace运行：导出、非文件导入、停止、编辑4项失败，共5条断言，变量刷新成功正向1项通过。
- [x] 复制使用原生独立命名NSPasteboard，不读取或写入系统general剪贴板。先观察新增pasteboard参数API编译失败；只引入原生依赖参数、不改提示行为后，再观察实际复制后错误残留及重试覆盖提示的2条运行期失败。
- [x] 统一publishNotice(message,isError)，新状态同时替换错误标记并撤销旧行错误归属；行失败仍在describe后取得归属，只有自己的重试能恢复当前比较提示。所有成功/失败/停止/新比较路径经过统一发布。
- [x] 40项专项回归绿，包括6项新增、完整ResultNoticeExport/RowsTransaction/VaultReportExport/ImportLifecycle；保留不完整/非原子披露及更晚变量刷新错误。
- [x] 冻结源码复制到隔离验证目录、13项完整门禁、ZIP/包/签名，原正在使用的App不退出、不替换。
- [x] CC/DS独立检查同一最终候选、证据完整性及主文档更新。

用户正在编辑窗口：本次不做任何GUI输入、设置、点击或重新启动。新候选测试包在隔离目录，当前运行窗口仍为85ea候选，不能将历史GUI冒称新代码的图形层验收。Rust编译缓存共享，源码及Swift/App输出独立；原包哈希在隔离构建前后核验。复制测试使用自己的命名剪贴板并释放该资源，不检查系统剪贴板数据；不将其代替真实GUI复制/恢复全矩阵。

原N-B快速分页/加载、N-D共享超时、详情选择交错、N2/N3/N4、完整91项/GUI/键盘/IME/VoiceOver/性能、包内worker运行中退出、干净设备、明确获准真实非生产、许可证及正式发行仍OPEN，完整目标保持active。

最终候选`db0c3726fb20270ce7fa946b1a98c5d5e3a05a188aa0ca814ff43589cae82771`（135文件），[隔离13门禁/292测试](../../evidence/2026-10-03-notice-ownership-final-results.json)、[包/ZIP/签名](../../evidence/2026-10-03-notice-ownership-final-package-check.json)、[同候选双评审](../../evidence/2026-10-03-notice-ownership-final-review-synthesis.json)、[评审后源/提示/包与原App完整性](../../evidence/2026-10-03-notice-ownership-final-post-review-integrity.json)均已核验。CC原会话4b204ff4-9f34-4492-8b63-0ffc22369d99正常exit0/timedOut=false；仅3个源码哈希/搜索实执行，不把摘要错误缩写当证明。DS仅阅读材料；关于后来的错误被覆盖的推断已依当前代码与现有回归纠正。

当前源修复已完成且测试包可审阅；用户当前GUI仍85ea，不自动替换/退出使用中的窗口，不把当前旧GUI当新候选证明。下一项继续分页/加载、迟到导入完成和Unicode显示等原定门槛，完整目标未完成。

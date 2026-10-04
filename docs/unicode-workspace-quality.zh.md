# 原生配置页面：Unicode 原文同步与结果过期

> 最新[许可证／NOTICE资源交付](license-delivery-quality.zh.md)：0fd389候选315项源码、14门禁／361项命名测试、105份原生渲染、新包177文件及同候选CC／DS独立源码接受通过；仅开发构建与本地资源增量已合入。当前App与输入保留，完整目标／正式发行仍active。

> 历史[测试记录与自有进程组清理](run-lifecycle-quality.zh.md)：同一ed3423候选13门禁／345项命名测试、105份原生渲染、ZIP核验与CC／DS独立源码接受通过；两个脚本已合入，当前App与输入保留。完整目标仍active。

> 当前主源码已更新为36fbb707／143文件：[Vault四尺寸滚动与整次测试门禁](minimum-window-and-run-gate.zh.md)通过13门禁／335项测试、105份原生图像和同候选双源码接受；当前App与输入保留，完整目标仍active。下文具体哈希、计数与结论属于原候选历史。

> 后续[Vault表单修订](vault-form-quality.zh.md)已将名称与非生产确认调整为三尺寸首屏完整可见，并补原生绑定回归；本文05f0／322项为历史。本Unicode源码修订保留在当前8a6e／325项候选。

2026-10-04。此项是白鹅原生界面的输入／结果交互修订，沿用 SwiftUI、AppKit 与 Rust 核心。完整目标继续 active，不连接真实 Vault 或生产，不执行配置代码。

## 已复现的问题

`é` 与 `e` 加组合重音看起来相同，Swift String 的相等判断也将其视为相等，但原文 UTF-16 不同。已有 Rust 比较核心正确区分两者；页面却用普通 String 相等判断监听输入，漏掉变化。外部替换还可能被 SwiftUI 的原生视图更新判断忽略，显示旧文本。

在完整 CompareUI 模块的真实 WorkspaceView、NSWindow、NSTextView 和 Rust FFI 上，新五项回归对旧 `2f080310…` 产品代码实际失败：5 项／17 条断言，退出码 1。包含外部 A 输入、原生 A 编辑、设置返回后 B 编辑／undo／redo及详情、等长 Unicode 变体和 YAML 旧输出。只补编辑器快照时，原文显示恢复，但结果过期仍失败；两处须同时修正。

首次准备运行未指定完整 Xcode，找不到 Testing 模块；后续测试辅助函数直接在 async 上下文调用 RunLoop.run，被编译器拒绝。两次均属于准备错误，没有记为产品行为失败。正式运行改用完整 Xcode及同步事件处理辅助函数。

## 实际源码修订

- `SourceEditor.swift`：增加 SourceTextSnapshot，以 NSString 长度及 literal 比较识别实际 UTF-16；初始化时捕获绑定原文，确保 SwiftUI 原生视图更新能识别规范等价、编码不同的来源；继续原生撤销、高亮和安全解析。
- `ConfigCompareApp.swift`：A/B 的 onChange 使用相同原文快照，调用既有 Workspace.changed，旧结果标记过期、禁用结果操作并清理详情。
- `UnicodeWorkspaceTests.swift`：五项完整页面回归，实际验证双侧绑定、焦点边框、设置遮盖／返回保留编辑器、undo／redo、详情清理、重新比较和只读 YAML 输出。

没有修改 Workspace、WireModels、比较核心、Vault、MCP或文本布局／对象所有权。此前非连续布局与生命周期实验没有进入此候选；其失败和设备／内存门槛继续独立保留。

## 当前候选与验证范围

隔离候选 `05f0ae4ed8e775738f445b9e5bd6a196563898ad3e4756cb9274b29d3f0af250`，141 个源／测试／打包文件；相对主源码仅上述三项变化。强化专项五项通过。[完整13本机门禁](evidence/unicode-workspace-quality/results.json)实际通过，Rust95／Swift194（23套）／Python33，共322项命名测试，专项不重复累加；起止清单稳定。[11项自建HTTP／TLS](evidence/unicode-workspace-quality/network-check.json)、包内XPC／stdioMCP、Release本机ad-hoc签名通过。[ZIP全新解压核验](evidence/unicode-workspace-quality/package-check.json)核对二进制／图标／许可证／Info.plist及可执行权限，deep／strict签名通过。[同候选CC／DS独立接受](evidence/unicode-workspace-quality/review-synthesis.json)这一源码增量，无阻塞，wholeGoalAccepted均为false。CC原会话正常exit0／timedOut=false，没有观察超时后重启；本机核对141项候选及140项主基线、差异、源码和日志，没有重跑测试或看图。DS只读提供的文本，实际deepseek-flash，没有本机执行。DS关于专项日志包含194项的描述不准确，以实际全门禁日志为准。

本轮没有 node_repl／computer-use 执行工具，无法补最终桌面截图；此前整页原生渲染对嵌入 TextKit 绘制层的限制仍有效。上述测试实际挂载、绘制原生视图，并通过委托和绑定验证文本，不等于实际键盘、输入法、系统通用剪贴板或 VoiceOver 验收。Penguin 查询成功但索引 mutation 返回 MUTATION_DISABLED；没有更改服务设置或声称索引刷新成功。

只处理配置输入原文更新，不宣称已完成 Unicode 根名／搜索字段的所有 UI 身份与匹配矩阵、20 MiB 冷P95、完整应用100循环、macOS14／Intel、真实获准非生产部署或正式签名公证发行。经双评审后，确切两项产品源码和五项测试已合入主项目。[评审后完整性](evidence/unicode-workspace-quality/post-review-integrity.json)核对主源码逐字节等于05f0候选、同一提示和ZIP稳定。当前用户App／输入仍保留，只剩原主进程PID47589；本候选没有替换或另开主窗口。新包为 `build/Config Compare Unicode Quality.zip`。

## 三尺寸原生布局复核

[本候选五项布局测试](evidence/unicode-workspace-quality/visual-layout-rebuilt.log)通过，19种页面／状态分别在1280×800、1440×900、1720×1000点检查，保存[57整页＋2编辑器图片及哈希](evidence/unicode-workspace-quality/visual-proof.json)。Codex实际看图核对1280不完整差异、1440详情、1720Vault与单独编辑器代码：奶油白／柔粉、单一白鹅、列对齐与真实统计保持。整页的TextKit内容未被cacheDisplay捕获，仍以单独原生编辑器图核对代码，不拼接、不冒充桌面截图。

最初skip-build导图因Release打包清理Debug测试产品，找不到bundle；保留退出1的准备记录，重新构建并执行布局测试后通过。1720由测试窗口解除本机显示器约束，只证明原生布局，不能替代更宽物理显示器。当时Vault表单保留实际滚动容器，但首屏未显示全部名称／确认字段；后续Vault专项已复现并修复首屏可见性。最小窗口、实际滚动／菜单展开和桌面交互仍待补。

## 继续开放的质量项

CC提出未显式采用NSString同对象快路，可能在大输入、非文本状态更新时增加开销；尚未测量，不把推断当作已证卡顿。等长变体的原生输入、Vault JSON及Unicode文件交换／根名／搜索身份的扩展矩阵继续登记。源快照解决完整页面的原文／过期问题，不用于接受非连续布局、生命周期归因或全应用20MiB性能。

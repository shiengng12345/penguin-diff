# 编辑器生命周期：原生计时器、窗口动画与异步测试对照

2026-10-04。完整目标继续 active。调查开始时主工作区是已接受的 `2f080310…`／140 文件，当前用户窗口仍运行白鹅视觉基础版 `8df029ff…`。这里记录隔离实验与测试修订，没有替换当前 App、修改用户输入、访问真实 Vault 或改变比较算法。

## 已完成的检查与候选边界

第一轮生命周期测试候选 `9629556c…`／144 文件使用与上一轮 `3121707c…` **完全相同的 SourceEditor.swift**，只改测试并增加独立原生进程探针。该候选[完整原生回归](evidence/editor-lifetime-investigation/first-full-native-network-check.log) **198 项／24 套通过**，11 项自建 loopback HTTP／TLS 通过。不是 13 门禁全部通过，也没有打包或最终源码接受。

该候选的 20 MiB、真实 600×240 NSWindow、实际 SwiftUI 绑定专项均通过 500 ms 断言，校验原文、绑定、撤销／重做与目标字符确实可见；每组只有一次连续三位置样本，完整往返含 20 ms 等待：

| 构建 | 文末完整往返 | 中间完整往返 | 文首完整往返 |
| --- | ---: | ---: | ---: |
| Debug | 156.62 ms | 346.75 ms | 445.84 ms |
| Release | 169.66 ms | 286.76 ms | 319.38 ms |

[Debug 记录](evidence/editor-lifetime-investigation/final-debug-metrics/explicit-noncontiguous-20971520.json)、[Release 记录](evidence/editor-lifetime-investigation/final-release-metrics/explicit-noncontiguous-20971520.json)。不是重复冷 P95、实际键盘、完整应用帧时间、多结构／非 ASCII 20 MiB、峰值内存或目标设备支持证明。

补强后的候选 `fc565057…`／144 文件位于 `build/quality-review/editor-lifetime/revision-workspace`，[十项专项](evidence/editor-lifetime-investigation/revision-final-focused.log)通过。[该候选完整原生回归](evidence/editor-lifetime-investigation/revision-final-network-check.log)实际完成：**200 项／24 套通过**，11 项自建 HTTP／TLS通过，源码起止清单一致。[范围记录](evidence/editor-lifetime-investigation/revision-final-proof.json)。13门禁、打包和新候选最终双评审仍未完成。本候选的产品 SourceEditor 仍逐字节等于上述实验；新增证据不能继承上一候选的完整回归或模型接受。

## 已确认的原生保留来源

普通 NSTextView 在约 0.15 秒观察期内也未释放。[独立校准](evidence/editor-lifetime-investigation/timed-calibration.log)显示，继续处理公开主 RunLoop 后释放。只检查本次自建合成进程 PID95789：`leaks --noContent` 找到强捕获 block 与主队列计时器，[分配栈](evidence/editor-lifetime-investigation/native-timer-allocation.log)指向 `NSTextView.initWithFrame:textContainer:` → `_requestUpdateOfDragTypeRegistration` → `_NSCreateMainQueueHysteresisBlock` → `_Block_copy`。恢复原进程后 weak view 确实变为 nil，原会话退出码 0。[恢复记录](evidence/editor-lifetime-investigation/freeze-resume-proof.json)。这些私有符号仅用于读诊断栈，没有在产品或测试调用私有 API。

加强到真正显示并绘制 100 个测试窗口后，14 类对象中 editor、storage、layout、container、host、fixture、scroll、clip、ruler、coordinator、observer、undo、storageDelegate 均为 0，**window 仍为 100**，严格检查失败。改用 NSWindowController、updateWindows 或公开事件派发均未消除。[失败计数](evidence/editor-lifetime-investigation/revision-visible-cycle-counts.err)保留。

只读取自建诊断进程 PID21676 的窗口指针，[引用树](evidence/editor-lifetime-investigation/visible-window-reference-tree.log)包含 `_NSWindowTransformAnimation` 对 `_animatingWindow` 的强持有和动画工作线程。测试窗口设置公开 `animationBehavior = .none` 后，[同类 100 次可见循环](evidence/editor-lifetime-investigation/revision-no-window-animation-cycle.json)全部 14 类弱引用为 0，约 0.51 秒完成清理。仅取消合成测试窗口的系统开关动画；产品动画、编辑预算和释放断言没有改动。普通动画模式下的 100 窗口在 2 秒内全释放仍未通过，不能用这一样本声明正常窗口动画全验收。

## 未确认的归因仍保留

旧 Swift Testing `@MainActor async` 原地测试仍有 storage／layout／container 存活，editor、host 等已释放。[自己测试进程的引用树](evidence/editor-lifetime-investigation/mounted-storage-reference-tree.log)出现外层自动释放池、共享 NSATSTypesetter、通知表与派发路径；扫描到引用不代表每一条都是强引用环。

曾尝试“只延长外层自动释放池”对照，但没有复现保留，诊断断言失败：[原失败](evidence/editor-lifetime-investigation/revision-pool-control-debug.err)。未把这一校准假设当作产品契约，没有将失败改写为成功；源码保存于 `build/quality-review/editor-lifetime/failed-pool-hypothesis`。第一次讨论材料冻结在该对照之前；CC 在稍后本机阅读到新增失败文件，后续综合明确补入。

旧测试仅关闭前一窗口动画时，单次挂载检查有通过样本，但 100 循环仍留 49 组文本系统；将循环里的源值断言先计算 Bool 再传给 #expect，也仍留 48 组，并再次出现单次挂载失败。[动画对照](evidence/editor-lifetime-investigation/async-animation-control.log)、[布尔断言对照](evidence/editor-lifetime-investigation/async-boolean-oracles.log)均保留。不能宣称这两项变化解决旧异步测试。

另在独立原生进程内，用真实 `Task { @MainActor }` 驱动同一批 100 个可见编辑器，分别让外层事件处理拥有／不拥有额外自动释放池；两者在异步 job 内和结束后，14 类对象均为 0。[拥有池](evidence/editor-lifetime-investigation/async-owned-pools.json)、[不额外拥有池](evidence/editor-lifetime-investigation/async-unowned-pools.json)。这是诊断观察；没有使用 Swift Testing 执行器，不能证明其内部持有已归因，更不能将“异步 job 本身造成泄漏”写成结论。

因此，**原地 Swift Testing 残留的具体原因仍 OPEN**。没有宣布产品有确定引用环，也没有宣布主应用无泄漏。独立原生的同步／异步样本是补充证据，不能抹掉原失败或替代完整应用与原 91 项要求。

## 测试补强

独立进程重新编译确切 WireModels、SourceEditor、GooseDesign 和探针源码，编译前后核对哈希；使用 Swift 6／enable-testing，Release 增加 -O 与 WMO。编译、超时、进程、JSON、phase 或哈希不符均失败。仅开发测试依赖 Xcode 与 Python，不进入 App。NSApplication 自身可能读取系统偏好；没有写入应用偏好、读取 App Token 或调用 Vault。

现跟踪 14 类公开对象，并检查 native storage／layout／container、scroll.documentView 和 ruler.clientView 关系。强保留 editor、coordinator、undo、scroll、ruler、observer token，以及真实 NotificationCenter 注册闭包捕获 editor 的七个反例，都使用与正路径相同的 **2 秒**判断；不保留对象的同类对照必须释放，解除保留后也必须全释放。[七项反例](evidence/editor-lifetime-investigation/revision-negative-two-second.json)。这修正了原 0.25 秒反例短于原生 0.5 秒计时器、分辨力不足的问题。

加入 100 次可见绘制、实际源绑定、原生 undo／redo、清空／替换、模拟设置覆盖保留编辑器、禁用／返回、外部 NFC／NFD 原文及语法切换，另有原生异步 MainActor job 的 100 次循环。模拟设置覆盖没有完整 Workspace.onChange→model.changed、副作用、真实设置页面、真实用户键盘／输入法或整应用导航的验收含义；编译的是上述确切选定源码，没有链接整个 CompareUI 模块。

## 独立讨论及下一步

[Claude Code 与 DeepSeek](evidence/editor-lifetime-investigation/discussion-synthesis.json)对第一轮 `9629556c…` 均为 **NEEDS_CHANGES**，不是接受。CC 本机核对144项哈希并只读代码／证据，没有运行测试；DS只读所提供文本，实际模型 deepseek-flash。CC 两次没有收到提示的调用以 exit1、timedOut=false 结束并保留；后续调用正常完成，会话 `59b0bd28-ad73-4107-89bb-e59b2b12c71e`，不是观察超时后重启原会话。

两者一致要求恢复完整对象图、改善反例、辨明旧异步残留，并补原生回归及 UI 副作用。后续已补14类对象、七种同期限反例、可见绘制、外部更新、异步原生循环；完整测试与新候选的最终独立评审仍另行核对。CC关于窗口显示、反例期限、OS偏好读取的意见采纳；其在初始材料之后读取到的工作中间文件不会被记为冻结候选接受。

继续核验：原地测试保留归因、整个 CompareUI／Workspace 的绑定和 model.changed、副作用／滚动观察器／首响应者、同候选完整门禁和双评审、行号实际像素、多来源／Unicode大文件、峰值内存／完整应用100循环、真实GUI／输入法／无障碍、最低 macOS14／Intel、获准非生产部署与正式发行。生产禁止边界保持，完整目标 active。

## 补强候选的后续独立讨论

同一冻结候选 `fc565057…` 的[后续讨论](evidence/editor-lifetime-investigation/revision-discussion-synthesis.json)：CC 为 **READY_FOR_NEXT_EXPERIMENT**，DS 为 **NEEDS_CHANGES**；两者 wholeGoalAccepted 均为 false。CC 正常终态 exit0、timedOut=false，会话 `a6dd2bc6-2388-4097-8dbe-54bc2f98ce98`，实际 claude-opus-5-5[1m]；核对144项清单、源码与日志，没有重跑 App／测试。DS仍仅审阅提示文本，实际 deepseek-flash。

CC认可14类对象、同期限反例和200项回归，要求继续辨明原Swift Testing残留、普通窗口动画释放时间和真实Workspace副作用。部分原始反例／async JSON对应冻结前的探针版本；正式专项已在冻结候选通过，但这些早期JSON不能作为完全相同探针字节的补证。DS将样本缺少P95作为阻塞，合理保留；其“未施加500ms预算”的断言不准确，实际 Debug／Release 样本开启预算断言并通过。三个固定位置样本仍不能替代冷P95、Unicode大文件或桌面帧时间。

没有合并实验、降低期限或宣布完整目标完成。后续优先补真实Workspace输入更新与结果过期链路，生命周期原失败继续登记。

后续独立[Unicode完整页面修订](unicode-workspace-quality.zh.md)以05f0候选通过322项本机测试并获双评审源码接受后合入主项目；仅原文快照／页面监听改变。本调查中的布局／所有权实验仍未合入，原生命周期失败不继承该源码接受。

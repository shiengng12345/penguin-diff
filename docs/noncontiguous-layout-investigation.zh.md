# 大文件编辑：非连续布局与绑定同步调查

> 后续[生命周期调查](editor-lifetime-investigation.zh.md)补充原生计时器、窗口动画、完整对象图与异步对照。旧失败保留，具体异步残留归因仍未闭合；以下为上一轮快照记录。

2026-10-04。原完整目标继续 active。主工作区仍为已接受的 `2f080310…`／140 文件，没有替换当前 App、修改用户输入或访问真实 Vault。这里是独立实验，不是最终源码接受。

## 测量条件与无效结果

设备 Apple M3／24 GiB（Mac15,3）、macOS 26.5.2／25F84、Xcode Swift 6.3.3。测试使用真实 SourceEditor、SwiftUI ObservableObject 绑定、600×240 原生 NSWindow 与可见窗口；20 MiB、约 116 万行合成注释文本。不是完整应用、真实键盘、帧时间、重复冷启动 P95 或最低支持系统的证据。

显式 NSTextStorage／NSLayoutManager／NSTextContainer 链在填入文本前设置非连续布局，并实测 `hasNonContiguousLayout=true`。初次实验默认 maxSize.height 只有 240 点，跳到文末时视口没有移动；那组很快的计时被排除。修正尺寸后，继续验证目标字符确实属于可见字符范围，不能仅凭滚动偏移变化宣布成功。初次 JSON 记录方法对象导致的崩溃属于测量代码错误，修正后增加 JSON 类型校验。

## 先定位性能，再检查正确性

仅启用非连续布局时，Debug 20 MiB 完整往返仍约 604／815／904 ms，超过 500 ms；Release 文首约 534 ms，仍真实失败。[原生窗口 Debug 记录](evidence/noncontiguous-layout-investigation/verified-viewport-metrics/explicit-noncontiguous-20971520.json)、[Release 记录](evidence/noncontiguous-layout-investigation/verified-viewport-release-metrics/explicit-noncontiguous-20971520.json)分别保留。

ASCII 独立基准中，UTF-16 逐项相等检查约 303 ms，Foundation `.compare(options: .literal)` 约 0.62 ms。该微基准只说明这个输入存在同步开销，不代表 CJK、emoji、多种缓冲区来源或完整应用。实验只改变编辑器同步判断，不改变比较核心。[基准](evidence/noncontiguous-layout-investigation/compare-bench-debug.json)。

字面比较加入特殊字符两两对照、嵌入 NUL、BOM、CRLF、emoji、组合字符、固定种子 500 组及长文本尾部／编码变化，与独立 UTF-16 oracle 核对。Swift String 解码未配对代理项时会替换它们，这不能证明原始 NSMutableString 中非法代理项的保持。

真正的外部绑定回归发现：普通文字替换正常，但 `é` 到 `e + 组合重音` 更新没有反映到编辑器。[运行期失败](evidence/noncontiguous-layout-investigation/literal-external-controls.log)。实验增加字面相等的输入快照，避免视图把编码不同但规范等价的输入当作同一值；已通过外部 NFC／NFD、同长度 Å／Å、Ω／Ω、组合符顺序变化及原生撤销／重做。之前仅直接调用 replaceSource 的回归不足以验证外部绑定，已补上真实 ObservableObject 与窗口。

加入快照后的独立 Debug 20 MiB 全往返如下；均包含一次 20 ms 等待，目标字符可见、绑定／原文／撤销／重做精确检查通过。单次三位置通过不能替代完整性能验收。

| 位置 | 跨位置输入完整往返 | 可见位置输入完整往返 |
| --- | ---: | ---: |
| 文末 | 155.30 ms | 130.09 ms |
| 中间 | 346.71 ms | 187.73 ms |
| 文首 | 444.52 ms | 285.15 ms |

最新实验快照 `3121707c…`／142 文件，保存在 `build/quality-review/noncontiguous-layout/literal-workspace`。最终默认链与补强测试的[Release 独立性能](evidence/noncontiguous-layout-investigation/final-literal-release-metrics/explicit-noncontiguous-20971520.json)实际通过：跨位置输入完整往返文末 **157.89 ms**、中间 **286.89 ms**、文首 **327.43 ms**；可见位置分别 **131.49／130.88／160.97 ms**。全部精确性和目标可见检查通过；这是本快照的一次三位置结果，尚不是重复冷 P95、多结构或完整 App 验收。

[完整原生回归](evidence/noncontiguous-layout-investigation/network-check.log)真实结束：**196 项／24 套，194 项通过、两项失败、三条断言**，退出码 1。失败为 explicitStorageSurvivesMountAndReleasesWithEditor、bareNativeOwnershipControl；11 项自建 loopback HTTP／TLS 通过。完整测试中性能探针默认使用 1 MiB 且未启用预算，不替代上述独立的 20 MiB 测试。[范围与未通过项](evidence/noncontiguous-layout-investigation/literal-proof.json)明确保留，尚未取得本快照完整门禁或最终同候选源码接受。

## 未通过的检查不能隐去

新增生命周期检查：宿主销毁后，editor／storage／layout／container 尚未全部释放；排除短暂 autorelease 和处理 RunLoop 后仍不通过。普通 NSTextView、frame 初始化及显式初始化对照也出现保留，宿主本身已释放。因此尚未证实实际引用环或归因于显式链，不能宣称无泄漏，也不通过此门槛。

[独立原生进程校准](evidence/noncontiguous-layout-investigation/lifetime-control.json)已调用 NSApplication.finishLaunching，在禁止激活的进程中创建普通 NSTextView；空文本、非空文本及 inputContext.deactivate 三种均未立即释放。实测 stronglyReferencesTextStorage=true。该进程没有启动主 App 或读取用户输入，结果进一步说明保留现象不是本次 SourceEditor／显式链独有；其原因仍待定位，不能把这一对照当作豁免或泄漏根因证明。

尚需解决对象销毁证据、检查完整原生回归、更多输入结构与来源、行号／光标实际像素对齐、峰值内存／100 次循环、完整应用绑定及视口性能；生产边界、原 91 项、GUI／键盘／输入法／VoiceOver、最低 macOS 14、设备及正式发行要求保持。

## 独立方案讨论

[Claude Code 与 DeepSeek](evidence/noncontiguous-layout-investigation/discussion-synthesis.json)均为 `READY_FOR_NEXT_EXPERIMENT`，不是源码接受，`wholeGoalAccepted=false`。CC 会话正常结束、未超时，只读完整实验编辑器及微基准，没有运行测试；DS 第一次 TLS 连接终止并实际退出，保留原记录后重试完成，仅文本审阅，实际模型 deepseek-flash。没有因观察等待就重启 CC。

两者要求更多差分测试、同步成本归因、生命周期及视口对齐证据。CC 的“显式 storage 仅为局部变量可能提前销毁”推断未获证明；本机 SDK 文档声明现代 NSTextView 强持有 storage，默认策略自 macOS 10.12 起启用，但仍需目标系统生命周期实测。两者收到的是字面比较之前的 Debug 失败记录，不能把方案讨论用于接受后续新快照。

技术参考：[Apple 非连续布局](https://developer.apple.com/documentation/appkit/nslayoutmanager/allowsnoncontiguouslayout)、[TextKit 布局管理](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextLayout/Concepts/LayoutManager.html)。API 允许非连续布局不代表已经启用，也不代表本项目达到所有性能门槛。

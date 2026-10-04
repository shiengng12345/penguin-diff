# 大文件编辑性能调查（未验收）

> 后续[显式非连续布局与绑定同步调查](noncontiguous-layout-investigation.zh.md)已证明新方向在完整原生视口中实际生效，并取得独立 Debug 改善；外部 Unicode 编码同步已补失败回归及实验修订。生命周期等检查仍未通过，尚未纳入主工作区或正式候选，不能宣称完整性能验收完成。

2026-10-04。完整目标及原 91 项要求保持未完成，不能用小范围接受替代。当前发布候选继续使用已经验证的原生编辑器；本次 TextKit 2 实验已隔离，**没有打包或切换到用户窗口**。

## 已观察到的事实

- 接受版本 `20bc16ef…` 的真实挂载 `SourceEditor`，10.2 MB 首次原生插入及绑定设置约 3929.9 ms，挂载约 647.8 ms。窗口外原生探针中，允许非连续布局前后约 4054.4 / 4576.2 ms，两次 `hasNonContiguousLayout` 均为 false。因此该探针不能证明非连续布局已经生效，也不能据此宣布这个方向不可行。
- 调用栈主要位于原生插入、`didChangeText`、布局容器查找与字形排版；高亮刷新只约 0.002 ms。记录见[原始采样](evidence/editor-layout-investigation/profile/native-stack.txt)。
- Claude Code 的独立原生探针发现：当前 macOS 上普通 frame 初始化已经使用 TextKit 2，访问 `layoutManager` 后永久回退；`textStorage.delegate` 当时为 nil。该结果尚未在最低支持的 macOS 14 验证，不能扩展为所有系统的所有权结论。
- TextKit 2 窗口外 10.2 MB 首次插入约 4.56 ms，但没有高亮、行号、非空视口或 SwiftUI 完整往返；**该数字不是交付性能证据**。

## 完整挂载实验的失败结果

实验使用 20 MiB、约 116 万逻辑行、600×240 的实际 NSWindow、非空视口及实际 SourceEditor／ObservableObject 绑定。原生插入包含自动定位与滚动到目标位置；不能等同于已在可见光标处打字的耗时。后续需要分别测量导航、可见位置打字，以及原来的合并场景；不能移除合并场景或放宽预算。

| 位置 | 原生插入与绑定设置 | SwiftUI 往返（包括一次 20 ms 等待） |
| --- | ---: | ---: |
| 文件末尾 | 23410.97 ms | 25405.63 ms |
| 文件中间 | 103442.49 ms | 104936.63 ms |
| 文件开头 | 11146.02 ms | 15211.01 ms |

[实际计时](evidence/editor-layout-investigation/modern-final/twenty-MiB-roundtrip.json)。文字、撤销、重做及选区检查通过，但 `<500 ms` 插入预算失败。[34 项专项](evidence/editor-layout-investigation/modern-final-second.log)真实完成，退出码 1、总耗时约 178.54 秒；不是超时后的推定结论，也没有终止测试。最终实验快照后来增加的 fallback 通知测试尚未运行，不能宣称该快照完整通过。

中间插入的 1096 个主线程采样全部在原生插入自动滚动与布局链中，其中 960 个在布局片段存储／RLE 数组搬移；约 64 个涉及我们的装饰回调。[采样记录](evidence/editor-layout-investigation/slow-mounted-stack.txt)。复杂度推断来自这些栈与计时，没有 Apple 内部实现证明。

仅在 1.08 MB／6 万行测过视口迁移：迁移约 537.49 ms，随后插入约 23.99 ms。[记录](evidence/editor-layout-investigation/relocation-probe.json)。迁移本身已经超过局部预算，尚无 20 MiB 的可行性证明。

## 实验隔离与评审

实验源码完整保留于 `build/quality-review/editor-layout/experimental-workspace`，快照 `b1aec900…`／141 文件。隔离后主工作区曾逐字节恢复为接受版本 `20bc16ef…`，然后只进行独立的行号修订；没有把实验代码混入新包。

Claude Code 与 DeepSeek 均建议不交付当前实验。Claude 实际模型为 `claude-opus-5-5`，首次讨论运行了原生探针，后续讨论只读源码与记录；两次 CLI 均正常结束，无观察超时。DeepSeek 实际模型为 `deepseek-flash`，仅阅读提供的文本，没有本机文件／测试工具。这些都是方案讨论，**不属于最终源码或完整目标接受**。

两者对下一步有分歧：Claude 建议先在显式 TextKit 1、赋值前开启非连续布局的完整挂载环境验证其实际生效；DeepSeek 更倾向探索分段内容管理或自定义可视区编辑器。二者均未证明下一种方案可行。[独立评审及事实修正](evidence/editor-layout-investigation/synthesis.json)。其中“访问 textContainer 必然回退”不符合 Apple 文档；“91 个测试套件”也不准确，91 是原始验收要求数量。

## 下一步门槛

1. 明确构造原生 TextKit 1，赋值前设置非连续布局；测量实际启用状态、导航／可见位置编辑／合并路径及绑定往返，记录导致连续布局的调用链。
2. 如继续迁移视口方案，测量 1／2／5／10／20 MiB 完整曲线，计入迁移自身成本；不能只报告迁移后的打字。
3. 若需要自定义可视区编辑器，继续沿用 SwiftUI／AppKit，完整验证中文／日文输入法、Unicode／UTF-16、双向文字、选区、跨行操作、撤销重做、查找、滚动、复制、VoiceOver；不能以仅显示部分文档或缩小文件限制冒充完成。
4. 原始比较算法、生产边界及全部功能保持。性能、GUI、最低支持系统、设备与正式分发验收继续未完成。

技术参考：[Apple TextKit](https://developer.apple.com/documentation/appkit/textkit)、[视口迁移](https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/relocateviewport(to:))。参考 API 的存在不证明本项目达到性能标准。

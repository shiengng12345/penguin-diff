# 白鹅改版：原生编辑器精修与验证

> 2026-10-04 最新行号修订候选 `2f080310…`（140 文件）：[13 门禁／317 测试及新包核验](gutter-quality.zh.md)已通过，同候选 CC／DS 独立接受与评审后完整性核验均通过。以下为各历史增量证据。当前运行窗口仍为白鹅视觉基础版 `8df029ff…`；[20 MiB 完整挂载实验](editor-performance-investigation.zh.md)未达性能预算，实验代码未进入新包。完整原 91 项、实际桌面／输入法／设备／正式发行仍开放。

> 最终状态：候选 `20bc16ef…` 的 13 项门禁／314 项测试、Release 原生专项与同候选 CC／DS 独立源码评审均通过。完整项目／桌面／设备／性能验收仍开放。前轮 `9217895b…` 的连续编辑残留着色已由原生失败回归确认并修复，没有继承旧候选结论。

本次在已经实现的奶油白／草莓粉白鹅界面上修复编辑器问题，沿用 SwiftUI、AppKit 和 Rust。没有修改比较算法，没有连接真实 Vault 或生产，没有执行配置中的表达式。

候选清单：`20bc16efe43b4809e2b0109faf816ee4a1f8e380f9c9c560dcbdec9a0304a59f`，139 个源码／测试／打包文件。相对上轮 `8df029ff…`，只有以下三项变化；其余源码与既有测试逐字节不变，见[范围证明](evidence/editor-quality-v2/change-scope.json)。

| 文件 | 实际实现 |
| --- | --- |
| [SourceEditor.swift](../apps/macos/Sources/ConfigCompare/SourceEditor.swift) | 区分 JavaScript、JSON、YAML 装饰高亮；避免把 YAML URL、普通撇号、路径当作 JS 注释或字符串；支持双单引号、块字符串、JS CRLF 字符串续行；按原生 NSTextStorage 编辑范围局部更新 UTF-16 行号索引；前缀以外编辑跳过高亮刷新；清除前缀插入后移出的旧着色；延迟刷新期间持续跟踪已移出上限的着色尾部 |
| [ConfigCompareApp.swift](../apps/macos/Sources/ConfigCompare/ConfigCompareApp.swift) | env.js 使用 JS；Vault 本机输入使用 JSON；YAML 输入与只读输出都使用 YAML |
| [EditorQualityTests.swift](../apps/macos/Tests/CompareTests/EditorQualityTests.swift)（新增） | 八项原生回归：实际 YAML 页面双编辑器、引号／块内容、语言切换与着色上限、CRLF／Unicode／合并编辑行号，连续／全量替换的颜色边界，以及大文件输入、撤销和精确原文 |

高亮只影响临时显示属性，不影响 Rust 解析、比较范围、结果统计或原文件。仍只装饰前 200000 个 UTF-16 单元，后续文本使用清晰的中性文字；输入法组合期间推迟高亮。保留 AppKit 原有文本系统和所有权、每侧独立撤销历史及精确 UTF-16 替换检查。

## 从失败测试到修复

[旧实现回归](evidence/editor-quality-v2/baseline-red.log)实际复现两项运行期失败、12 条断言：YAML 双编辑器 8 条，未闭合 JS 引号 4 条。[性能红测试](evidence/editor-quality-v2/index-red.log)单独复现热编辑刷新超出 100 毫秒预算；[CRLF 续行红测试](evidence/editor-quality-v2/quote-red.log)复现 2 条断言。编译错误不当作行为失败证据。

修复后[专项记录](evidence/editor-quality-v2/focused-v2-final.log)的 26 项通过；随后新增的累计编辑验证也[实际通过](evidence/editor-quality-v2/randomized-lines.log)。行号验证包含小字符串各 UTF-16 位置的插入／替换、CRLF 分拆与组合、中文和组合字符，以及 300 轮连续单次／批量修改，逐次与独立全扫描结果核对。它不代替真实键盘、输入法或系统无障碍测试。

针对 CC 的着色阻塞，[原生运行期红测试](evidence/editor-quality-v2/color-red-2.log)先确认连续编辑后 `limit+140` 的实际临时颜色存在，再确认旧刷新未清除它；修订后的 Debug／Release 均通过。另三种整段替换（storage、native insertText、replaceSource）的[实际观察](evidence/editor-quality-v2/metrics/replacement-colors.json)在刷新前后均无上限外颜色，因此没有把未复现的继承颜色推测当作已证缺陷。

## 全量门禁与性能边界

[本候选 13 项完整门禁](evidence/editor-quality-v2/results.json)全部通过，起止源码清单稳定。Rust **95**、Swift **186**（21 套）、Python **33**，共 **314** 项；专项是其中子集，不重复累加。另包括 format/clippy、OXC 来源、Debug／Release 合成 Node 对照、报告与深度保护、11 项真实 loopback HTTP/TLS、Release 打包、deep/strict 签名、包内 XPC 与 MCP。网络只访问自建 127.0.0.1。

10.2 MB、600001 逻辑行合成文件，在同一原生末尾追加与撤销测试中的时间如下：

| 实际测量 | 修复前 | 冻结候选完整门禁内 |
| --- | --- | --- |
| 热编辑装饰刷新，两次 | 904.88／900.43 ms | 0.000584／0.000750 ms |
| 热编辑原生追加＋刷新，两次 | 905.18／900.69 ms | 0.23004／0.25421 ms |
| 第一次冷追加＋刷新 | 4833.5 ms | 3795.96 ms |

详见[原始前测](evidence/editor-quality-v2/before-large-edit.json)和[最终测量](evidence/editor-quality-v2/metrics/large-edit.json)。这证明末尾热编辑不再整篇扫描；**测试中首次原生冷追加仍约 3.8 秒，没有宣称达标，其具体开销尚待定位。** 该测试使用独立原生文本视图，没有测量完整 SwiftUI 绑定路径、真实窗口帧率、20 MiB 上限或全部编辑位置的延迟，相关性能门槛继续开放。

另外补测 UTF-16 位置 100 的高亮范围内编辑：Debug 原生插入＋刷新为 172.86／173.48 ms，其中高亮刷新 31.77／31.62 ms；[Release 实测](evidence/editor-quality-v2/release-metrics/large-edit.json)原生插入＋刷新为 97.89／97.79 ms，其中高亮 14.83／14.87 ms，末尾热追加为 0.255／0.230 ms，首次冷追加为 3807.08 ms。[三项 Release 原生回归](evidence/editor-quality-v2/release-native.log)通过，属于 314 项的重跑子集，不能累加到总数。这仍不代表实际 App 的帧率或完整输入流程达到性能要求。

## 原生渲染、评审与测试包

本候选按 1280×800、1440×900、1720×1000 点跑原生布局回归，保存 57 份整页图、2 份 JS 编辑器视口及 2 份实际 YAML 编辑器视口；[61 份图像哈希及尺寸](evidence/editor-quality-v2/visual-proof.json)可核对。修订后人工检查了初始页、不完整长内容、所选详情、英文设置、401 条结果及两份 YAML 编辑器图。

- [初始页 1440](evidence/editor-quality-v2/screenshots/empty-1440x900.png)
- [长内容与不完整结果 1280](evidence/editor-quality-v2/screenshots/incomplete-long-1280x800.png)
- [详情 1440](evidence/editor-quality-v2/screenshots/selected-detail-1440x900.png)
- [英文全窗口设置 1280](evidence/editor-quality-v2/screenshots/settings-english-1280x800.png)
- [大量结果 1720](evidence/editor-quality-v2/screenshots/many-results-1720x1000.png)
- [YAML 输入](evidence/editor-quality-v2/screenshots/yaml-editor-0.png)／[YAML 输出](evidence/editor-quality-v2/screenshots/yaml-editor-1.png)

整页 NSHostingView 渲染仍不包含嵌入 TextKit 的文字绘制层，不能因为整页输入看似空白就把它当作真实桌面截图；独立编辑器图显示实际代码与高亮，没有合成拼接。1720 点通过测试专用窗口解除当前 1512 点显示器约束，并非物理宽屏验证。此次[只读桌面复查](evidence/editor-quality/desktop-probe.json)仍为 `cgWindowNotFound`，未修改用户输入。

前轮 `9217895b…` 为 DS 接受／CC 阻塞；CC 的连续编辑着色疑点确实复现并修复，整段替换继承颜色的推测未复现。修订候选 `20bc16ef…` 的第一次复审为 CC 接受／DS 对坐标、首次索引和颜色范围提出疑点。随后补做[三项针对性原生验证](evidence/editor-quality-v2/native-probes/native-probes.log)：直接替换 CRLF 的 LF（含上限附近）、预填充 storage 与重复观察、以及上限前后两次插入再删除，均通过；实际旧颜色先移出上限，刷新后所有上限外单元均无临时颜色。测试夹具只临时加入 SwiftPM 测试目录，按字节核验后移除；[前后候选完整性](evidence/editor-quality-v2/native-probes/integrity.json)保持同一清单。这三项不计入 314 项冻结门禁命名测试，也没有修改产品代码。

[最终独立评审与 Codex 合议](evidence/editor-quality-v2/final-review-synthesis.json)：两位对同一 `20bc16ef…`、同一提示 SHA `c9d8e576…` 均为 `ACCEPT_SOURCE_CHANGE`、无阻塞、`wholeGoalAccepted=false`。CC 实际复算 139 文件哈希、核对源文件与原生探针资料，并运行[离线 Python 模型](evidence/editor-quality-v2/claude-offline-model.json)检查 3000 份随机文档×40 步、缩放上限 40、合并编辑／延迟刷新／最坏颜色继承，结果 `fails 0`；这不是原生 TextKit 或设备测试。CC 没有重跑构建／Swift 测试／GUI。DS 实际模型 `deepseek-flash`，依据相同范围文本、原生记录和边界不变量撤回阻塞，没有本地执行能力；其首条 checks 写了“Re-hashed frozen candidate path”，但其自身 limits 明确没有运行命令，实际只是核对所提供的 SHA 记录，不能算独立字节复算。原始响应完整保留。剩余分歧不包括已证正确性缺陷；完整 UI 绑定、冷追加、行数很大时的尾部索引移动等性能仍待验证／优化。

[新测试包及全新解压核验](evidence/editor-quality-v2/package-check.json)通过，主程序、worker、许可证、白鹅图标与 Info 字节匹配，解压后 deep/strict 签名有效。新包位于 `build/Config Compare Editor Quality v2.zip`，属于本机 ad-hoc Release。当前打开的 `build/Config Compare.app` 仍为上轮白鹅视觉候选 `8df029ff…`，只有一个主进程；本次未退出、替换或另开用户窗口。新源码已实现，新测试包已构建，不能声称新编辑器已切换到当前窗口。

[评审后完整性](evidence/editor-quality-v2/post-review-integrity.json)再次核对原工作区与冻结源码、同提示、Release App 和 ZIP 哈希，均未变化。构建目录根部的三个 Swift 副本是历史差异基线，不属于候选；当前代码以冻结源码目录及清单为准。

完整桌面鼠标／键盘／剪贴板／VoiceOver、真实输入法组合、物理宽屏、完整大文件与超大详情性能、干净目标设备和正式签名公证发行仍未完成；原[全量验收清单](quality-completion-audit.zh.md)继续有效。本增量不是整个项目 100% 验收。

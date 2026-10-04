# Vault 原生表单：首屏可见性与双侧绑定

> 最新[许可证／NOTICE资源交付](license-delivery-quality.zh.md)：0fd389候选315项源码、14门禁／361项命名测试、105份原生渲染、新包177文件及同候选CC／DS独立源码接受通过；仅开发构建与本地资源增量已合入。当前App与输入保留，完整目标／正式发行仍active。

> 历史[测试记录与自有进程组清理](run-lifecycle-quality.zh.md)：同一ed3423候选13门禁／345项命名测试、105份原生渲染、ZIP核验与CC／DS独立源码接受通过；两个脚本已合入，当前App与输入保留。完整目标仍active。

> 当前主源码已更新为36fbb707／143文件：[Vault四尺寸滚动与整次测试门禁](minimum-window-and-run-gate.zh.md)通过13门禁／335项测试、105份原生图像和同候选双源码接受；当前App与输入保留，完整目标仍active。下文具体哈希、计数与结论属于原候选历史。

2026-10-04。沿用 SwiftUI／AppKit 的奶油白、柔粉与本地白鹅界面。本增量只整理 Vault 表单布局，比较核心、数据模型、连接策略与 MCP 没有变更。完整目标仍 active。

## 实际修订

旧表单将字段全部纵向排列，配置名称与非生产确认落在初始滚动视口外。新版将 KV mount／配置名称、namespace 根／匹配、目录根／匹配分别配为两列；A／B 对齐，字段继续独立编辑。保留 Token、安全确认、拆解链接、namespace 选择、匹配计划展开及真实滚动容器。两侧外层视口按可用高度限制为294～360点，英文确认文案可以正常换行。

候选 `8a6e701e10dfe4fdf27fde4cbf99f05511b270a2aab8af0f6c84adac729065c4`，143个源码／测试／打包文件。相对已接受的05f0候选只改 `VaultConnectionPanel.swift`、`ConfigCompareApp.swift`，新增 `VaultViewportTests.swift` 与 `Tests/NativeProbes/VaultBindingProbe.swift`。编辑器、算法及此前非连续布局／所有权实验没有混入。[逐文件清单](evidence/vault-form-quality/candidate.manifest.sha256)与[差异哈希](evidence/vault-form-quality/changed-files.json)保留。

## 测试与真实失败记录

第一次几何检查误用了整个 visibleRect 的宽高，造成假绿；保留错误检查版本。正确计算是控件 bounds 与 visibleRect 的交集。修正后的检查在旧05f0产品代码实际失败24条可见性断言；新版三项专项实际通过。[旧版失败记录](evidence/vault-form-quality/viewport-runtime-red.log)、[最终专项](evidence/vault-form-quality/final-focused.log)可复核。中英文分别在1280×800、1440×900、1720×1000点检查，名称、原生确认控件及全部文字字段首屏可见；两侧名称宽高和基线一致。仅A有namespace菜单、两侧各有24个合成计划条目的布局也通过；这些是明确标记的测试样本，不是真实Vault发现。

直接对 SwiftUI 背后的 NSButton 调用 performClick／sendAction，并没有更新模型绑定；本机形式 AX 树也未提供可按压的语义复选框。那些尝试记为失败，不能视为真实点击。部分异步运行退出0却缺少 Swift Testing 完成行，保留退出堆栈；观察到 Swift 异步主循环退出，尚未归因到确切停止调用点。

最终交互检查将实际 CompareUI 模块与已构建依赖链接到独立、同步启动的 AppKit 测试进程。事件只发送到自己的窗口，经过 NSApplication 事件入口；不激活或操作用户当前App。父测试同时检查构建／进程退出状态、JSON完成标记、两种语言、32条断言与零工作请求。实际验证A／B分别确认、取消确认、重新确认，原生字段编辑含中文和组合重音的长名称、B侧mount独立编辑、文本UTF16完整性与最终可见性／对齐。[交互结果](evidence/vault-form-quality/native-binding-result.json)已通过；32条断言不作为32个测试累加，也不能替代实际键盘／VoiceOver验收。

首次完整门禁在生成Swift测试清单时失败。控制脚本在异常前没有保存所捕获的原Swift输出，因此原因仍未确认；不把它改写为通过或宣称已归因。[首次完整失败证据](evidence/vault-form-quality/first-full-gate-failed/results.json)保留。随后直接完整Swift197项／24套与清单生成通过，重新从clean执行同一源码的完整门禁，13项全部通过，起止清单相同。正式自建HTTP／TLS11项、71个本地GET，零重定向／Cookie／信任变更，无真实Vault连接。[最终13门禁](evidence/vault-form-quality/full-results.json)、[真实网络证据](evidence/vault-form-quality/network-check.json)、[测试计数](evidence/vault-form-quality/test-counts.json)：Rust95＋Swift197＋Python33＝325项命名测试；专项重复运行不累加。

## 页面与打包复核

[同候选8项布局与交互复核](evidence/vault-form-quality/final-visual-layout.log)完成：原19种页面／状态各检查三尺寸，另补中英文Vault初始与单侧namespace菜单／计划布局。保存69整页原生渲染＋2独立TextKit编辑器图及哈希，[原生渲染证据](evidence/vault-form-quality/visual-proof.json)记录实际查看的7张图片。包含空状态、差异详情、401项真实核心计算结果、中文／英文表单与长代码高亮。配置名称和确认在首屏完整可见，保留奶油白／柔粉、统一白鹅、真实统计与列对齐。

图片是NSHosting/AppKit的cacheDisplay输出，不是桌面截图。整页未捕获嵌入TextKit绘制层，代码另存原生编辑器图片并验证实际文本，不拼接。1720测试窗口解除物理屏幕约束，只证明布局，不声明已验证更宽显示器。合成Vault计划只用于布局；namespace菜单项实际选择／计划展开后的滚动与最小1050×700窗口仍需补验证。

Release、本机ad-hoc签名、包内XPC与stdioMCP通过。[ZIP全新解压核验](evidence/vault-form-quality/package-check.json)核对全部包文件、二进制可执行权限及deep／strict签名。包为 `build/Config Compare Vault Form Quality.zip`，SHA256 `c414bc880ccf24e823eda5112836d13a63c5bf98b6d15803b146d5cb5a2bf0aa`，不是正式公证发行。

## 独立评审与当前工作区

[CC与DS最终独立接受同一8a6e源码增量](evidence/vault-form-quality/review-synthesis.json)，无阻塞，wholeGoalAccepted均为false。CC原会话 `cf6a574e-e964-4a7a-a659-d1b4692557ae` 正常exit0／timedOut=false，实际claude-opus-5-5[1m]；没有因为观察等待而重启。终端摘要指向其计划文件的完整JSON，保存原CLI／摘要／JSON，不把手工摘要伪装成原返回。CC实际复算143项冻结文件、141项主基线、共享提示哈希及两份源码差异，没有执行测试／探针或查看图片。只写自己的计划文件和两个/tmp差异文件，没有更改项目。DS只读相同提供文本，实际deepseek-flash，没有本机哈希计算、测试、桌面或图片审查。

保留CC关于1050×700、构建目录／Release／scratch-path依赖、未来控件查找和合成mouse-up可能重复的非阻塞意见；同步探针不用于声明真实鼠标／键盘／AX通过。每个子进程单独限30秒，编译与运行总计可达60秒，CC将两者概括为总共30秒并不准确。DS对声明哈希的一致性检查也不是本机密码学复算。

经过双评审才将确切两项产品源码及两项测试文件合入主项目，逐字节等于143项冻结候选。[评审后完整性](evidence/vault-form-quality/post-review-integrity.json)核对共享提示、ZIP与主清单稳定，原App全部8个包文件未改、只剩原主进程PID47589，当前输入没有更改或强制比较。Penguin重新索引返回MUTATION_DISABLED，没有改服务设置或声称索引成功。

完整桌面键盘／IME／VoiceOver、20MiB冷P95、完整应用生命周期、macOS14／Intel、正式发行与原91项门槛仍开放。没有使用生产、真实Vault／App Token或通用剪贴板，当前用户App／输入保留。

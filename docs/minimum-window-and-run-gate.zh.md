# Vault 小窗口与整次测试完成门禁

> 最新[许可证／NOTICE资源交付](license-delivery-quality.zh.md)：0fd389候选315项源码、14门禁／361项命名测试、105份原生渲染、新包177文件及同候选CC／DS独立源码接受通过；仅开发构建与本地资源增量已合入。当前App与输入保留，完整目标／正式发行仍active。

> 历史[测试记录与自有进程组清理](run-lifecycle-quality.zh.md)：同一ed3423候选13门禁／345项命名测试、105份原生渲染、ZIP核验与CC／DS独立源码接受通过；两个脚本已合入，当前App与输入保留。完整目标仍active。

2026-10-04。奶油白、柔粉、马卡龙与本地白鹅的 SwiftUI／AppKit 界面继续沿用。源码候选 `36fbb707b1232bc4739cefebb7fa189bd310f85b4bfb8bdc32cf845ffef1e2c0`（143文件）已经过 CC／DS 独立接受并合入主项目；完整目标仍 active。

## 实际改动

相对已接受的8a6e候选，只修改四项：

- `ConfigCompareApp.swift`：Vault 标题／主操作固定在滚动区外，主体使用真实原生滚动；结果卡最低148点。没有结果时来源视口294～360点，有结果时160～250点；短于800点的工作区使用52点统计卡和10点间距。小窗口紧凑间距与统计样式也适用于 env.js；其他页面继续沿用共同视觉语言。
- `VaultViewportTests.swift`：增加中英文、四尺寸的真实 NSView 滚动与可见性回归。沿用真实 Rust FFI 的合成 JSON 比较输出作为布局样本，随即释放创建的会话。未伪造产品统计，也不冒充实际 Vault 连接／选择工作流。
- `check-network.py`：校验完整 Swift Testing 运行和实际发现清单，不再只凭 HTTP 套件通过；保存主运行输出后才发现清单，失败或超时保留日志，失败运行替换旧的绿色记录。
- `test-verifiers.py`：补充整次运行缺失、前端用例遗漏、伪计数、身份重复／同名冲突、失败日志／退出码与超时的负向验证。

比较算法、模型、编辑器、Vault 请求与生产拒绝策略、MCP、栈和白鹅素材未改。[候选清单](evidence/minimum-window-and-run-gate/candidate-source.manifest.sha256)、[四文件差异](evidence/minimum-window-and-run-gate/candidate.diff)、[主源码清单](evidence/minimum-window-and-run-gate/root-source.manifest.sha256)可逐字节复核。

## 实际失败与修复

旧1050×700的结果视口高度为0。初次缩减后中文42.5点、英文仍0；再次缩减只给英文64.5点，余量不足，没有将它作为最终完成。最终用原生页面滚动及结果最低高度保留工作内容，标题和主要操作保持固定。[真实几何红灯](evidence/minimum-window-and-run-gate/minimum-viewport-red.log)与两次未采纳记录均保留。

程序滚动后，中英文在1050×700、1280×800、1440×900、1720×1000的结果视口分别为92、120.5、198.5、276.5点，能容纳当前62点结果行；全部16个来源字段及两项真实非生产确认控件可达，名称／确认状态不变。[八组实测几何](evidence/minimum-window-and-run-gate/accepted-minimum-viewport.json)来自最终完整运行。名称／确认的首屏要求继续在原三尺寸通过；最小尺寸及有结果时允许滚动访问，不能描述为全部控件同时首屏可见。现有同步原生绑定探针也在本候选完整运行通过；32条条件断言不作为32个测试累加。

旧 HTTP 门禁会接受“只有 HTTP 套件完成”“漏前端用例却总计成功”“最终计数错误”三种损坏输出。[三个最终负向用例在旧源码均失败](evidence/minimum-window-and-run-gate/final-negative-tests-on-baseline.log)，证明原门禁确有缺口。新校验器要求全限定身份、串行开始／通过、套件完整结束、唯一整次成功记录及与发现清单相符的计数；异常、跳过、重复、尾随事件和不支持的命名／参数化格式明确失败。42项 Python 回归通过，真实历史197项／24套完整日志也通过新校验器。

首次bb2b候选的完整运行在180秒超时，冷构建66.81秒；记录为失败，不能声明整套 Swift 通过。[原失败及部分输出](evidence/minimum-window-and-run-gate/first-full-timeout/verification/results.json)保留。此前8a候选清单生成失败仍未归因，不能将本次已确认超时当作其原因。

整套检查的新上限300秒包含冷构建与原生渲染，没有更改产品网络期限、减少用例或降低断言。36fbb从clean重跑的[13门禁](evidence/minimum-window-and-run-gate/verification/results.json)全部通过，源码起止相同；Swift检查181.67秒。Rust95＋Swift198／24套＋Python42＝[335项命名测试](evidence/minimum-window-and-run-gate/test-counts.json)，专项重复和窗口／语言组合不重复累加。[自建 HTTP／TLS](evidence/minimum-window-and-run-gate/network-check.json)11项、71个loopback GET，零生产、真实Vault、真实Token、重定向、Cookie或信任变更。

## 页面、图像与交付边界

最终本机运行保存105份PNG：原19状态×三尺寸57整页、4独立原生编辑器图、12 Vault 初始／菜单计划布局图、32 Vault 核心结果布局与滚动位置图。实际查看8份：[图像哈希与实看记录](evidence/minimum-window-and-run-gate/visual-proof.json)。覆盖比较、结果不完整、长内容、详情、YAML与全页设置等现有页面，保留奶油白、柔粉、同一画风白鹅、真实统计和列对齐。

图像是自己的 NSHosting／AppKit cacheDisplay 输出，**不是桌面截图**。整页没有捕获TextKit嵌入层，代码另存原生编辑器图并核对文本，没有拼图。1720窗口解除了物理屏幕约束，仅证明布局。1050仅新增Vault专项；其他页面最低原生检查仍为1280，不能宣布全产品最小尺寸、实际滚轮／触控板、键盘、IME或VoiceOver都已通过。

Release／本机ad-hoc、包内XPC与stdio MCP通过。[ZIP全新解压核验](evidence/minimum-window-and-run-gate/package-check.json)比较8个包文件哈希、2个执行权限及deep／strict签名。MCP入口是同一App的`--mcp`，不是独立MCP二进制；首次核验错误假设另有该文件，按实际构建／MCP运行契约纠正并保留原记录。包为 `build/Config Compare Window Quality.zip`，SHA256 `996620942c92b18a0b44aba79dd20e06df5a4f91534234cac0e6cde8a2bdb709`，不是正式公证发行。

## 双独立评审与剩余工作

[CC／DS接受同一36fbb源码增量](evidence/minimum-window-and-run-gate/review-synthesis.json)，无阻塞，wholeGoalAccepted均为false。CC原会话 `de333359-8049-4a13-824e-90ea647fb992` 正常exit0／timedOut=false，实际claude-opus-5-5[1m]；保留原会话，没有因观察等待重启。CC复算143项冻结文件，核对两份清单及四项差异，检查源码和198／24套运行日志，没有重跑测试／构建或查看图片，只写自己的计划文件。其若干shell片段外层用了rtk proxy，但包含未加前缀的cd／内部命令，不声称每一段都按要求加了前缀。

DS实际deepseek-flash，通过官方API只阅读提供的文本，没有本机文件／工具、测试或图片访问。原返回声称做了rtk本机检查，这不是实际证据；其“本机完整门禁仍待完成”也与已附的13项通过事实相矛盾，综合结论以原始门禁记录为准。原91项和完整目标仍开放，不因此把文本错误转成验收证明。

保留两模型非阻塞意见：结果行62点与卡片148点可进一步用共享常量／实际几何约束；固定主按钮的滚动归属缺少直接断言；失败阶段和suiteExitCode记录可更细；已知问题／警告形式的通过行需进一步收紧；超时后子进程组清理、未来测试格式、原生控件语义识别和真实滚轮交接需补证。本次超时后的进程检查未见残留Swift测试／helper，不能把潜在子进程问题写成已观察到的泄漏。

[评审后完整性](evidence/minimum-window-and-run-gate/post-review-integrity.json)确认主项目与冻结143文件一致，共享提示和ZIP未变，用户当前App8个包文件未改，仍只有原主进程PID47589，没有另开主GUI、修改用户输入或通用剪贴板／真实Vault Token。新源码和ZIP已交付，当前运行窗口未切换。完整桌面／设备、20MiB冷P95／交互响应／峰值内存、完整App生命周期、namespace菜单选择／计划展开、测试探针构建目录适配、macOS14／Intel、正式发行及原91项继续开放。

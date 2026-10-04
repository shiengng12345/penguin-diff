# 白鹅编辑器：行号修订与交付边界

2026-10-04。本轮继续沿用 SwiftUI／AppKit／Rust，奶油白、草莓粉及本地二维白鹅视觉基础保持。比较算法、Workspace、WireModels、Vault 和 MCP 源码逐字节不变，没有连接真实 Vault 或生产环境。

候选 `2f080310dd3ac0613d24d2d80b5e634dab4c34a7001ce18f00643b77306d8d7e`，140 文件。相对已接受编辑器版本 `20bc16ef…`，只修改以下两项：

| 文件 | 实际变化 |
| --- | --- |
| [SourceEditor.swift](../apps/macos/Sources/ConfigCompare/SourceEditor.swift) | 行号栏按数字位数增宽及缩回；仅在位数变化时调整宽度；LF／CR／CRLF 末尾空行显示正确行号；空文档第 1 行与普通文档位置一致；复用文字属性，避免绘制时桥接整份源文本 |
| [GutterQualityTests.swift](../apps/macos/Tests/CompareTests/GutterQualityTests.swift) | 三项原生回归覆盖 100001 行宽度及缩放恢复、首行实际笔画与对齐、三种换行在导入／原生编辑／滚动到底部的九个绘制场景 |

末尾空行通过既有 TextKit 的 extraLineFragmentRect 绘制；只在当前可见字形对应字符范围到达文末时查询，避免每次绘制强制排版整个文件。文字、选择、撤销和比较行为没有改写。

## 验证状态

补强的三项专项已实际通过。旧行为实际复现行号栏 38 点不足以显示所需 54 点、三种末尾换行缺少行号、空与非空首行不对齐。CC 指出旧图片比较可能因两张都空白而误通过，DS 建议避免依赖整张 PNG 字节；现改为两侧必须存在真实笔画，再以 0.5 点容差比较笔画坐标。

[13 项完整冻结门禁](evidence/gutter-quality-v2/results.json)全部通过，起止清单稳定。Rust 95、Swift 189（22 套）、Python 33，共 **317 项命名测试**；九个绘制场景属于其中三项测试，不重复累加。另含可信合成 Node 对照、报告与深度保护、11 项自建 loopback HTTP／TLS、Release 打包、XPC 与 stdio MCP。

新包 `build/Config Compare Gutter Quality v2.zip` 已完成[全新解压与严格签名核验](evidence/gutter-quality-v2/package-check.json)。这是本机 ad-hoc 签名测试包，尚未通过正式发行验收。原工作区、冻结源码与门禁清单逐字节相同；当前主 App 文件未改变，只有原来的一个主进程。

[本候选原生渲染](evidence/gutter-quality-v2/visual-proof.json)共 61 份整页／编辑器图，另有九份行号图；三个视口为 1280×800、1440×900、1720×1000 点。人工检查了初始页、英文设置页、401 条真实合成比较结果页、JS／YAML 独立编辑器，以及长文档文末空行。图像取自真实原生视图，统计经真实 Rust FFI 计算，没有装饰性假记录。

[同候选独立评审](evidence/gutter-quality-v2/final-review-synthesis.json)：Claude Code 与 DeepSeek 均为 `ACCEPT_SOURCE_CHANGE`，无阻塞，`wholeGoalAccepted=false`。两者收到同一份最终提示和证据；[评审后源码／提示／ZIP 完整性](evidence/gutter-quality-v2/post-review-integrity.json)再次核对通过，不继承旧候选接受。

CC 实际模型为 `claude-opus-5-5`，CLI 正常结束、无超时；实际复算冻结清单和全部 140 文件哈希，并阅读行号实现及调用路径，没有重跑测试、构建或查看图片。DS 请求 `deepseek-chat`，实际返回 `deepseek-flash`；只审阅提供的文本，不能独立核对本机文件或执行结果。

CC 的非阻塞建议涉及未来 inset／origin 变化的一致性和进一步独立验证行距；当前原生对齐与旧代码运行期失败均有证据。DS 关于字体变化缓存的建议属于未来能力，当前字体固定；九场景图片相同符合相同视觉结果，不人为制造不同图像。三项命名测试与九场景已分别计数。

## 保留的未验收范围

- [大文件完整挂载实验](editor-performance-investigation.zh.md)未达性能预算，TextKit 2 实验已隔离，没有进入这个候选。
- 原生 view 渲染不能替代实际桌面截图。全页渲染不含内嵌 TextKit 文字层，编辑器另存独立视口图；1720 点视口属于测试窗口，尚未验证真实宽屏设备。
- 实际键盘／输入法／VoiceOver、最低支持 macOS 14、完整性能、干净目标设备及正式分发继续开放。
- 当前用户窗口仍运行白鹅视觉基础版 `8df029ff…`，没有退出、替换、另开主 App 或修改其中输入。

本轮源码增量接受不代表原始 91 项要求和完整产品目标已经完成。

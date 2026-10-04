# 编辑器行号裁剪与代码可见性修复

2026-10-04。主源码已合入冻结候选 `56b6d94b3a3da82255b22fd5b3f3502c2a30126ef80c55c49413a239476bb5bb`（329 文件），在最新 Vault 下拉发现候选上修复整页代码文字被背景覆盖的问题。只修改两个源码文件，保持 SwiftUI／AppKit、比较算法、安全解析、Vault／MCP 权限与行为。

## 实际修改

- `apps/macos/Sources/ConfigCompare/SourceEditor.swift`：LineNumberRuler 初始化显式设置 `clipsToBounds = true`，使行号背景只画在自己的列内。
- `apps/macos/Tests/CompareTests/EditorDrawingTests.swift`：两项完整父视图／真实 WorkspaceView 的像素回归，覆盖 A/B 初始、缩放、替换和原生 insertText，并核对 UTF-16 原文。使用已有禁止展示／抢焦点的测试窗口。

原始诊断观察到 `drawHashMarksAndLabels` 的失效矩形宽 360，而行号 bounds 宽 38；`rect.fill()` 越过行号列。Apple 本机 macOS 26 SDK 的 NSView.h 注释指出 macOS 14 起 clipsToBounds 默认 NO。历史调查及被中断的旧候选保留在[诊断记录](editor-desktop-drawing.zh.md)，不能冒充本轮完整通过。

## 失败复现与完整验证

[最新基线 RED](evidence/editor-ruler-visibility/drawing-red.log)实际退出 1：两个测试中六处完整父视图代码区域均为零个深色字形像素。没有用局部编辑器捕获或编译错误替代绘制失败。[修复 GREEN](evidence/editor-ruler-visibility/drawing-green.log)实际退出 0：初始 A/B、独立编辑器与缩放均为 3991，替换 4459，插入 6368；输入内容保持。

[15 项完整门槛](evidence/editor-ruler-visibility/verification/results.json) runID `cc8482cf-6362-4159-9aa9-e7c7e4f1983a`，源码起止清单稳定，全部命令 exit 0，完成标记为真。Rust 95 项、Swift 229 项／29 套件，另有入口路由、验证器负向、许可证、可信 Node 合成 JS、JSON／CSV、深度保护、Release 签名、真实包内 XPC 和 stdio MCP 检查。不是只跑两个新增测试。[真实 URLSession HTTP／TLS](evidence/editor-ruler-visibility/network-check.json) 11 项通过，重定向目标零请求、Cookie 零请求，没有改变系统证书信任；只访问临时 loopback 合成服务。

## 页面检查

[原生渲染记录](evidence/editor-ruler-visibility/visual-proof.json)：67 张整页／编辑器图像和 12 张 Vault 下拉图像，1280×800、1440×900、1720×1000。实际查看 8 张，覆盖初始 A/B 文字、原生插入、不完整长内容、401 项真实合成比较结果、选中详情、YAML 输入／结果、全窗口设置返回与 Vault 下拉。空状态、单侧、就绪、比较中、相同、差异／未知、无搜索匹配、读取／解析错误和长文件名均由原有真实控制器状态生成，无假填充行或统计。

这些是 AppKit cacheDisplay 位图，**不是系统桌面截图**，不替代肉眼显示、真实键鼠、IME、VoiceOver、Reduce Motion 或实际显示器证据。本轮不启动／切换用户 App，不修改其输入；测试禁止前置或抢焦点。已有 Vault 原生鼠标探针使用自有透明、不可聚焦且忽略真实鼠标的 WindowServer 表面，排在普通窗口下面；不能称为完全没有 WindowServer 交互。

## 独立评审与包

[CC／DS 结论](evidence/editor-ruler-visibility/review-synthesis.json)分别来自实际 Claude Code Local 和官方 DeepSeek API，对同一 `56b6d94b…` 冻结候选接受本增量、无阻塞。完整原始回复保留；模型阅读与本机运行证据分开，不宣称评审员重跑测试。仅此两文件增量接受，不是全产品／91 项／正式发行接受。

新包：[Config Compare Ruler Quality.zip](../build/Config%20Compare%20Ruler%20Quality.zip)，App 同名，ZIP SHA-256 `4523e0c2840aa64a4791588e121682383e1403142549e7b27e180211da7ed3fd`。[10 项交付检查](evidence/editor-ruler-visibility/package-check.json)验证原包／全新解压的 181 文件字节及执行权限一致、深度严格签名、资源与许可证、实际 XPC 自检。自检窗口数零。开发签名包不等于 Developer ID／公证／首次下载验收。

[合入完整性](evidence/editor-ruler-visibility/post-review-integrity.json)确认主源码逐文件匹配评审候选，只合入这两文件，原三份 App 产物字节不变；没有 commit／push。既有 Vault 下拉的非生产确认、分层 KV／namespace／名称读取、全部目录与高级通配符继续保留，没有连接真实 Vault 或生产。

## 未完成范围

完整目标继续 active。实际桌面代码显示、全键盘／输入法／无障碍、真实 20 MiB 完整挂载性能与生命周期、包内 worker 运行中外部退出、完整 91 项、干净 arm64／所承诺 Intel 系统、明确批准的真实非生产部署、Developer ID／公证／stapling 与 Gatekeeper 仍未全部验证。没有把隔离的 TextKit／非连续布局实验合入本候选，标准未降低。

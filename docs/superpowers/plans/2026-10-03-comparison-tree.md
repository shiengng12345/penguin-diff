# 对比结果树与导入停止实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans 在当前已授权工作区逐项实施；不自动提交、推送或发布。用户已要求完成原计划全部功能和测试。

**Goal:** 完成原计划 C17 的嵌套阅读能力，保留计数、完整性、筛选与导出契约，并使导入可主动停止。

**Architecture:** 主表在平面/树形模式间切换，树只组织当前页最多200个真实结果项，用 UTF-16 Key/数组索引机器路径作为身份，分组不是新增差异。详情树只读展示已取得的完整类型树，单侧容器与类型变化的内部项不重复计数。使用原生分层 Table/分层 List，保留共享 A/B 列与原结果 ID。

**Tech Stack:** SwiftUI（macOS14）、现有 Swift DTO/Workspace、Rust C ABI/XPC；无新增依赖或网络能力。

## 已确定的设计

完整结果树一次加载十万结果会破坏当前分页和按需详情边界；用路径文本拆分又会混淆含点号、斜杠、空串、孤立 surrogate 的 Key。因此采用机器路径的当前页分组与独立详情树。界面明确标注“当前页树”，不把当前页称为完整树；总计、匹配数和报告仍来自原核心会话。

终端结果身份为 result(id)，纯分组身份为 branch(machineSegments)。详情身份为根内的机器路径；对象 Key 与数组 index 不互换，Unicode 不归一化。无机器路径的旧 DTO 单项保留平面叶节点，不从显示路径猜测结构。

## 执行步骤

- [x] 写导入停止策略测试；`Workspace.canStop = busy || importing` 同时驱动菜单与 toolbar，`cancel()` 继续使旧导入成功/失败失效。
- [x] 新增 `ResultOutline.swift` 与 `ResultOutlineTests.swift`。先验证新 API 缺失，再实现纯树投影：`ResultOutline.build([ResultRow]) -> [ResultOutlineNode]`；`ValueOutline.children(of: Side) -> [ValueOutlineNode]`。
- [x] 测试真实核心行的完整路径/机器身份、重复前缀聚合、UTF-16 Key/数组 index、不完整状态、空容器、单侧容器详情、过滤/分页，以及展开前后报告逐字不变。纯分组与详情子项不参与 Summary。
- [x] 使用 `Table(nodes, children: \.children, selection:)` 添加共享 A/B 树表，保留平面模式；结果项选择继续驱动原 inspectSelection。检查器显示原完整 literal 和可折叠只读结构，不增加复制隐式动作。
- [x] 避免把大 literal 放入每个结构 cell；用已有 bounded display，完整文本仅原检查器/明确复制。无损显示 UTF-16 Key：合法 Unicode 保留，孤立 surrogate 显式转义。
- [x] 在打包 XPC self-test 加入树投影/详情桥接断言；完整规范验证、负向门禁和同候选 CC/DS 独立复核。
- [ ] GUI 折叠/键盘/VoiceOver 仍必须有实际 Sky 证据，不用纯模型测试冒充。

验证命令：`rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apps/macos --no-parallel --filter 'ResultOutlineTests|ImportLifecycleTests'`；随后 `rtk proxy python3 scripts/verify-local.py`。

原生层级表 API 依据：[Apple Table children](https://developer.apple.com/documentation/swiftui/table/init(_:children:selection:columncustomization:columns:))；已由当前SDK接口和macOS14部署目标编译验证，不能替代最低系统真机证据。

实现、本机门禁与同候选 c74e1d90 独立 CC/DS 接受已完成；GUI 阶段仍 OPEN，分别记录在全量审计，不自动提交或发布。非阻断建议中的导入停止/模型选择失效/Unicode显示进入下一增量，不把本轮接受继承给新源码。


后续质量增量：ccaae0f7修复单独取消导入保留有效结果及selected模型同步失效；8540e486将Branch显示前缀增量缓存、freeze改显式后序遍历。深度120×200真实CABI在小测试线程栈通过，原递归崩溃、同测试快照修复绿及性能基线保留。当前规范62 Rust/74 Swift/14 Python与十项门禁通过，CC/DS独立接受同一8540e486。参考机模型深树P95从1332.222ms降到60.376ms，额外深层包内MCP/XPC通过；模型测量不是GUI帧时间或App内存证明。GUI勾选继续保持未完成；Unicode显示、128/129与更小栈、完整资源和发行门槛仍待补。

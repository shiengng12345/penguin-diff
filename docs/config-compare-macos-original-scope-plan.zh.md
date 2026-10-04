# Config Compare：macOS SRE 配置小工具计划

> **2026-10-04 当前视觉资源清理：**本轮按用户最新要求移除 App 内全部白鹅／企鹅插画、动物头像、冬日主题及对应本地资源；设置页、侧栏、空状态和结果页改用中性 SF Symbols。用户提供的 `codex-clipboard-ISPDA5.png` 原图直接保存为 `assets/config-compare-icon.png`，仅在打包时生成 macOS 所需的多尺寸 `ConfigCompare.icns`，作为唯一 App 图标来源。比较算法、env.js／Vault／YAML 功能、只读非生产边界与 MCP 行为未改变。Release 构建、打包自测、CLI 路由、图标资源和设计／设置聚焦测试已通过；全量并行 Swift 测试仍有既有窗口／异步时序失败，未将其标记为整体通过。

> **2026-10-04 最新 Vault URL 协议增量：**候选 `b7c5ca5b3eff90d65e3ee8b94519cc53fae8a8024c67f136116cde0b9a6ef778` 已移除入口处的 HTTPS-only 校验，错误文案改为通用 Vault 地址提示，并新增 HTTP 与 `vault://` 解析回归。账号、密码、fragment、端口、路径和生产标识校验保留；非 HTTP scheme 的解析接受不等于底层 URLSession 已验证连通。完整门禁 15/15，Swift 251 tests／30 suites，`realVaultAccessed=false`；CC 与 DeepSeek 对同一 SHA 均 `ACCEPT_LOCAL_CHANGE`。详见[协议专项](evidence/vault-url-scheme-review-synthesis.json)和[本轮门禁](evidence/vault-url-scheme-main-rerun.json)。

> **2026-10-04 最新目录优先／共同配置过滤修订：**候选 `aa270086dc10dd2c933b7f5e2baccc3666bc6456324dfa571df65f2bd969f567` 已完成 15/15 本机门禁、Swift 250 tests／30 suites；`VaultReader` 现在把目录匹配 `.` 明确作为根目录单层读取，只有真实 `**` 扫描才计算全目录交集。`auth`、`payment`、`promotion` 等目录选择后，配置名称只显示所选范围内存在的名称；选择全部目录时只显示每个已发现目录共同拥有的名称，空目录会使交集为空。namespace、mount、目录根与匹配范围变化会清理无效旧值，高级手动配置名称仍可编辑；A/B 继续隔离。CC 与 DeepSeek 对同一 SHA 均 `ACCEPT_LOCAL_CHANGE`，blocking 为空。loopback、打包、NOTICE、资源、签名与 self-test 已通过，`realVaultAccessed=false`，`formalReleasePassed=false`。详见[专项记录](vault-directory-filter-quality.zh.md)、[本轮门禁](evidence/vault-directory-filter-main-rerun.json)和[双审合成](evidence/vault-directory-filter-review-synthesis.json)。

> **2026-10-04 最新目录优先下拉与自动生产拦截增量：**Vault 表单已改为先选 Directory scope，再选 configuration name；`**` 全目录范围只显示所有已发现子目录共同存在的名称，避免把只存在于单一目录的配置误选为批量范围。手动非生产勾选已移除，程序仍拒绝可识别的 `prod`／`production`／`prd` 标识；本轮不连接真实或生产 Vault。对应实现位于 `VaultContents`、`VaultConnectionPanel`、`VaultReader` 与 `Workspace`，并新增全目录交集和无手动确认的回归测试。

> **2026-10-04 Vault 取消／迟到响应复审：**候选 `088678478a170a3d9b4283ea7f6f53dd9819c03200d52a098dc5f4fab5b710d6` 已由 CC 与 DeepSeek 针对同一 SHA 独立复审并返回 `ACCEPT_LOCAL_CHANGE`，blocking 为空。接受范围仅是本机合成 Vault 生命周期模型；真实网络、生产 Vault、打包 worker 外部终止、GUI/VoiceOver/输入法、设备和正式发行仍开放。详见[专项记录](vault-cancellation-quality.zh.md)与[双审合成](evidence/vault-cancellation-review-synthesis.json)。

> **2026-10-04 最新 Vault 取消／迟到响应增量：**本地候选 `088678478a170a3d9b4283ea7f6f53dd9819c03200d52a098dc5f4fab5b710d6` 完成 15/15 门禁、Swift 245 tests／30 suites。Vault Reader 已覆盖 KV v1/v2 的 403/404/429/503 中途失败整批丢弃与显式干净重试；取消后释放的迟到 data 回复不会形成部分结果；Workspace 在 scope 改动后不会被旧响应恢复。`realVaultAccessed=false`，正式发行仍为 false；这轮仅将 V15/V16 记录为本机模型部分通过，GUI、打包 worker、真实非生产网络与正式发行仍开放。详见[Vault 取消／迟到响应专项](vault-cancellation-quality.zh.md)、[本轮门禁证据](evidence/vault-cancellation-main-rerun.json)。

> **2026-10-04 最新 J18/C07 文件编码与特殊值增量：**主源码候选 `a7d7f9714c8b50fedf8732dee368581387500cbf92163aa4428cb8554237008b`（331 文件）完成 15/15 本机门禁、Swift 243 tests／30 suites。文件读取经匿名进程内 NSXPC 到 Workspace 的 BOM/无 BOM、LF/CRLF、中文路径／字节列，以及经 NSXPC 的 Missing/null/undefined/空字符串／三种类型变化详情矩阵已通过；loopback 网络与打包 XPC/MCP/NOTICE/资源/ad-hoc 签名核验通过，`realVaultAccessed=false`。这轮只推进 J18/C07 的本机模型证据，SwiftUI/键盘/VoiceOver、独立 worker 压力、设备和正式发行仍开放；malformed EOF 错误没有可靠行列偏移，未伪造结果。CC 与 DeepSeek 已针对同一 SHA 返回 `ACCEPT_LOCAL_CHANGE` 且 blocking 为空，但没有把 GUI/打包 worker/正式发行边界算作完成。按 91 项严格分类：51 项完整关闭、24 项部分证据、16 项纯 OPEN，完整关闭率 56.0%。详见[文件编码与特殊值增量](file-encoding-ui-quality.zh.md)、[本轮证据](evidence/file-encoding-ui-quality-main-rerun.json)和[双审合成](evidence/file-encoding-ui-quality-review-synthesis.json)。

> **2026-10-04 最新 N4 Unicode 行／分组一致性增量：**主源码候选 e503684dc4c354c2b0c96bcd493e1a60ad187cb9fc1d41cbb617059a5d833154（331 文件）已合入。比较核心现在只把 ASCII 字母／数字／下划线使用点号路径；é、中文、组合字符、点号和 lone surrogate 使用带引号的括号路径，Swift ResultOutline 按 UTF-16 machine path identity 保持分组一致。正式 15/15 门禁、Swift 237 tests／30 suites、Rust／Swift 聚焦回归、ad-hoc 包签名／XPC／MCP／资源核验通过，realVaultAccessed=false；Claude Code 与 DeepSeek 对同一 SHA 均 ACCEPT_LOCAL_CHANGE。[N4 修订记录](unicode-groups-quality.zh.md)。真实 GUI／设备／非生产部署／正式发行仍开放，完整目标保持 active。

> **2026-10-04 最新导入生命周期 N2 增量：**主源码候选 `d73132e2c1b6512054cfd99fc8015f82368eb368eb8f1852d254c6a04de8ec00`（331 文件）已合入。导入取消后的迟到成功／失败测试改为等待真实 import Task 的 MainActor `defer` 完成通知，覆盖取消、旧导入替换、双侧取消与工具切换；原固定 10ms 等待已移除。正式 15/15 门禁、主工作区 `swift test --no-parallel` 的 236 tests／30 suites、突变负向验证均通过；Claude Code 与 DeepSeek 对同一 SHA 均 `ACCEPT_LOCAL_CHANGE`。[修订记录](import-lifecycle-quality.zh.md)。N4 Unicode 行／分组一致性、真实 GUI／设备／非生产部署／正式发行仍开放，完整目标保持 active。

> **2026-10-04 最新行请求去重增量：**主源码候选 `8d0a33f5bf778c5941c545b04177d740e24d058e0ea74c5177403b553af5566a`（331 文件）已合入。相同 session／页码／筛选／搜索条件的在途 rows 请求只保留一个，失败／取消／旧 session 仍受原 token guard 保护；正式 15/15 门禁、Swift 236 tests／30 suites、同 SHA 的 CC／DS `ACCEPT_LOCAL_CHANGE` 均已记录。[修订记录](rows-dedup-quality.zh.md)。完整目标、真实 GUI／设备／发行与生产禁止边界保持 active。

> **2026-10-04 最新主源码：**`e20e0d03be1bb7c36a67de352cb39370ab00e65f609cea1ab77282fc6dc55403`（331 文件）。本轮修复重复 GUI 实例：正式 `com.penguin.configcompare` 使用用户级非阻塞 `fcntl` 锁；只向已完成启动的旧 peer 交接，并在 macOS 14 上协作激活／复用已有 bundle；CLI、MCP、XPC worker、非打包测试不启用。隔离候选 15/15 门禁全部通过，Swift 235 tests／30 suites，`realVaultAccessed=false`；Claude Code 与 DeepSeek 对同一 SHA 均 `ACCEPT_LOCAL_CHANGE`。未启动用户 App、未关闭窗口、未改变输入、未连接生产 Vault。详见[单实例修订记录](single-instance-quality.zh.md)。

> 上一轮主源码 `56b6d94b…`（329 文件）：[代码显示／行号裁剪修复](editor-ruler-visibility.zh.md)已通过 15 项完整本机门槛、Rust 95／Swift 229 项测试、新包 10 项核验及同候选 CC／DS 独立增量接受；Vault 链接＋Token 下拉发现与批量比较保留。代码文字在整页原生图像中恢复，实际桌面／输入法／设备／完整性能／正式发行和原 91 项仍未全部验收。没有启动、关闭、切换用户 App 或改变其输入。

> 下文旧版本的“当前”哈希、运行窗口、深浅色和计数均只对应各自历史记录；本轮没有重新核对用户窗口 PID，不继承旧版接受为完整目标通过。

> 最新[许可证／NOTICE资源交付](license-delivery-quality.zh.md)：0fd389候选315项源码、14门禁／361项命名测试、105份原生渲染、新包177文件及同候选CC／DS独立源码接受通过；仅开发构建与本地资源增量已合入。当前App与输入保留，完整目标／正式发行仍active。

> 历史[测试记录与自有进程组清理](run-lifecycle-quality.zh.md)：同一ed3423候选13门禁／345项命名测试、105份原生渲染、ZIP核验与CC／DS独立源码接受通过；两个脚本已合入，当前App与输入保留。完整目标仍active。

> 上一[Vault小窗口与整次完成门禁](minimum-window-and-run-gate.zh.md)：固定标题／主操作、可滚动工作区和结果最低高度；中英文四尺寸原生字段／结果可达，13门禁／335项命名测试、105份原生渲染、ZIP核验及同候选CC／DS源码接受通过。源码已合入，当前App与输入保留，完整目标仍active。

> 上一[Vault表单首屏与绑定修订](vault-form-quality.zh.md)保留为8a6e候选的历史记录：中英文三尺寸首屏、原生交互32断言、13门禁／325项命名测试、71份原生渲染及双源码接受通过。

> 后续[Unicode 输入／结果过期修订](unicode-workspace-quality.zh.md)：5项完整页面回归在旧代码复现17条断言；修复后13门禁／322项测试、三尺寸19状态原生布局、ZIP核验及同候选CC／DS源码接受通过。确切修订已合入项目；比较核心与当前用户窗口未替换，完整目标仍active。

> 后续[编辑器生命周期调查](editor-lifetime-investigation.zh.md)：补强隔离候选200项原生回归通过，20 MiB Debug／Release固定样本通过500ms断言。CC同意继续实验，DS仍要求修改；旧Swift Testing残留及普通窗口动画释放未完成归因，完整应用集成与最终双验收开放。该布局／所有权实验未进入主源码，当前用户窗口未替换，不声明完整目标通过。

> 版本：1.35 · 新增[目录优先下拉与自动生产拦截增量](vault-directory-filter-quality.zh.md)、[Vault 取消／迟到响应专项](vault-cancellation-quality.zh.md)与[双审合成](evidence/vault-cancellation-review-synthesis.json)，并保留[N4 Unicode 行／分组一致性修订](unicode-groups-quality.zh.md)、[导入生命周期 N2 修订](import-lifecycle-quality.zh.md)、[行请求去重修订](rows-dedup-quality.zh.md)、[单实例锁与重复启动修复](single-instance-quality.zh.md)与[文件编码／特殊值增量](file-encoding-ui-quality.zh.md)；保留[行号边界裁剪与整页代码可见性修复](editor-ruler-visibility.zh.md)和[Vault URL／Token 下拉发现与批量选择](vault-dropdown-discovery.zh.md)；当前界面为奶油白、草莓粉与中性 SF Symbols，App 图标来自用户提供的本地 PNG，不再打包动物插画或冬日主题；[大文件性能调查](editor-performance-investigation.zh.md)另记未达标实验。完整质量门槛不变。  
> 当前范围：env.js 比较、URL + Token 直连非生产 Vault 批量比较、YAML 格式化、本机 MCP；简体中文／English、显示名称、中性内置图标、奶油白浅色主题与柔和强调色。  
> **禁止连接生产。Vault 支持选择 namespace，以及 namespace / secret 目录通配符。**

上一许可证源码候选 `0fd389c4…`（315文件）：[14门禁／361项测试](evidence/license-delivery-quality/verification/results.json)、[177文件新ZIP核验](evidence/license-delivery-quality/final-package-check.json)及[同候选双接受](evidence/license-delivery-quality/final-review-synthesis.json)通过。原生视觉及比较行为未改；仅补104组件的166份原始许可证／NOTICE／版权资料和离线校验。新包 `build/Config Compare License Quality v2.zip`，当前App与输入保留，完整目标仍active。该候选为素材接入前的历史证据。

上一源码候选 `ed3423a2…`（143文件）：[13门禁／345项命名测试](evidence/run-lifecycle-quality/verification/results.json)、[105份原生渲染／7份实看](evidence/run-lifecycle-quality/visual-proof.json)、[新ZIP解压／签名](evidence/run-lifecycle-quality/package-check.json)、[同候选CC／DS独立接受](evidence/run-lifecycle-quality/review-synthesis.json)及[合入完整性](evidence/run-lifecycle-quality/post-review-integrity.json)通过。只修两项验证脚本的完整记录、精确通过格式和自有进程组清理；产品UI、比较核心、编辑器、Vault及MCP行为未改。新包 `build/Config Compare Run Quality.zip`。当前用户App与输入保留，仅原主进程PID47589；真实桌面／设备／性能／完整生命周期／正式发行／91项仍开放，不能声明100%。

上一小窗口候选 `36fbb707…`（143文件）：[13门禁／335项测试](evidence/minimum-window-and-run-gate/verification/results.json)、[中英文四尺寸原生视口](evidence/minimum-window-and-run-gate/accepted-minimum-viewport.json)、[105份原生图像及8份实际查看](evidence/minimum-window-and-run-gate/visual-proof.json)、[ZIP全新解压／严格签名](evidence/minimum-window-and-run-gate/package-check.json)、[同候选CC／DS独立接受本增量](evidence/minimum-window-and-run-gate/review-synthesis.json)及[评审后完整性](evidence/minimum-window-and-run-gate/post-review-integrity.json)通过。只修改Vault／短窗口布局和测试门禁，不改算法、模型、编辑器、网络或MCP；旧门禁三种假通过已独立复现并修正。首次bb2b完整运行180秒超时真实记失败；扩大整套上限至300秒后，36fbb从clean重跑通过，未减少测试或降低产品网络期限。新包为 `build/Config Compare Window Quality.zip`。1050新增Vault程序滚动专项；其他页面最低原生检查1280。图像不是桌面截图，1720不是实际宽显示器证据。当前运行窗口仍保留原App／输入，没有另开主GUI。完整桌面、设备、性能、生命周期、菜单选择／计划展开、测试构建目录适配、正式发行与91项继续开放；源码增量接受不等于100%。

上一Vault表单候选 `8a6e701e…`（143文件）和325项测试／71份原生图像保留为已接受历史。那轮清单生成失败仍未归因，不与本次已确认的180秒超时混同。

上一Unicode候选 `05f0ae4e…`（141文件）与322项命名测试保留为已接受历史，Unicode输入／过期修订保持在当前源码。

上一轮行号候选 `2f080310…`（140文件）的[317项本机测试与交付边界](gutter-quality.zh.md)保留为历史。TextKit2和非连续布局／生命周期实验继续隔离，没有混入本新包。

用户明确要求填写 URL、Token 直接读取 Vault，不需要复制导出。此前 1.2 把“禁止连接生产”扩大为“禁止连接所有环境”属于理解错误，本版纠正。[1.2 历史稿](archive/config-compare-macos-original-scope-plan.v1.2.zh.md)不再作为连接边界；[1.1 历史稿](archive/config-compare-macos-original-scope-plan.v1.1.zh.md)适用的类型正确性、未知传播、UI、性能与分发要求继续有效。

2026-10-04 后续[非连续布局与绑定同步实验](noncontiguous-layout-investigation.zh.md)取得 20 MiB 独立 Debug／Release 性能改善，并补外部 Unicode 编码同步回归；实验全套原生 196 项仍有两项生命周期失败，未进入主工作区，未打包或取得最终双源码接受。此前 CC／DS 仅认可继续实验，不用于接受后续快照，原完整目标保持 active。

之前 CC/DS 提出的其他工具均为讨论候选，用户未选择，不进入实现。本轮直接实施用户指定功能；[执行任务与证据状态](offline-tools-execution.zh.md)记录进度。

上一轮翻页提示/导出迟到回复修订：`85ea5571fa633635e0a29eaac2eb73bf0474a46889ab6ba67d9e51a31343c876`（135文件）的[13项本机检查](evidence/2026-10-03-result-notice-export-final-results.json)通过，Rust95／Swift158／Python33，共286项测试。8项新回归在旧源码复现6个命名失败/8项断言，修复后与10项分页回归共18项绿。翻页错误重试恢复该次比较的不完整或Vault非原子说明；停止、编辑、新比较和新导出后的旧报告失败不能覆盖当前状态，当前有效失败仍显示。[CC/DS独立接受同一候选本增量](evidence/2026-10-03-result-notice-export-final-review-synthesis.json)，[评审后清单/提示/包核验](evidence/2026-10-03-result-notice-export-final-post-review-integrity.json)稳定。CC仅实际复算5文件哈希及搜索，DS仅文本审阅，两者未重跑完整测试/GUI。

[新包5份实际AX/JPEG](evidence/2026-10-03-result-notice-export-final-gui-proof.json)核对402项不完整结果/第二页、中英文与全窗口设置返回。恢复原env/happy后观察到用户新编辑，保留其最新输入并停止UI修改，最终结果自然过期；不强制重新运行或覆盖内容。该轮仅保留一个对应版本主进程，未注入GUI行错误或在途竞态。

后续：上轮CC指出的提示归属残留已由下述1.16补测并修复。原N-B快速翻页/加载、N-C导入边界、N-D共享超时、详情选择交错、N2/N3/N4，以及完整91项/GUI/键盘/IME/VoiceOver/性能、包内worker运行中退出、干净目标设备、实际获准非生产部署、许可证与正式发行仍OPEN；完整目标保持active。

历史提示/错误归属修订：`db0c3726fb20270ce7fa946b1a98c5d5e3a05a188aa0ca814ff43589cae82771`（135文件）的[隔离源码13门禁](evidence/2026-10-03-notice-ownership-final-results.json)全部通过，Rust95／Swift164／Python33，共292项测试。新增6项回归，旧85ea源码的5项测试中4项运行期失败/5条断言；复制先区分API编译红，再在仅迁移原生依赖参数的旧行为上复现2条运行期断言。统一publishNotice同步提示、错误标记及行错误归属，修复导出/复制后旧错误残留、重试覆盖新提示、非文件导入拒绝被擦除，以及停止/编辑后的错误图标。[40项专项](evidence/2026-10-03-notice-ownership-final-runtime-green.log)与[同候选CC/DS独立接受](evidence/2026-10-03-notice-ownership-final-review-synthesis.json)均通过；完整目标保持active。

[隔离验证与测试包](evidence/2026-10-03-notice-ownership-final-focused-proof.json)：135文件源码清单与原工作区逐字节一致，Rust缓存共享，Swift构建/App输出独立；包内XPC/stdioMCP、ZIP全新解压及深度严格签名通过。[评审后完整性](evidence/2026-10-03-notice-ownership-final-post-review-integrity.json)核对原App文件未改，只剩原来的85ea窗口，没有退出、启动新GUI或更改用户输入。**当前运行窗口仍为85ea；新测试包尚未切换到当前窗口，本次没有新候选GUI证据。**复制测试只使用NSPasteboard.withUniqueName自己的命名板，不读取/写入系统general剪贴板，不代替真实GUI复制/恢复矩阵。

评审边界：CC实际核对3个范围源码哈希及搜索，摘要3项缩写尾码不准确，以原会话工具输出为准；DS仅文本阅读，实际模型deepseek-flash。DS关于后来错误仍会被重试覆盖的推断与publishNotice清除归属、现有根错误和新增导入拒绝回归相矛盾，不当作已证缺陷。CC建议收紧error为private(set)，初次解析失败后的编辑提示等仍需契约核验。原N-B快速分页/加载、N-D共享超时、详情交错、N2/N3/N4和完整91项/GUI/键盘/IME/VoiceOver/性能、包内worker运行中退出、干净设备、明确获准真实非生产、许可证与正式发行仍OPEN。

## 1. 使用目标与边界

给 SRE 一个本机 helper：打开或粘贴配置，看结构差异，整理 YAML，复制或另存结果。输入顺序不必人工整理，不执行用户脚本，不改原文件。

三个入口：

| 入口 | 用户输入 | 结果 |
| --- | --- | --- |
| env.js 比较 | 两份含多个变量的本地 JavaScript 配置文本 | 按变量名称配对，显示变量及属性名称、A/B 类型和值、六类比较状态 |
| Vault 比较 | 两侧独立的 URL、Token、namespace、KV mount、目录范围与配置名称 | 预览匹配范围，只读取得整批配置，按对应目录比较 |
| YAML 格式化 | 一份本地 YAML | 保留内容的格式化预览，可复制或另存 |

文件内容不触发其中的 URL。env.js 与 YAML 功能离线；Vault 只有用户手动发起的非生产只读连接，没有自动登录、Token 创建/续期、自动更新、遥测、外部命令或自动 AI 上传。测试只用合成响应和明确的本机测试服务，不访问生产。开发依赖获取与用户要求的 CC/DS 源码评审不属于产品能力；不得把真实 Token/Secret 发给评审模型。

不新增生产巡检、监控、部署、数据库客户端、通用 HTTP 请求器、日志分析、证书/JWT/编码工具、Schema 工具箱、自动修复、同步、回滚、混合来源比较、多环境矩阵或三方合并。用户明确要求本地 MCP，确认开放全部三项功能，并同意 Vault 范围在 App 授权、Token 存本机钥匙串。

## 2. env.js 静态比较

### 根与作用域

env.js 输入允许带有常见的 YAML/ConfigMap 外壳，例如 `data` 下的 `env.js: |` block scalar。比较器只提取 `env.js` 的 literal block 后交给静态 JavaScript 解析；不执行 YAML、JavaScript，也不为了补齐不完整语法而猜测或自动修复。YAML 外壳中的其它字段不会进入比较结果。

App 和 MCP `env_compare` 默认一次比较两份文件中的所有顶层变量，按变量名称配对，`env`、`happy` 等同时进入同一批结果。界面“比较范围”默认“全部变量”，不要求逐个运行；显示 `env.x`、`env.y`、`happy.x`，保留所属变量以避免同名字段混淆。“刷新变量列表”从实际静态解析取得候选，保留已选的全部变量范围，完成后提示“变量列表已更新”；仍可分别选择对应的单一命名变量或最终 `module.exports`。MCP 的 rootA/rootB 默认 `*`，需要单变量时明确提供两侧根名。

例：`var env={y:2,x:3}; var happy={x:y};` 中，`y` 没有独立声明，`happy.x` 为 Unknown／无法比较，不会把它当成 `env.y` 或正常缺失；写成 `x:env.y` 才能静态确认值2。全变量模式仍保留已知 `env` 的结果及不完整诊断。 默认结果筛选只显示差异与无法比较；要同时看到相同的 `env.y`，把“状态”选为“全部”。[当前新包实际界面](evidence/2026-10-03-ipc-lifecycle-final-gui-proof.json)已核对两种筛选，以及 `env.y` 引用的已知值。

### 多变量与多层嵌套

一次比较须递归检查每个选中变量里的全部已知对象分支和数组元素，不能只比较第一层或第一个变量。全变量模式显示完整名称，例如 `env.api.retries.max`、`env.servers[0].tls.enabled`、`happy.options.cache.enabled`；不同变量中同名的属性分别比较。

- 对象按键名称配对，调整对象键或变量声明的顺序不产生差异；数组按下标配对，元素顺序有意义。
- 深层字段继续保留相同、值变化、类型变化、仅 A、仅 B、无法比较六类状态。父节点由对象变为字符串等不同类型时，在该父节点显示类型变化，详情查看两侧完整值，不额外制造子字段缺失。
- 属性名本身包含点号时使用方括号，例如 `happy.labels["a.b"].value`，与实际嵌套的 `happy.labels.a.b.value` 保持独立。
- 深层未知值显示无法比较，并标记整体结果不完整；其他变量和已知兄弟分支继续给出可靠结果。超出资源或深度限制时明确失败，不静默截断后宣称相同。
- 平面结果保留完整字段名称；“当前页树”可按变量、对象和数组逐层展开或折叠。树形显示只影响当前页展示，不改变比较计数、结果身份或报告。

上一轮冻结候选 `d776ce0a36c0547b89e07c37018bd44515aa176c4dd17fdb97aa017300a6022b`（133文件）的[13项本机检查](evidence/2026-10-03-nested-batch-final-results.json)通过，Rust95／Swift140／Python33，共268项测试。新增组合样本逐项核对15条路径及状态、交换A/B、多层树身份、MCP脱敏和深层Unknown；[最终新包11份AX/JPEG](evidence/2026-10-03-nested-batch-final-gui-proof.json)验证深层展开、数字/字符串详情、未知兄弟隔离，以及401行的三页对应关系、编辑后禁用分页/筛选、重新比较恢复。原始env/happy示例与中文深色平面结果已恢复。现有递归核心未改写，不执行用户JS、没有真实Vault或生产连接。

[CC与DS独立接受同一候选本增量](evidence/2026-10-03-nested-batch-final-review-synthesis.json)：CC复算8个范围源码哈希并阅读代码/AX，未重跑测试或实际GUI；DS仅文本审阅，实际返回deepseek-flash。当时CC推断的在途分页问题现已在下述62448候选独立复现并修复。完整目标、全量GUI/键盘/IME/VoiceOver/性能、目标设备、实际获准非生产部署、许可证及正式发行仍OPEN，见[本轮记录](superpowers/plans/2026-10-03-nested-batch-and-result-paging.md)。


上一轮页码/行事务与单实例修订：`62448daad11446a382951718ba37e497657c89a3da3f33f87218ae86157b4e53`（134文件）的[13项本机检查](evidence/2026-10-03-rows-transaction-final-results.json)全部通过，Rust95／Swift150／Python33，共278项测试；10项真实Workspace/Rust FFI回归、运行期红灯及两项定向变异证明在途分页、导出/变量刷新隔离、失败重试与迟到回复守卫。[最终新包8份AX/JPEG](evidence/2026-10-03-rows-transaction-final-gui-proof.json)验证正常分页、变量刷新、过期/重比、多变量嵌套和原输入恢复，不冒称GUI注入在途延迟。历史和重建前App均已通过原生菜单退出，[评审后进程检查](evidence/2026-10-03-rows-transaction-final-instances-after-review.json)只剩最新版PID16151。[CC与DS独立接受同一候选本增量](evidence/2026-10-03-rows-transaction-final-review-synthesis.json)；两者未重跑完整测试/GUI，完整目标保持active。

后续：CC N1在途页码/行错配已独立复现并修复。当时待修的N-A完整性/非原子提示及N-E迟到导出错误已由上述1.15修订补测并修复；快速翻页/详情交错、导入错误归属/共享超时、原N2/N3/N4仍待核验。完整91项、GUI/键盘/IME/VoiceOver/性能、包内worker运行中退出、干净目标设备、实际获准非生产部署、许可证及正式发行仍OPEN，见[本轮记录](superpowers/plans/2026-10-03-row-page-transaction.md)。

- 单根路径从 `$` 开始，不把变量名写入业务路径。
- 全部顶层变量按名称配对，普通命名变量即使共享对象，也各自按名称显示和计数。
- 全变量模式保留独立的 `module.exports` 与通过 `exports.PORT` 等写入的最终导出；显示如 `["module.exports"].PORT`。只在两侧导出都仅引用命名变量的同一对象、没有独立导出时去重，按堆对象身份判断，不能用值相等代替。任一侧导出独立时，两侧显式导出一起比较，避免“别名对独立对象”制造缺失。未使用的合成初始空导出不作为用户变量。
- 当前显式使用包括读取导出、写入后再删除。显式空导出对另一侧未使用的初始空导出，可显示为仅 A／B；这里比较文件的变量范围，不只比较 Node 最终导出值。`module.exports = env.s` 的嵌套对象若不是另一个顶层命名绑定，也作为独立导出参与计数；不会因值相等而去重。
- `module.exports = env` 捕获对象身份，之后 env 重绑定不改变旧导出对象。
- 普通属性赋值先捕获左侧引用，再处理右侧，禁止倒置 JS 求值顺序。
- 两侧全部变量/单根模式不能混搭；找不到根明确失败，不悄悄换比较范围。刷新后已选单变量消失时保留其选择并标注“未找到”，提示重新选择；直接比较返回 ROOT_NOT_FOUND。
- 静态求值实际到达的同一对象字面量中，普通属性重复定义时按源码顺序采用最后一次定义，并记录源码警告。Key 按解码后的 UTF-16 身份匹配；spread 的正常覆盖不单独算重复定义。警告可以包括非所选根的已求值对象，不扫描未执行分支或未知调用内部，包含 A/B、行号、UTF-8 字节列及上次定义位置，不包含原始键名或配置值，不改变结果计数或完整性。初次比较、根检查及界面最多接收前 200 项并说明总数；JSON 导出保留全部警告。MCP 使用独立 warningOffset 每次取得最多 200 项，不随差异筛选丢失；warningCount／hasMoreWarnings 明确总数和后续页。CSV 保持原有行列格式，响应只给警告数量，完整警告通过 JSON 查看。
- 字符串的花括号 Unicode 转义按 ECMAScript UTF-16 规则处理：BMP 范围可包含孤立 surrogate，补充平面转成代理对，超过 U+10FFFF 拒绝。行号统一识别 LF、CRLF、单 CR、U+2028、U+2029；列仍按原始 UTF-8 字节计算。
- 无论语法是否可解析，任何运行时表达式都不执行。

### 当前静态支持矩阵

| 语法 | 行为 |
| --- | --- |
| 字面量、普通对象/数组、变量、引用 | 保留类型和对象身份 |
| 对象键、字符串/数字计算键、shorthand | 按解码后的精确 Key 比较 |
| 已知普通对象展开、已知数组展开 | 静态求值；数组空槽展开遵循 undefined 语义 |
| 简单 `=`、属性赋值、delete、自变量重绑定 | 按语句顺序处理；const 重绑定报错 |
| 同类数值 `+ - * /`、字符串连接、已知 Boolean 条件（简单表达式语句，不接受嵌套声明） | 求确定的静态值 |
| process.env、外部标识符、调用、import、循环、未知控制流等 | Unknown 或不完整诊断，不能据此判 SAME/可靠缺失 |
| getter/setter、对象方法、原型修改、特殊全局重绑定 | 当前明确拒绝，不模拟访问器/原型运行时 |
| 未列出的复杂语义 | 未支持，保守失效，不宣称能解析任意 JS 的最终运行结果 |

支持矩阵是当前实现边界，新增语法必须有独立预期用例。仅解析成功不等于静态语义完整；未知影响对象身份时，不能保留旧的“已知”值冒充最终值。

## 3. Vault 直连与批量范围

### 3.1 两侧独立输入

A/B 默认各自填写 URL、遮罩 Token，再主动读取 namespace／KV mount／目录范围／配置名称下拉选项。界面不再要求手动勾选非生产；代码仍自动阻止可识别的生产标识。namespace 根、namespace 匹配、KV mount、目录根、目录匹配和配置名称的手动输入保留在折叠高级设置。所有字段可编辑；`FPMS-NT-V2`、`uat-swim` 仅为用户示例，不硬编码、不要求两侧同名。

支持拆解 Vault 网页链接。例如 `/ui/vault/secrets/<mount>/kv/auth%2Fuat-swim` 提取服务根地址、mount、`auth` 目录和 `uat-swim` 名称；拆解不联网。默认直连输入，导入已有 JSON 仅为可选方式。

### 3.1.1 链接与 Token 驱动的下拉选择（已实现，本地增量验证完成）

2026-10-04 用户要求已落实：输入 Vault 链接和 Token 后主动读取真实可见选项，不需先手填 mount 或配置名。独立的连接发现与名称发现均不读取 secret 值。详情、22 个文件变更、最终冻结源码、15 项完整本机检查及 CC／DS 同一候选接受见[专项交付记录](vault-dropdown-discovery.zh.md)；没有访问实际 Vault，不代表真实部署、正式分发或此前全部质量目标完成。

已实现交互：

1. A/B 各自只先显示「Vault 链接」「Token」和「读取选项」。链接解析不再强制 HTTPS，支持输入提供的服务根、`/ui`、`/ui/` 首页及现有 secret 网页链接；先在本机解析为固定 origin，网页链接提供的 mount／目录／配置名称作为选择提示，不执行网页内容。实际协议由底层连接能力决定。
2. 用户主动读取后，按顺序提供「Vault namespace」「KV mount」「目录范围」「配置名称」选择。先选目录范围，再根据范围过滤配置名称；选择「全部目录」时只显示所有已发现子目录都存在的共同名称。root 是明确的默认 namespace；部署支持且有权限时列出当前根内的子 namespace。未知生产标识仍由代码拒绝，不能从不透明 Token 猜测 namespace。
3. mount 选项只纳入服务器声明的 KV engine，再对实际选择定向核实 KV v1/v2。目录和配置名称从所选 KV 范围内的 LIST 结果去重得到，逐步加载，只读取路径和名称，不读取 secret 值。不得把固定示例 `FPMS-NT-V2`、`uat-swim` 当作真实选项。
4. 目录范围默认提供「全部目录（含子目录）」和具体目录；「全部目录」沿用现有 `**`，先求 auth、payment、promotion 等已发现子目录的名称交集，再让用户选择共同配置，一次比较这些目录下的全部匹配配置。A/B 的 mount、名称及 namespace 独立选择；一次每侧仍选择一个 mount，不在本需求中偷偷扩为跨 mount 比较。
5. 已有 namespace／目录通配符、目录根与手动路径输入保留在折叠的「高级设置」。Token 缺少 LIST 权限、部署不支持 namespace 或发现接口不兼容时，明确显示原因并提供手动输入；不得将失败冒充空清单、完整扫描或全部相同。获取了 mount 可见列表，也不意味着有权限读取其全部配置。
6. 两侧选好后仍先预览实际匹配清单，再读取并比较。链接／Token／namespace／mount／目录范围改变时清理对应下游选项与预览；取消和晚到响应不得覆盖新输入。不自动选第一个 mount，不静默扩大范围，也不随每次输入自动联网。MCP 继续只使用 App 主动授权的确切范围与清单。

实现涉及 `VaultModels.swift`（独立于完整比较目标的连接发现输入）、`VaultReader.swift`（受限只读发现）、`Workspace.swift`（逐侧加载／失效／取消）、`VaultConnectionPanel.swift` 和双语文案；比较算法不改。发现允许新增明确的 mount 可见列表 GET，namespace 与 KV 目录继续使用受限 LIST；只对确认的 KV 路径读取值，不开放其他 engine、通用请求或写入。

最终候选已实际完成 15 项完整本机检查，含 227 项 Swift 测试、95 项 Rust 测试、HTTP／TLS、签名包内 XPC 与 MCP；CC／DS 均接受同一冻结源码。新增测试覆盖首页／根／secret 链接、KV v1/v2、namespace 选择与拒绝列举、名称去重、全部目录批量配对、发现失败、非法／生产路径、预算、取消、两侧独立与晚到响应；既有完整故障矩阵未缩减。中英文原生布局检查为 1280×800、1440×900、1720×1000，12 张受控位图，非 OS 桌面截图。仅使用合成响应及自有 loopback；没有使用截图中的 URL／Token、打开用户 App 或抢焦点。

切换 namespace 会清除原选项并明确提示重新读取。带 namespace query 的 secret 链接必须与当前范围一致，否则联网前拒绝；高级设置拆解可采用该提示。名称提示只用于原链接对应 mount。重新读取配置名称遵循当前目录匹配，不静默扩大范围；恢复全目录列举时显式改为 `**`，共同名称只显示所有子目录都存在的项。

接口依据：[可见 mount 列举及定向识别](https://developer.hashicorp.com/vault/api-docs/system/internal-ui-mounts)、[namespace 列举](https://developer.hashicorp.com/vault/api-docs/system/namespaces)。mount 可见列表受 Token 能力和 listing_visibility 影响，内部接口不保证向后兼容，因此保留手动回退而不要求管理员权限。

### 3.2 namespace 与 secret 目录通配符

- namespace 根是实际 Vault `X-Vault-Namespace`，与 KV mount、secret 目录独立。`.` 选择当前 namespace；`*` 匹配一层、`**` 匹配任意层、`?` 匹配单字符。通配模式只列举已确认根下面的 namespace，不越级。
- 目录根是 mount 下相对路径；目录匹配 `**` 配合可编辑配置名称 `uat-swim`，等价于匹配 `**/uat-swim`，涵盖 `auth/uat-swim`、`common/uat-swim` 等。`.` 读取当前目录的一个指定配置，无需 LIST 权限。
- 两侧可以分别使用不同 URL、namespace 根、mount 和配置名称。按相对 namespace / 相对目录配对，忽略两侧不同的末级配置名称；字面目录与通配匹配使用同一相对目录键。需要配对不同的目录根时，各侧把该目录填入“目录根”，目录匹配填 `.`，按各自根下的同一个配置位置配对。
- 先预览两侧匹配清单，再点击“读取并比较”。预览只识别 mount 和列举路径，不读取配置值；预览超过 5 分钟需刷新，读取前再次识别 KV。

### 3.3 请求与生产边界

服务地址不再由入口强制 HTTPS；默认无连接，URL / namespace 根或匹配模式改变后必须重新读取。明显的 prod / production / prd 标识由代码拒绝。**URL 命名本身不是环境真实性证明**：用户仍必须使用已核实的非生产地址与 Token；共享 Vault 必须收窄到已核实的非生产 namespace 根。未提供真实测试地址/Token前，不宣称已验证用户部署。

网络白名单：确认来源内的可见 KV mount 列表 GET（`/v1/sys/internal/ui/mounts`）、namespace LIST（GET `?list=true`）、所选 mount 定向识别、已确认为 KV v1/v2 的目录 LIST 和 secret GET。使用 `X-Vault-Token`、`X-Vault-Namespace`、`X-Vault-Request`；不允许通用 URL 请求、动态 engine、写入、删除、续期或重定向，不绕过 TLS。Token 默认只在当前进程内存中，只有用户主动授权 MCP 才写本机钥匙串；不进入 Rust 比较请求、报告、日志或评审提示。

响应由 Rust 严格校验重复键后处理，配置数字和 UTF-16 不经过 Swift Double 重序列化。403、歧义404、TLS/超时、未确认 mount、超预算或任何一条读取失败均停止本批，不拿未读路径制造 ONLY/全部相同结论；可修改范围重试。完整确认 KV LIST 返回 `404 {"errors":[]}` 才作为该列举的空结果。多个读取不是原子快照；JSON 报告记录来源和开始/结束时间，不伪造全局快照。

初始网络预算：每侧每次预览/读取最多 500 请求、100 namespace / 8 层、1000 个配置与目录 / 16 层、总响应 20 MiB；单请求 30 秒、资源超时 60 秒。取消停止后续请求，晚到结果失效。

### 3.4 可选已有 JSON 输入

选择“已有 JSON”时，两个来源由用户主动选文件或粘贴。A、B 可以明确选择不同 KV 包装类型：

| 类型 | 显式提取范围 |
| --- | --- |
| `plain-object` | 整个配置对象；真实业务字段 `data.data` 不擅自剥离 |
| `kv-v1-response` | 顶层 `data` 对象 |
| `kv-v2-response` | 顶层 `data.data` 对象；metadata 不算业务差异 |
| `path-map` | 非空路径字符串 → 纯配置对象，按精确路径键对齐 |

本版路径映射采用明确选择的简单对象形式，例如：

```json
{"service-a/config":{"PORT":3000},"service-b/config":{"DEBUG":true}}
```

这取代历史稿未实现的 `scope/entries` 包装，不能自动猜测输入类型。空路径、非对象条目、null/删除响应、格式错误均拒绝；不会把 null 当作已确认不存在。未提供路径只表示本次输入没有该路径，**仅 A/仅 B 是导出内容差异，不能推断真实 Vault 中的 secret 存在性，也不代表扫描目录完整**。

JSON 重复 Key 按解码后 UTF-16 检测，包含包装和嵌套对象；重复则拒绝整个输入，保留原文并显示安全错误码/位置。大数与指数不先转换为 Double。JSON 根必须是对象。导入时间不冒充原 Vault 读取时间，未知版本、部署兼容性不生成虚构来源。

## 4. 比较契约

| 状态 | 含义 |
| --- | --- |
| SAME | 已知、可比较且类型和值一致 |
| VALUE_CHANGED | 类型相同、已知值不同 |
| TYPE_CHANGED | 已知类型不同，例如 Number 3000 与 String "3000" |
| ONLY_A / ONLY_B | 本次可靠输入范围内只有一侧提供该键 |
| NOT_COMPARABLE | 值、对象身份或缺失无法可靠确认 |

- 对象键忽略排列顺序；数组按索引比较，不排序。
- 缺失、null、undefined、数组空槽、空对象、空数组互不混淆。
- JS Number 使用 IEEE-754 / Object.is 比较语义；已知 NaN 相同、正负零不同；Infinity 与有限数不同。
- JSON 数字精确十进制比较：`1/1.0/1e0` 相同，正负零不同，大整数不丢失精度；超出预算明确报错。
- 字符串和 Key 保留 UTF-16 编码单元，包括孤立 surrogate，不做 Unicode 归一化或替换字符合并。
- 类型变化和单侧容器可作为一个终结结果项；空容器也是结果项。总计描述结果项，不假装等于 secret 数。
- 确认差异数只计值变化、类型变化、仅 A、仅 B；无法比较单独计数。
- 任一嵌套 Unknown、不完整键集合或未确认执行范围，都使整体结果不完整。不能因筛选隐藏 Unknown 就显示“全部相同”。
- 路径显示可读，报告另有区分对象 Key 编码单元与数组索引的机器路径。

## 5. YAML 格式化

使用 CST 排版器，独立事件解析器检查前后内容；不加载 YAML 为 JS 对象再序列化，不执行 tag，不展开 alias 图。

- 调整缩进、空白和换行，支持 2/4 空格；不排序键、不合并文档。
- 保留字符串引号、注释文本与顺序、anchor、alias、tag、标量内容/风格、多文档顺序。
- 重复 Key 和语法错误不输出覆盖后的结果。
- 当前只支持字符串 Key；数字/Boolean/集合/alias/tag Key 明确拒绝。
- 格式化后事件内容和注释必须与原输入一致，否则返回 YAML_SEMANTICS_CHANGED，阻止输出。
- 输入保持不变，结果只读；只有用户明确复制/导出才产生外部文件或剪贴板内容。

复杂 YAML 的实际兼容范围由样本验证，不宣称覆盖全部语言特性。资源过限不降级为有损输出。

## 6. macOS 使用流程

1. 左侧选择三项功能之一。
2. 选择本地文件、拖入文件，或主动粘贴内容。
3. env.js 必要时检查根；Vault 默认填写两侧连接及批量范围，预览后读取比较；可选已有 JSON 时明确选择包装类型。
   比较功能提供“交换 A/B”（`⇧⌘S`）：同时互换内容、文件标签、根和输入格式；Vault URL、Token 与范围成对交换，清除非生产确认及预览，要求重新核对，不自动连接，也不改变钥匙串中已经保存的 MCP 授权。运行或文件导入中禁用交换与执行；文件导入中也禁用根检查。修改根、格式或缩进保留正在读取的文件；手动编辑内容只作废同侧导入，停止/切换功能才作废两侧导入。YAML 单输入不提供交换。
4. `⌘ Return` 比较或格式化；`Esc` 或“停止当前操作”可停止计算或作废正在导入的文件，保留已编辑输入。只有文件导入正在进行时，停止还保留此前有效的比较会话、选择详情及 YAML 输出；切换工具仍清除旧结果。清除或更换结果选择立即作废旧详情回复，不依赖界面回调。实际键盘与UI验收另行留证。
5. 比较视图显示汇总、完整性诊断、状态筛选、区分大小写的路径/值搜索、共享 A/B 表和完整值详情。可切换平面或“当前页树”：按机器路径组织本页结果，分组不是新增差异；折叠不改变总计、完整性、匹配数或导出。容器的完整内容在只读详情树查看，单侧容器/类型变化的内部内容不重复计数。
env.js 结果的首列显示变量名称，标题为“变量”：`$.x` 显示 `x`，`$.auth.host` 显示 `auth.host`，数组显示 `items[0]`。平面列表、当前页树及详情使用一致的名称；包含点号、空键或特殊字符的属性保留方括号和转义，避免混淆。原始路径和 UTF-16 段继续用于内部定位、差异身份及报告；“复制变量”复制界面中的完整变量名称。根对象本身的结果显示选中的同名根，不显示合成 `$`；全变量模式显示本地化“全部变量”，两侧单根名不同时显示“比较根”。Vault 仍显示路径。

6. 列表只显示有截断标记的预览；详情与复制使用完整值。结果分页每页 200 项。
7. 导出完整或当前筛选范围，选择是否包含配置值。JSON 保存类型化树；CSV 对公式触发字符做安全转义。
8. 导出只创建新文件，拒绝覆盖输入、符号链接、硬链接或其他已有文件。写入、同步或关闭失败时明确提示新文件可能不完整；不按路径删除文件，以免删除其他操作替换后的文件。用户检查后另选新文件名重新导出。

输入、根、格式设置发生变化后，旧结果明确过期，禁止作为当前结果复制/导出。异步结果绑定 generation，旧响应不能覆盖新请求。取消时终止本地 worker，输入保留，结果会话释放，可重新运行。

文件读取只接受用户选择的普通本地文件，保留 UTF-8 BOM 和原换行；严格拒绝非法 UTF-8、超限、FIFO/设备/目录，并核对打开文件与路径在读取期间的身份、大小及修改时间。允许用户主动选择的文件符号链接，但导出仍禁止覆盖已有文件。

JS/JSON 解析位置对应保留 BOM 的原始输入，首行中文位置也计入原始 UTF-8 字节偏移；不能用删除 BOM 后的位置定位编辑器。YAML 格式化输出沿用移除前导 BOM 的行为，原输入仍保留。

原生语义颜色支持系统外观；输入编辑器关闭自动引号替换、拼写纠正、自动链接检测。禁用窗口内容恢复，不缓存明文输入，不自动读剪贴板、不自动读取最近文件。复制时提醒剪贴板生命周期；报告可能包含用户主动选择导出的敏感值。

### 6.1 双语、设置与个人资料（用户新增要求）

设置入口在主侧栏底部，提供 `⌘,` 快捷键。设置占据整个窗口，进入后隐藏 env.js、Vault、YAML 工具侧栏，左上角提供“← 返回工具”（也支持 Esc）；返回只关闭设置，保留原工具、输入和比较结果。设置期间工具层禁用并从无障碍树隐藏，原生编辑器不能接受文本或输入法标记输入。设置页采用“左侧分类、右侧选项”的布局，后续可以添加设置分类；不加入截图中的 CMS 页面管理功能。首批分类为通用、个人资料、外观，具体设计见[双语与设置设计](superpowers/specs/2026-10-03-settings-and-language.zh.md)。

| 分类 | 设置 | 行为 |
| --- | --- | --- |
| 通用 | 简体中文／English | 首次按系统首个受支持语言选择；没有受支持语言时使用 English。用户明确选择后保留，立即更新界面与已有受控提示/错误 |
| 个人资料 | 显示名称 | 仅在本机展示，无账号登录；最多 40 个完整字符，保留中文和 emoji，拒绝控制字符；空值显示本地化默认名称 |
| 本机个性化 | 内置图标 | 提供四款中性 SF Symbols 图标；仅在本机显示，无远程下载或上传，不代表账号 |
| 外观 | 主题 | 用户本轮明确要求统一奶油白浅色；旧 system/dark 偏好兼容读取后回落浅色 |
| 外观 | 强调色 | 蓝、绿、橙、紫、粉、灰 |

这 5 项显示偏好保存到本机 UserDefaults，另有一项本功能旧占位迁移的布尔标记；不保存配置内容或 Token。恢复默认只重置显示偏好，不触碰输入、结果、连接范围、Token 或钥匙串授权，也不重新启动旧占位迁移。打开/关闭设置、修改语言/主题/头像不能触发 Vault 请求，也不作废已有 session 或预览。切换到不同工具仍遵循原有清空规则。

当前主题通过 SwiftUI 浅色外观与 AppKit aqua 保持内容区、标题栏和原生控件统一。跟随系统/深色属于历史实现，不再作为当前选项。进入设置时已有的原生输入法组合结束标记，保留编辑器当前可见文本；返回时恢复有界选区。原生协议测试与实际 GUI 输入法验收分别记录。旧 John Doe 示例名称仅做一次占位迁移，不阻止用户随后明确填写自己的本机显示名称。

双语覆盖 App 自有菜单、按钮、标签、状态、提示、受控错误和辅助功能标签。配置原文、文件名、路径、精确数字、UTF-16、机器类型/状态码和 MCP 协议字段保持不变；翻译只针对明确的界面文案，不对任意配置字符串做替换。系统提供的原生菜单/文件对话框标准按钮依 macOS 自身语言显示。错误没有原始位置时不伪造行列；有位置时保留原 UTF-8 字节列。

## 7. 技术边界与资源

| 层 | 责任 |
| --- | --- |
| SwiftUI/AppKit App | 用户授权文件、非生产 Vault 类型化读取、generation、结果展示、复制、新文件导出 |
| CompareWorker.xpc | 独立本地计算进程；中断不会要求执行用户脚本 |
| Rust compare-core | Oxc 静态求值、精确 JSON 类型树、结构 Diff、查询、CST YAML、报告 |
| C ABI + JSON DTO | 明确 C header，Swift 真实往返测试；不传递文件权限或网络能力 |

App 和 worker 均启用 Sandbox。App 增加 network.client 以支持用户要求的 Vault 连接；worker 没有网络和用户文件访问权限，只接收输入字节在内存计算，不接收连接 Token、不记录输入/值/panic。没有网络服务端。第三方依赖锁定在 Cargo.lock，不属于最终用户运行时依赖。

预算：单侧 20 MiB、JSON/引用展开最多 100000 节点、静态值/语句深度 128、结果最多 100000 项、YAML 事件最多 200000、JSON 指数绝对值最多 10000、每次 XPC 请求 30 秒超时。Rust 每次计算使用 8 MiB 独立线程栈，OXC 使用 6 MiB 栈标记差额与 3000000 次游标操作预算；栈标记不是操作系统剩余栈测量。Debug/Release 对未求值语法的预算到达位置可能不同，但受支持的深度 128 静态值和合法宽配置必须保留。超限返回错误或终止本地计算，不静默截断真实值。预算不是已完成所有恶意输入压测的声明；仍需完整 App 的内存、超时与设备证据。

源码警告另有独立预算：每次根检查最多 100000 项、序列化警告数组最多 20 MiB；比较按 A/B 合计相同预算，在保存 session 前核对。超限返回 RESOURCE_LIMIT，不截断后伪装完整结果；这些预算只约束警告，不放宽其他节点或语义预算。初次响应与 MCP 警告页最多 200 项，全部位置保留在成功 session 的完整 JSON 报告中。警告预算不等于整个进程内存预算，完整 App 压测仍独立验收。

当前使用 C ABI 是实现选择；实际桥接编译/类型往返作为证据，不声称 UniFFI 已被证明不可用。SwiftUI 最低 API 部署目标设为 macOS 14，仅实际测试过的系统与架构写入支持证据。

## 8. 本地 MCP

### Vault 逐条读取来源（1.7）

直连模式从现有 secret GET 响应提取来源，不额外请求 metadata 接口：实际 namespace、secret 路径、相对配对键、已确认 KV engine 版本、服务器提供的 secret 版本及创建／删除／销毁信息、本机逐条请求与验证的开始／结束时间。只保留白名单来源字段；不转交 `custom_metadata`。KV v1 没有 secret 版本，缺少的 KV v2 字段也明确未知，JSON 使用 null；secret 版本使用精确十进制字符串，不经过 Double。

版本元数据不成为业务比较字段。两侧可分别为 KV v1 和 KV v2，并使用不同 Token、namespace、mount、配置名；业务值仍经 Rust 严格解析，保持大数与 UTF-16。来源信息在 App 的可展开记录和选中行详情中显示，完整来源随 JSON 报告及 MCP Vault 比较／分页输出；界面来源预览最多 200 条，完整 JSON 保留全部已完成记录。输入范围改变、取消或切换工具后旧来源清除；MCP 来源与结果 session 一起淘汰，授权撤销后禁止返回旧 Vault 分页。Token 从不进入这些 DTO。

`deletion_time` 也可能是未来的计划删除时间，不能把任意非空值当作已删除，不依赖本机时钟替服务器判断。可读业务对象仍继续比较并保留原始删除／计划删除时间；HTTP 状态明确传入 Rust；已知 KV v2 404 的删除／销毁元数据只从同一次响应按标准包装白名单严格解析，必须有显式 null 业务体、合法版本与销毁标志，直接返回错误并整批停止。无法确认的 404 仍报 HTTP 错误，不当缺失。依据：[官方计划删除说明](https://developer.hashicorp.com/vault/docs/commands/kv/metadata)、[官方读取实现](https://github.com/hashicorp/vault-plugin-secrets-kv/blob/main/path_data.go)。

成功读取不代表原子快照：不同 secret 读取之间可能变化，`snapshotAtomic=false` 始终保留，版本差异不算业务差异。已知删除／销毁或无效来源会停止整批，不输出相同／缺失结论；没有通过额外权限去猜测 403／404 的原因。离线导入不冒充直连来源，未取得的读取时间／版本不伪造。实际部署、读取中修改／回退以及失败来源完整 UI 矩阵继续单独验收。

**用户已确认：三项功能都开放；Vault 在 App 中确认两侧已核实的非生产范围并主动授权，Token 保存在本机钥匙串。MCP 只调用已授权范围，不接收或返回 Token。** 这项授权不开放生产访问，也不允许模型通过参数扩大 namespace、mount、目录或配置名称范围。

使用官方 Swift MCP SDK 0.12.1，stdio JSON-RPC，无 HTTP 监听端口。打包的同一 App 可通过 `Contents/MacOS/ConfigCompare --mcp` 作为本机子进程运行，无需 Node/Python/Vault CLI。App 提供“复制 MCP 配置”，不把 Token 放到连接配置中。

| 工具 | 输入和输出 |
| --- | --- |
| `env_compare` | 两份 JS 文本、根；静态比较，不执行，返回汇总、第一页差异和警告总数／第一页警告 |
| `yaml_format` | YAML 文本及缩进；返回格式化文本，不写文件 |
| `vault_preview` | 无连接参数；列举 App 已授权的 A/B 范围，返回 planId 和清单 |
| `vault_compare` | planId；取得同一授权范围的配置并比较，预览 5 分钟有效 |
| `comparison_rows` | 结果 session、offset、filter、可选 warningOffset；差异与警告分别每页最多 200 项，警告偏移与差异筛选独立 |

用户在 App 预览范围后，主动点击授权才保存两侧 URL/范围/Token 及逐条 namespace/path/KV版本清单到本机钥匙串。MCP 重新列举必须与授权清单一致；出现新增或变化项目时拒绝读取，要求回 App 重新预览授权。界面后续修改不会悄悄扩大这份授权；重新授权会令旧预览失效，可撤销并删除该凭证。MCP 不接收 URL、Token 或范围变更参数；每次 Vault 调用及返回前检查授权，撤销后旧 Vault 结果分页也拒绝。未授权时离线功能仍可用，Vault 明确报错。

比较结果默认 `includeValues=false`，返回路径、类型、状态及 Vault 来源信息；明确请求 `includeValues=true` 才向调用客户端交付配置值。YAML 格式化本身会返回原内容排版后的文本。**MCP 返回给 CC/Codex 的内容可能进入客户端模型上下文**，这与 GUI 默认本机处理不同；用户选择是否向客户端交付内容。没有 App 自动调用模型或上传功能。

Swift SDK 与传递依赖固定于 Package.resolved；原核心质量门槛继续有效。MCP 实际握手、工具调用、EOF 退出、参数约束、取消/权限失败及撤销检查记录在执行证据，不以 SDK 引入替代运行证据。

## 9. 验证和交付门槛

可以本机使用的三功能 App 是阶段成果。用户要求持续完成完整目标、前后端测试及同一候选双评审，不因成本或时间缩减标准；本机通过不能代替完整交付。逐项状态见[全量验收审计](quality-completion-audit.zh.md)，正式分发与未验证设备证据独立登记，不能伪造 PASS。

| 验证 | 必需证据 |
| --- | --- |
| 正确性 | 七项手工样本；乱序、类型、缺失、大数、特殊值、数组、对象身份、未知传播、重复 Key、UTF-16 回归 |
| YAML | 注释/引号/anchor/alias、多文档、标量风格、语法/重复键/语义变化阻止样本 |
| macOS 集成 | 真实 Swift/Rust 桥接、打包 XPC 进程往返；文件保护与 generation 用例；三入口实际 UI 操作 |
| 连接边界 | 文件/YAML 模式零联网，Vault 仅手动非生产 KV GET/LIST；最终包 entitlement、无重定向/写入/动态 engine/Token泄露；不用生产测试 |
| 资源与恢复 | 资源限制、worker 中断、超时/取消、输入保留、晚到响应失效；大输入压测单独留证 |
| 双评审 | CC、DS 各自读取同一冻结实现清单，反馈和修复分开登记；历史计划通过不等于实现通过 |
| 本机交付 | Release .app、包内链接/签名检查、实际打开；明确 ad-hoc 本机测试包的性质 |
| 正式分发 | Developer ID、hardened runtime、公证与 stapling、干净目标 Mac、所有承诺架构、VoiceOver 和性能矩阵 |

1.1 历史稿适用的语义/设备/分发用例仍是质量待办，不因为本轮测试数量增加就自动全部关闭。全量审计保留 11 项需求、6 个阶段、91 个最低用例及性能/页面状态/交付门槛；不得只选择当前通过的部分来定义完成。未测试的语法不扩充支持范围，未执行的 UI/设备/公证检查保留 OPEN。发布前需补全依赖许可证清单、目标系统实机矩阵与发行流程；本轮不自动发布、不推送、不提交。

## 10. 讨论与状态引用

- [最初 CC/DS 计划评审](evidence/2026-10-03-config-compare-plan-review.zh.md)：针对历史稿，不代表当前实现已验收。
- [离线 helper 功能讨论](evidence/2026-10-03-sre-offline-helper-discussion.zh.md)：额外建议未被选择。
- [本轮执行记录](offline-tools-execution.zh.md)：当前实现、验证、限制与实际评审状态。
- [全窗口设置同候选双评审](evidence/2026-10-03-settings-full-page-final-review-synthesis.json)：c937450f增量已通过12项本机门禁及中英文返回GUI样本；CC/DS独立接受，完整目标仍未验收。
- [主题、输入法标记与源码警告同候选双评审](evidence/2026-10-03-appearance-source-warnings-review-synthesis.json)：4465692c增量的12门禁及实际GUI样本通过，CC/DS独立接受；完整目标及警告资源预算、特殊转义、完整输入法/无障碍等仍继续验收。

最终以用户明确范围和实际证据为准。后续功能需要用户选择，不能自动扩充成 SRE 平台。

API 依据：[Vault HTTP API](https://developer.hashicorp.com/vault/api-docs)、[namespace LIST](https://developer.hashicorp.com/vault/api-docs/system/namespaces)、[定向 mount 识别](https://developer.hashicorp.com/vault/api-docs/system/internal-ui-mounts)、[KV v2](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2)、[官方 Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk)。namespace 需要对应部署支持；内部 mount 识别接口不保证向后兼容，失败时保守停止，不猜测 engine。

2026-10-03 · 1.6 最新实现核验：冻结候选 `e4fddad2b4a10da26b29c55645872fe5dda2a5b147f7272e70d45518c096a9dd`（123文件）的[12项本机门禁](evidence/2026-10-03-multiple-variables-commonjs-final-results.json)通过（Rust85/Swift104/Python16），[新包GUI](evidence/2026-10-03-multiple-variables-commonjs-final-gui-proof.json)验证独立导出、消失变量提示、中英文整页设置返回和原始三行批量结果；[包核验](evidence/2026-10-03-multiple-variables-commonjs-final-package-check.json)通过。[CC与DS已独立接受同一候选本增量](evidence/2026-10-03-multiple-variables-commonjs-final-review-synthesis.json)；完整目标、实际非生产部署、设备/正式发行/完整IME与VoiceOver/GUI性能仍OPEN，不能宣称全量100%。

2026-10-03 · 1.7 当前来源增量：冻结候选 `e84a5f23b1f8a9e7c1f765b23ccbc3168fac3567e5ec5d04715751aff087b64f`（127文件）的[12项本机门禁](evidence/2026-10-03-vault-provenance-final-results.json)通过（Rust93 / Swift114 / Python17，共224项），真实HTTP/TLS11例、Debug/Release可信Node对照、188资源探针、包内XPC/stdioMCP继续通过。[新包GUI](evidence/2026-10-03-vault-provenance-final-gui-proof.json)验证混合KV、四笔来源、KVv1未知、KVv2计划删除可读、右侧展开不挤压表格、中英文整页设置返回、完整JSON来源、已删除/销毁/未确认404整批失败及恢复；重预览/重读取不保留旧行来源，原用户三行多变量结果已恢复。[包核验](evidence/2026-10-03-vault-provenance-final-package-check.json)通过。[CC/DS同一新候选独立接受](evidence/2026-10-03-vault-provenance-final-review-synthesis.json)；只接受本增量，完整91项、读期间修改/回退、真实非生产部署、完整GUI/IME/VoiceOver/性能、目标设备与正式发行仍OPEN。没有真实Vault或生产访问。


## 历史验证增量：类型报告与 CSV（02cb144e4b85）

冻结候选 `02cb144e4b85356addced8006c0793520dd3a9ba1d92ce9bb49e916051483cc0`（129文件）的[13条完整本机门禁](evidence/2026-10-03-report-roundtrip-final-results.json)通过：Rust93、Swift117、Python21，共231项命名测试；原有独立 Node、188资源、真实HTTP/TLS11例、Release签名/XPC/stdioMCP继续通过。[包与解压核验](evidence/2026-10-03-report-roundtrip-final-package-check.json)通过。[CC与DS独立复核](evidence/2026-10-03-report-roundtrip-final-review-synthesis.json)接受同一候选的本次验证增量，完整目标保持 active。

[独立报告验证](evidence/2026-10-03-report-roundtrip-final-report-proof.json)在 Debug、Release 各核对9份JSON文件往返、9份CSV及546行；Python标准库独立解析/编码与固定合成类型预期交叉核对，覆盖ASCII和全角公式样式字符串、控制字符的转义、逗号/引号/Unicode、负数保护、完整/筛选/隐藏值报告。[Swift真实FFI与文件](evidence/2026-10-03-report-roundtrip-final-swift-http-tls-controller-tests.log)核对NaN、正负Infinity、正负零、BigInt、Undefined、Null、Hole、Unknown、Missing、孤立UTF-16、精确JSON大数/指数、长文本和240行全量报告。JSON以类型与UTF-16单元保存精确信息；CSV用于阅读，没有新增报告导入功能，也不执行任何literal。

失败记录保留：新增验证器前缺模块、手算摘要和诊断路径预期修正、冻结过程中修改脚本被正确拒绝，以及旧页面测试过早检查异步筛选行。页面等待修正后117项通过，再以最终源码完整重跑13门禁；产品代码未改。[原页面时序失败](evidence/2026-10-03-report-roundtrip-final-row-wait-red.log)和[修正后完整Swift通过](evidence/2026-10-03-report-roundtrip-final-row-wait-green.log)可核对。

本轮没有新的GUI/剪贴板实测，旧e84来源GUI仍是历史证据。实际长值复制与剪贴板恢复、完整JSON/CSV界面导出、电子表格保存再打开、VoiceOver/IME/性能、干净目标设备、真实已批准非生产Vault和正式签名发行继续OPEN；没有真实Vault或生产访问。

历史待办（本项已由下节d6f6e04ad3bd关闭）：当时results.json缺少总体passed、最终manifest与manifestStable字段，不能只凭13个命令exit0判断整轮成功。本候选有[最终driver成功标记](evidence/2026-10-03-report-roundtrip-final-current-full-gate-driver.log)、实际进程exit0及评审后独立源码/包核对；这不替代验证器自身的修复。另须专项覆盖Vault加入来源信息后的JSON重编码导出，Python标准库文件往返也不能冒充App的安全写入证明；边界与两位建议记录在综合记录中。


## 历史验证增量：整轮状态与真实界面导出（d6f6e04ad3bd）

冻结候选 `d6f6e04ad3bd45318fd0ceaa3ba738493dba6003f0429a61324270f788cc9ec5`（129文件）的[13条完整门禁](evidence/2026-10-03-verifier-status-final-results.json)全部通过：Rust93、Swift117、Python33，共243项命名测试；真实HTTP/TLS11例、可信Node Debug/Release、188资源、Release签名/XPC/stdioMCP继续通过。[新包与解压核验](evidence/2026-10-03-verifier-status-final-package-check.json)通过。[CC与DS独立接受](evidence/2026-10-03-verifier-status-final-review-synthesis.json)的是本轮增量，完整目标保持active。

关闭此前CC R1：验证开始即原子写入本次runID及passed=false/finished=false，成功需子命令全部通过、数量正确、最终源码冻结不变且结果落盘；文件记录finalManifestSHA256、manifestStable和脱敏failure，之后才输出成功标记。当前runID为 `7b8a247e-51ab-404b-87d0-7c58f1901149`，起止manifest均为本候选哈希。新增12个回归覆盖实际临时源码修改、exit7、初始/最终缺文件、旧passed记录，以及注入超时/中断/spawn/最终写入失败和命令数量变化。[初始红灯](evidence/2026-10-03-verifier-status-final-local-gate-evidence-red.log)、[扩展红灯](evidence/2026-10-03-verifier-status-final-local-gate-evidence-expanded-red.log)、[普通通过](evidence/2026-10-03-verifier-status-final-local-gate-evidence-all-green.log)与[-O通过](evidence/2026-10-03-verifier-status-final-local-gate-evidence-optimized-green.log)保留。只声明完整文件的原子替换，未证明断电/系统崩溃持久性。

[实际新包GUI](evidence/2026-10-03-verifier-status-final-gui-proof.json)留存12份截图/AX：重启后的空输入、中文与既有主题、长值截断预览/完整详情、真实NSSavePanel、仅A筛选及原始用户三行代码恢复。[六份实际保存文件](evidence/2026-10-03-verifier-status-final-gui-file-proof.json)由独立标准库核对：完整JSON/CSV各12行（含2项SAME）、隐藏值各12行、仅A各1行；原文件权限均0600，筛选保留id11与全局12项摘要。实际JSON保留长值UTF-16、孤立surrogate、NaN/Infinity/-0/BigInt/Hole/Undefined/Unknown/Missing；CSV引号/逗号/转义/CRLF与负数保护符合固定预期。[GUI文件验证脚本](evidence/2026-10-03-verifier-status-final-gui-files-validator.py)为本机证据脚本，不是App运行依赖。

CC独立重算当前源码清单和范围文件哈希，复跑33项普通/-O测试，并核对实际文件字节/权限、包哈希/签名、runID和最终状态；没有复跑13门禁或重演GUI，只读取GUI的AX证据。DS仅通过官方API读同一提示/源码/证据，没有本机工具或实际GUI执行。不能把DS文本审阅写成真实操作证明。

完整剪贴板复制/恢复尚未执行；本轮只使用保留剪贴板的输入粘贴，未点击复制按钮。Vault加入来源装饰后的JSON重编码、更多GUI/IME/VoiceOver/性能、真实worker恢复、干净目标设备、已批准的真实非生产Vault与正式发行仍OPEN。两位提出的逐run隔离历史旁侧日志、目录fsync及证据落盘失败时保留原诊断等非阻塞建议留在综合记录；不由局部接受宣称100%。没有真实Vault或生产访问，没有执行用户JS。


## 当前验证增量：Vault 来源报告完整导出（5c44e36be89f）

冻结候选 `5c44e36be89f4ff5111405dbe25a30b6f04382b2e6c19be2899a7360c3f088bd`（130文件）的[13条完整本机门禁](evidence/2026-10-03-vault-report-export-final-results.json)全部通过：Rust93、Swift123、Python33，共249项命名测试；Swift无警告，真实HTTP/TLS11例、可信Node双profile、188资源、Release签名/XPC/stdioMCP继续通过。[包与解压核验](evidence/2026-10-03-vault-report-export-final-package-check.json)通过。仅修改保存目的地依赖注入和新增六个导出测试；默认仍使用原生NSSavePanel，没有新增产品工具。

[完整导出专项](evidence/2026-10-03-vault-report-export-final-focused-proof.json)经真实Workspace.export、VaultReader合成GET响应、FFI、来源JSON重编码和安全新文件写入，验证246行全量报告（243相同、1值变化、1类型变化、1仅A）；保留9007199254740993、1e10000、-0、嵌套与孤立UTF-16、完整长值、两侧KVv1/v2来源、精确secret版本及计划删除时间。只有HTTP外部响应和目的地选择交互被替换。JSON白名单不包含Token/custom_metadata，隐藏值两侧只有三个基础字段；筛选与搜索独立验证且保留全局摘要。另测CSV、取消、选择目的地期间输入过期、已有文件拒绝覆盖，以及离线报告不附加之前的直连来源、不再读取Vault。所有测试仅写入各自临时目录。

[六项实际运行期变异](evidence/2026-10-03-vault-report-export-final-mutations.json)均被断言拒绝。首次“忽略状态筛选”仍通过，说明同时搜索long掩盖筛选失效；[初次存活记录](evidence/2026-10-03-vault-report-export-final-initial-mutations.json)保留，随后分开验证状态和搜索，两种错误均真实失败。缺少目的地参数的编译前置失败、测试作者语法错误和嵌套对象同形会递归成叶行的样例修正分别留档，不写成产品缺陷。

[新包真实GUI](evidence/2026-10-03-vault-report-export-final-gui-proof.json)保存4份AX/截图：空输入启动、默认NSSavePanel、实际文件保存、原始用户输入恢复。初次启动观察超时后重新读取同一运行PID成功，没有因观察超时重复启动。实际保存[多变量JSON](evidence/2026-10-03-vault-report-export-final-native-export.json)由标准库独立解析，包含env.x/env.y/happy.x三行，原文件权限0600。此GUI仅证明默认保存交互和env.js示例；不能冒充Vault直连完整GUI或剪贴板恢复。

[当前独立评审状态](evidence/2026-10-03-vault-report-export-final-review-synthesis.json)：DS接受本轮增量，实际模型deepseek-flash；它仅审阅所提供文本，没有本机工具或独立执行。CC原调用session `de27d8cf-da1e-406a-b6a0-54730460a256` 返回[API429额度限制](evidence/2026-10-03-vault-report-export-final-cc-cli.json)，提示2026-10-03 22:30（Asia/Kuala_Lumpur）恢复，exit1/timedOut=false，尚未评审。**双方接受仍未达成**，完整目标保持active，不继承旧候选的CC接受。DS将已通过的HTTP/TLS/Node/资源本机门禁写成待验、将初次筛选变异存活写成断言失败的措辞不采纳；真实日志为准。共享的合成授权helper未改变，继续复用，不复制凭证样例。

Vault来源装饰导出的本机控制器/文件样本已补齐；真实直连GUI全矩阵、完整剪贴板、键盘/IME/VoiceOver、性能/worker恢复、原91项、干净目标设备、已批准真实非生产部署和正式签名发行仍OPEN。没有真实Vault或生产访问，没有执行用户JS。


### 同候选追加实测：真实空闲 worker 异常退出与工具切换恢复

源码和包仍是 `5c44e36be89f4ff5111405dbe25a30b6f04382b2e6c19be2899a7360c3f088bd`，未增加或修改产品代码。[实际恢复证据](evidence/2026-10-03-worker-recovery-addendum-proof.json)保留9份AX/截图和5份只包含本次App进程的记录：核对精确自测worker PID16289及其包内可执行路径后，在活动监视器Force Quit；PID16289确实消失，主App PID13959保持运行。首次重试就创建新worker PID66594，并重新得到原始三项摘要（相同1、仅A1、无法比较1）；后续真实详情请求返回env.x的数字3和原始位置。

切到YAML后PID66594退出；新worker PID71680实际把 `x:  1` 格式化为 `x: 1`，保留注释和带双空格的引号字符串。再切回env.js后由PID75403重新比较，原始A/B输入、全部变量和三行列表已恢复。自测活动监视器已恢复搜索并退出，没有修改输入文件、真实Vault或Token。遗留的上一轮解压测试App只做已知样例的只读核对，未宣称系统只有一个Config Compare进程。

这只证明空闲worker被外部强制结束后的首次重试，以及正常工具切换停止/重建路径；运行中中断、30秒超时、运行期取消/迟到回复、压力和完整GUI仍OPEN。自动化返回时菜单未被Esc关闭，使用菜单实际暴露的AX Cancel后成功；活动监视器动态列表选择器失效时未对未确认PID执行退出，不归咎于产品。此前249项/13门禁及包哈希再次核对稳定；没有把这组追加GUI操作算作新的命名自动测试。

本组实测属于模型评审之后的追加证据，CC/DS未重演或评审此附录。DS对同一源码候选的已有局部接受不扩大为GUI全验收；CC仍因API429额度未完成新候选评审，完整目标保持active。


## 历史修订：NSXPC 取消恢复与多变量界面复验（3621fdd9c69a）

当前NSXPC修订：`3621fdd9c69a1d855737343d863ac9a8caa21acac683dacecf992abd9c539640`（131文件），[13项门禁](evidence/2026-10-03-ipc-lifecycle-final-results.json)全部通过（Rust93 / Swift132 / Python33，共258项）；真实NSXPC取消/中断/默认30秒及[当前新包多变量GUI](evidence/2026-10-03-ipc-lifecycle-final-gui-proof.json)样本通过。[DS接受、CC待额度恢复后评审](evidence/2026-10-03-ipc-lifecycle-final-review-synthesis.json)，双方接受未达成，完整目标仍active。

[专项证据](evidence/2026-10-03-ipc-lifecycle-final-focused-proof.json)区分真实运行期缺陷与测试准备错误：匿名端点加原协议、真实CoreBridge首次取消附着请求时signal5；[LLDB完整栈](evidence/2026-10-03-ipc-lifecycle-final-ipc-lifecycle-attached-crash-lldb.log)定位Foundation私有队列错误回调继承MainActor隔离。显式Sendable回调修复崩溃后，[同测试运行期红](evidence/2026-10-03-ipc-lifecycle-final-ipc-lifecycle-semantic-red.log)继续复现较早取消超过3秒仍未完成、停止仅把最后一笔标为CancellationError。现在按UUID跟踪所有回复，清连接状态后完成全部取消，再停止/失效；只把Sendable连接代号传到MainActor清理，迟到错误不影响替代连接。锁继续保证每个continuation最多恢复一次，已完成请求取消不停止新请求。

9项新增测试走真实Foundation NSXPC、实际原协议与C/Rust FFI，仅替换连接构造和服务回复时机。覆盖健康复用、启动前/附着取消、较早与较新请求、停止全部、中断及新连接、乱序回复、迟到回复和重试。默认30秒没有缩短或注入，本轮完整门禁实际30.007秒；超时请求得到timedOut，同连接其他请求取消。较早任务取消仅完成它的客户端回复，当前run/stop协议不能在保留较新计算的同时单独杀掉较早的服务计算；最新任务取消保持停止共享worker的原策略。[追加三次运输复跑](evidence/2026-10-03-ipc-lifecycle-final-repeat-proof.json)各8项通过，不增加命名测试数量。中断旧代码的首次YAML重试本来已成功，负向断言只有新连接工厂调用数量，不能声称旧首次重试功能失败。缺注入参数、跨队列捕获非Sendable连接的编译拒绝及打包后skip-build找不到测试bundle属于准备/作者错误，完整保留。

[包与解压核验](evidence/2026-10-03-ipc-lifecycle-final-package-check.json)及[评审后完整性](evidence/2026-10-03-ipc-lifecycle-final-post-review-integrity.json)确认源码/门禁/提示/包/ZIP一致。旧主App PID13959在重建前经原生菜单退出；新App PID83521及worker PID84944实际运行。[5份当前GUI记录](evidence/2026-10-03-ipc-lifecycle-final-gui-proof.json)验证一次比较env/happy：默认差异筛选显示env.x/happy.x，全部筛选显示env.x/env.y/happy.x；临时把未声明y改为env.y后happy.x显示数字2、结果完整，随后原A/B、全部变量范围和三行结果恢复。没有触碰剪贴板或真实Vault；旧解压历史App仍在运行，未假称只剩一个实例。

[独立评审](evidence/2026-10-03-ipc-lifecycle-final-review-synthesis.json)中DS接受本增量，没有本机执行能力；它关于墙钟的建议不采纳为事实，测试实际用ContinuousClock。原CC在5c44候选返回终态API429，提示2026-10-03 22:30（Asia/Kuala_Lumpur）恢复；本新候选尚未向CC发起调用，同一冻结提示已准备，不能把旧额度错误写成新的评审失败，也不继承历史接受。

匿名服务端位于测试进程；以上不能替代包内独立worker运行中被外部杀掉/真实GUI30秒与取消矩阵。历史GUI仅证明空闲worker Force Quit。原91用例、完整剪贴板/键盘/IME/VoiceOver/GUI性能、干净目标设备、明确批准的真实非生产Vault与正式签名发行继续OPEN；不访问生产、不执行用户JS，完整目标保持active。


## 当前修订：Vault 后段失败、恢复与旧结果标记（c48785522ad9）

当前Vault失败状态修订：`c48785522ad9ba82ae5f5f1d7581e78f2e21ce7886019ea46f9066e14963e735`（131文件）的[13项完整本机门禁](evidence/2026-10-03-vault-stale-results-final-results.json)通过：Rust93 / Swift134 / Python33，共260项命名测试。新增两项后段失败/重试回归与中英文“上一轮结果（已过期）”；[新包实际GUI](evidence/2026-10-03-vault-stale-results-final-gui-proof.json)留存29份AX、28份JPEG，验证失败、恢复、双语/深浅色和原始三行结果。[CC与DS独立接受本候选增量](evidence/2026-10-03-vault-stale-results-final-review-synthesis.json)；完整目标仍active，不能以局部接受标为100%。

[旧3621包的负向GUI](evidence/2026-10-03-vault-late-failures-addendum-proof.json)实际验证两侧各两条secret：最后一笔B读取403前已有三笔成功读取；后段B子目录LIST403前已有成功列举。两种失败都停止整批、禁用导出、清除所选详情/隐藏旧来源，重试恢复；56笔请求均为自建loopback合成GET。旧统计仍保留且变灰，但没有明确“上一轮结果”文字，违反原1.1的旧结果标记要求。该证据绑定旧候选，不覆盖为新候选成功记录。

产品修复仅在stale摘要上方增加中英文标记，继续保留旧统计与行、沿用交互/导出保护。后端策略没有改变。两项新增[批量失败回归](evidence/2026-10-03-vault-stale-results-final-vault-late-failures-focused-tests.log)经真实Rust校验，覆盖KVv1/v2中途secret403/404/503、后段子目录LIST403，禁止继续访问第三条及返回部分plan/capture；同reader/plan重试从头列举/读取，精确大整数保持。它们是既有规则的扩展测试，不虚构旧后端缺陷；不为一个可逆文字标记增加与实现镜像的字符串单元测试。

[完整门禁](evidence/2026-10-03-vault-stale-results-final-results.json)runID为`65122329-8100-48e7-9dfc-bccb1859a115`，起止清单稳定、13命令exit0，Swift零警告；真实HTTP/TLS11、可信Node双profile、188资源探针、Release签名/包内XPC/stdioMCP继续通过。[包与解压核验](evidence/2026-10-03-vault-stale-results-final-package-check.json)确认主App、worker、许可证和ZIP；当前只支持该本机实测，正式分发仍独立。

[新包GUI](evidence/2026-10-03-vault-stale-results-final-gui-proof.json)由主App PID87507和初始worker PID89235实际运行，旧主App PID83521重建前经原生菜单退出，历史解压App保留。再次以合成127.0.0.1双范围实际读取：中文/英文后段403及子目录403均明确显示上一轮结果，旧详情/来源隐藏、导出禁用；重预览仍过期，新比较成功后移除标记、恢复来源与导出。英文深浅色及整窗口设置/返回已核对；每阶段精确8笔预览/6笔读取和失败顺序由脚本独立验证，语言/主题切换没有额外请求。29份AX含一份菜单无截图，28份截图的原始字节为JPEG，扩展名已据实更正，未改图像内容。

自建服务已关闭、端口关闭，临时URL/namespace/mount/name、Token和确认勾选已实际清空；中文/深色/紫色及既有John Doe恢复，原A/B文本、全部变量与env.x/env.y/happy.x三行最终恢复，没有触碰剪贴板、MCP授权/撤销、真实Vault或生产，也没有执行用户JS。

[独立评审](evidence/2026-10-03-vault-stale-results-final-review-synthesis.json)已向DS发送当前228668字符冻结范围提示（8个完整范围源码、两个UI片段、8份关键AX及清单/本机证据），包含此前尚待CC的IPC与Vault导出修订。DS接受，无阻塞，实际返回模型deepseek-flash，仅文本审查没有本机执行。其建议增加标记字符串镜像测试/独立AX身份保留为非阻塞建议；所谓语言/主题零请求没有机器检查不符合当前check-gui.py对56请求和每阶段计数/状态的实际断言。完整VoiceOver和网络UI全矩阵仍OPEN。CC在22:30后实际审查同一c487候选及同一冻结提示，session `997a3d86-5a7d-4b7d-8eb7-c00d99b7f76a` 返回[exit0/timedOut=false的本轮接受](evidence/2026-10-03-vault-stale-results-final-cc-cli.json)。它独立重算8个范围源码哈希并读代码/AX/日志，没有重跑Swift或完整13门禁，没有重算全部131项或重演GUI。双方无阻塞、各四项非阻塞意见；不继承历史接受，也不宣称完整目标通过。

原91项完整验收、包内独立worker运行中退出、全剪贴板/键盘/IME/VoiceOver/GUI性能、干净目标设备、明确批准的真实非生产部署和正式签名发行继续OPEN。参见[本轮执行计划](superpowers/plans/2026-10-03-vault-stale-results.md)。


CC另指出过期多页结果的分页/筛选仍可操作：页面先增加page，但loadRows因stale提前返回，页码可能与旧行不一致；单页GUI没有覆盖该场景。此STALE-PAGER-FILTER-01虽不阻塞文字标记增量，仍是下一项需要实测与修复的缺陷。完整目标继续active。

# Config Compare 实现任务与实测

> **2026-10-04 N4 已关闭：**候选 e503684dc4c354c2b0c96bcd493e1a60ad187cb9fc1d41cbb617059a5d833154 的 Unicode 路径／分组一致性通过 15/15 正式门禁、237/30 Swift 全量测试、包核验及同 SHA CC／DS 双接受；realVaultAccessed=false。记录见[N4 修订](unicode-groups-quality.zh.md)。

> **最新导入生命周期 N2 修订（2026-10-04）：**主源码候选 `d73132e2c1b6512054cfd99fc8015f82368eb368eb8f1852d254c6a04de8ec00`（331 文件）已合入。导入取消后的迟到成功／失败改为等待真实 import Task 的 MainActor 完成通知，10/10 导入专项、15/15 正式门禁和主工作区 236/30 全量 Swift 通过；成功 token guard 突变按预期让4项测试失败后已恢复。CC／DS 同 SHA 均 `ACCEPT_LOCAL_CHANGE`。不访问生产 Vault；完整目标、N4 与真实 GUI／设备／发行仍 active。详见[导入生命周期修订](import-lifecycle-quality.zh.md)。

> **最新行请求去重增量（2026-10-04）：**主源码候选 `8d0a33f5bf778c5941c545b04177d740e24d058e0ea74c5177403b553af5566a`（331 文件）已合入。相同 rows 请求只保留一个在途任务，失败／取消／旧 session guard 和真实结果提交保持；正式 15/15 门禁与主工作区 `swift test --no-parallel` 的 236/30 通过；CC／DS 同 SHA 均 `ACCEPT_LOCAL_CHANGE`。完整产品目标仍 active，真实 Vault I/O 与正式发行未宣称。详见[行请求去重修订](rows-dedup-quality.zh.md)。

> **最新单实例修订（2026-10-04）：**主源码候选 `e20e0d03…`（331 文件）已合入。正式 GUI bundle 使用用户级非阻塞锁，重复启动只向已完成启动的旧实例交接；`--mcp`、`--self-test`、图标模式、XPC worker 和无 bundle ID 的测试宿主不启用。15/15 本机门禁、Swift 235 tests／30 suites、同 SHA 的 CC／DS `ACCEPT_LOCAL_CHANGE` 已记录；真实双击、窗口激活、完整设备／发行门槛仍未验证。详见[单实例修订记录](single-instance-quality.zh.md)。

> 上一轮主源码 `56b6d94b…`（329 文件）：[代码显示／行号裁剪修复](editor-ruler-visibility.zh.md)已通过 15 项完整本机门槛、Rust 95／Swift 229 项测试、新包 10 项核验及同候选 CC／DS 独立增量接受；Vault 链接＋Token 下拉发现与批量比较保留。代码文字在整页原生图像中恢复，实际桌面／输入法／设备／完整性能／正式发行和原 91 项仍未全部验收。没有启动、关闭、切换用户 App 或改变其输入。

> 下文旧版本的“当前”哈希、运行窗口、深浅色和计数均只对应各自历史记录；本轮没有重新核对用户窗口 PID，不继承旧版接受为完整目标通过。

> 2026-10-04 最新行号修订候选 `2f080310…`（140 文件）：[13 门禁／317 测试及新包核验](gutter-quality.zh.md)已通过，同候选 CC／DS 独立接受与评审后完整性核验均通过。以下为各历史增量证据。当前运行窗口仍为白鹅视觉基础版 `8df029ff…`；[20 MiB 完整挂载实验](editor-performance-investigation.zh.md)未达性能预算，实验代码未进入新包。完整原 91 项、实际桌面／输入法／设备／正式发行仍开放。

> **最新编辑器源码修订：**`20bc16ef…`（139 文件）的 13 门禁／314 测试、Release 原生专项与同候选 CC／DS 独立接受均通过；[源码、边界探针、性能与包记录](editor-quality.zh.md)完整登记。新测试包为 `build/Config Compare Editor Quality v2.zip`，当前运行窗口仍为以下 `8df029ff…` 白鹅视觉基础版，未退出、替换或另开。实际桌面、完整性能、设备与正式发行仍 OPEN，不能用源码增量接受替代原全量目标。

> **当前视觉修订：**原生 SwiftUI/AppKit 的奶油白、草莓粉和中性 SF Symbols 已落实到 env.js、Vault、YAML 和全窗口设置。当前图标来自用户提供的本地 PNG；动物插画与冬日主题已移除。桌面工具异常和 TextKit 截图限制明确保留；完整门禁/评审/包证据以当前构建与测试输出为准。

> 当前提示/错误归属修订：`db0c3726fb20270ce7fa946b1a98c5d5e3a05a188aa0ca814ff43589cae82771`（135文件）的[隔离源码13门禁](evidence/2026-10-03-notice-ownership-final-results.json)全部通过，Rust95／Swift164／Python33，共292项测试。新增6项回归，旧85ea源码的5项测试中4项运行期失败/5条断言；复制先区分API编译红，再在仅迁移原生依赖参数的旧行为上复现2条运行期断言。统一publishNotice同步提示、错误标记及行错误归属，修复导出/复制后旧错误残留、重试覆盖新提示、非文件导入拒绝被擦除，以及停止/编辑后的错误图标。[40项专项](evidence/2026-10-03-notice-ownership-final-runtime-green.log)与[同候选CC/DS独立接受](evidence/2026-10-03-notice-ownership-final-review-synthesis.json)均通过；完整目标保持active。

> [隔离验证与测试包](evidence/2026-10-03-notice-ownership-final-focused-proof.json)：135文件源码清单与原工作区逐字节一致，Rust缓存共享，Swift构建/App输出独立；包内XPC/stdioMCP、ZIP全新解压及深度严格签名通过。[评审后完整性](evidence/2026-10-03-notice-ownership-final-post-review-integrity.json)核对原App文件未改，只剩原来的85ea窗口，没有退出、启动新GUI或更改用户输入。**当前运行窗口仍为85ea；新测试包尚未切换到当前窗口，本次没有新候选GUI证据。**复制测试只使用NSPasteboard.withUniqueName自己的命名板，不读取/写入系统general剪贴板，不代替真实GUI复制/恢复矩阵。

> 评审边界：CC实际核对3个范围源码哈希及搜索，摘要3项缩写尾码不准确，以原会话工具输出为准；DS仅文本阅读，实际模型deepseek-flash。DS关于后来错误仍会被重试覆盖的推断与publishNotice清除归属、现有根错误和新增导入拒绝回归相矛盾，不当作已证缺陷。CC建议收紧error为private(set)，初次解析失败后的编辑提示等仍需契约核验。原N-B快速分页/加载、N-D共享超时、详情交错、N2/N3/N4和完整91项/GUI/键盘/IME/VoiceOver/性能、包内worker运行中退出、干净设备、明确获准真实非生产、许可证与正式发行仍OPEN。

> 历史翻页提示/导出迟到回复修订：`85ea5571fa633635e0a29eaac2eb73bf0474a46889ab6ba67d9e51a31343c876`（135文件）的[13项本机检查](evidence/2026-10-03-result-notice-export-final-results.json)通过，Rust95／Swift158／Python33，共286项测试。8项新回归在旧源码复现6个命名失败/8项断言，修复后与10项分页回归共18项绿。翻页错误重试恢复该次比较的不完整或Vault非原子说明；停止、编辑、新比较和新导出后的旧报告失败不能覆盖当前状态，当前有效失败仍显示。[CC/DS独立接受同一候选本增量](evidence/2026-10-03-result-notice-export-final-review-synthesis.json)，[评审后清单/提示/包核验](evidence/2026-10-03-result-notice-export-final-post-review-integrity.json)稳定。CC仅实际复算5文件哈希及搜索，DS仅文本审阅，两者未重跑完整测试/GUI。

> [新包5份实际AX/JPEG](evidence/2026-10-03-result-notice-export-final-gui-proof.json)核对402项不完整结果/第二页、中英文与全窗口设置返回。恢复原env/happy后观察到用户新编辑，保留其最新输入并停止UI修改，最终结果自然过期；不强制重新运行或覆盖内容。只剩一个最新版主进程，未注入GUI行错误或在途竞态。

> 后续：上轮CC指出的提示归属残留已由当前1.16补测并修复。原N-B快速翻页/加载、N-C导入边界、N-D共享超时、详情选择交错、N2/N3/N4，以及完整91项/GUI/键盘/IME/VoiceOver/性能、包内worker运行中退出、干净目标设备、实际获准非生产部署、许可证与正式发行仍OPEN；完整目标保持active。

> 历史页码/行事务与单实例修订：`62448daad11446a382951718ba37e497657c89a3da3f33f87218ae86157b4e53`（134文件）的[13项本机检查](evidence/2026-10-03-rows-transaction-final-results.json)全部通过，Rust95／Swift150／Python33，共278项测试；10项真实Workspace/Rust FFI回归、运行期红灯及两项定向变异证明在途分页、导出/变量刷新隔离、失败重试与迟到回复守卫。[最终新包8份AX/JPEG](evidence/2026-10-03-rows-transaction-final-gui-proof.json)验证正常分页、变量刷新、过期/重比、多变量嵌套和原输入恢复，不冒称GUI注入在途延迟。历史和重建前App均已通过原生菜单退出，[评审后进程检查](evidence/2026-10-03-rows-transaction-final-instances-after-review.json)只剩最新版PID16151。[CC与DS独立接受同一候选本增量](evidence/2026-10-03-rows-transaction-final-review-synthesis.json)；两者未重跑完整测试/GUI，完整目标保持active。

> 后续：CC N1在途页码/行错配已独立复现并修复。当时待修的N-A完整性/非原子提示及N-E迟到导出错误已由当前1.15修订补测并修复；快速翻页/详情交错、导入错误归属/共享超时、原N2/N3/N4仍待核验。完整91项、GUI/键盘/IME/VoiceOver/性能、包内worker运行中退出、干净目标设备、实际获准非生产部署、许可证及正式发行仍OPEN，见[本轮记录](superpowers/plans/2026-10-03-row-page-transaction.md)。

> 历史多变量深层比较与分页修订：`d776ce0a36c0547b89e07c37018bd44515aa176c4dd17fdb97aa017300a6022b`（133文件）的[13项本机检查](evidence/2026-10-03-nested-batch-final-results.json)全部通过，Rust95／Swift140／Python33，共268项测试；现有递归核心新增15路径组合、交换A/B、深层Unknown、App树/详情与MCP脱敏核验。分页在过期/忙碌/导入状态先拒绝改变页码和行请求。[最终新包11份AX/JPEG](evidence/2026-10-03-nested-batch-final-gui-proof.json)通过三页对应关系、过期禁用/恢复、多变量深层展开、类型详情及原始输入恢复。[CC与DS独立接受同一候选本增量](evidence/2026-10-03-nested-batch-final-review-synthesis.json)，没有阻塞；CC核对8个范围源码哈希及代码/AX，未重跑测试或GUI，DS仅文本审阅。完整目标保持active。

> 历史Vault失败状态修订：`c48785522ad9ba82ae5f5f1d7581e78f2e21ce7886019ea46f9066e14963e735`（131文件）的[13项完整本机门禁](evidence/2026-10-03-vault-stale-results-final-results.json)通过：Rust93 / Swift134 / Python33，共260项命名测试。新增两项后段失败/重试回归与中英文“上一轮结果（已过期）”；[新包实际GUI](evidence/2026-10-03-vault-stale-results-final-gui-proof.json)留存29份AX、28份JPEG，验证失败、恢复、双语/深浅色和原始三行结果。[CC与DS独立接受本候选增量](evidence/2026-10-03-vault-stale-results-final-review-synthesis.json)；完整目标仍active，不能以局部接受标为100%。

> 完整目标仍 active。当前范围以用户最新确认及计划 1.16 为准：env.js 比较、URL + Token 直连非生产 Vault 批量比较、YAML 格式化，以及这三项能力的本机 stdio MCP。用户新增双语、设置、显示名称、内置头像、主题与强调色。禁止连接生产，不写回 Vault。

> 历史NSXPC修订：`3621fdd9c69a1d855737343d863ac9a8caa21acac683dacecf992abd9c539640`（131文件），[13项门禁](evidence/2026-10-03-ipc-lifecycle-final-results.json)全部通过（Rust93 / Swift132 / Python33，共258项）；真实NSXPC取消/中断/默认30秒及[当前新包多变量GUI](evidence/2026-10-03-ipc-lifecycle-final-gui-proof.json)样本通过。[DS接受、CC待额度恢复后评审](evidence/2026-10-03-ipc-lifecycle-final-review-synthesis.json)，双方接受未达成，完整目标仍active。

## 已有实现：一次比较多个变量

最新修订保留独立CommonJS导出，按堆身份判定命名对象别名，并对两侧使用一致策略，避免别名对独立对象制造假缺失；刷新丢失的单变量保留原选择并明确报错。Rust4契约和App/MCP3实际核心回归已补；初次Rust3红及Swift3共14失败保留。最终冻结候选 `e4fddad2b4a10da26b29c55645872fe5dda2a5b147f7272e70d45518c096a9dd`（123文件）的[12门禁](evidence/2026-10-03-multiple-variables-commonjs-final-results.json)通过：Rust85、Swift104（10套）、Python16及原有全部离线Node、188资源、HTTP/TLS、签名/XPC/MCP。[包核验](evidence/2026-10-03-multiple-variables-commonjs-final-package-check.json)通过；[实际新包GUI](evidence/2026-10-03-multiple-variables-commonjs-final-gui-proof.json)验证导出PORT值变化、消失env中英文未找到与ROOT_NOT_FOUND、全窗口设置顶部返回，以及恢复用户原代码后的三行批量结果。[CC和DS](evidence/2026-10-03-multiple-variables-commonjs-final-review-synthesis.json)均独立接受本候选本增量。CC独立核对123/123源码/提示/包哈希，并重跑12个Rust契约及19个实际包内MCP合成探针；DS仅通过API阅读范围源码/证据，未本机重跑。两者无阻塞，不继承旧接受，完整目标保持active。

App 和 MCP env_compare 默认两侧比较范围为全部变量，按名称配对，env/happy 同一次进入结果，显示 env.x、env.y、happy.x；仍可明确选择两侧单变量。未知 y 不冒充 env.y，保持无法比较。主计划1.6已更新。前次默认全变量候选 `ab5258b3a2f267e46d43f0d1beef8276f5087105ad1b48e4e4db689085836f3e`（123文件）的[12项门禁](evidence/2026-10-03-multiple-variables-final-results.json)全部通过：Rust81、Swift101（10套）、Python16及既有Node Debug/Release各1408对、188资源探针、HTTP/TLS、签名/XPC/MCP。[包核验](evidence/2026-10-03-multiple-variables-final-package-check.json)与[实际GUI](evidence/2026-10-03-multiple-variables-final-gui-proof.json)证明新包默认全部变量、同批三行、中英文整窗设置顶部返回及原输入/结果保留。该ab5258候选独立评审为CC NEEDS_CHANGES、DS接受：CC实际发现批量模式漏独立CommonJS导出。正在修订并补自己的全部检查与双评审，不继承DS单方接受。刷新变量列表保持全变量模式，并提示列表已更新。

## 历史：变量名称显示与警告资源限制

用户最新要求 env.js 的结果直接显示变量：`$.x` → `x`，`$.auth.host` → `auth.host`；首列改为“变量”。平面列表、树、详情和值子树一致，“复制变量”复制完整显示名称，保留特殊键的引号/转义以及数组索引；机器路径、结果身份和报告保持完整。主计划已更新。

当前候选 `0fac189ea3a1a18a3524ea575c946163a0a02b2d63a4d49249ac8ba233babd09`（123文件）已通过[12项门禁](evidence/2026-10-03-variable-labels-results.json)：Rust81、Swift99（10套）、Python16及既有Node/188资源/HTTP/TLS/XPC/MCP。[专项红绿证据](evidence/2026-10-03-variable-labels-focused-proof.json)与[实际GUI](evidence/2026-10-03-variable-labels-gui-proof.json)分别证明名称/身份/报告及真实列表x、树x、详情x、整页设置Esc返回和原输入保留。CC/DS已独立接受该变量显示候选本增量，见[综合记录](evidence/2026-10-03-variable-labels-review-synthesis.json)。用户随后要求一次比较多个变量，当前默认模式修订另取自己的门禁及双评审，不能继承接受。

[包核验](evidence/2026-10-03-variable-labels-package-check.json)先发现ZIP旧于App，重新生成后全新目录解压、二进制/许可证字节匹配与深度严格签名通过。[截图代码的静态实测](evidence/2026-10-03-variable-labels-why-probe.json)确认比较根env只有x/y两项，独立y未声明导致全局完整性false；改env.y后完整性true，原两行与计数不变。这是说明现有语义，没有执行用户JS或连接真实Vault。

此前警告修订冻结为 `7aa5638204dee53c4735f316b62e61a2f723e774515df5fddc1f563b1f894b07`（123文件），[12项完整门禁](evidence/2026-10-03-warning-budget-unicode-results.json)全部通过：Rust79、Swift98（10套）、Python16；可信Node Debug/Release各1408对、4957行，188项资源探针和包内XPC/MCP。[独立评审](evidence/2026-10-03-warning-budget-unicode-review-synthesis.json)为CC接受、DS要求补防护和永久回归，因此不能写成双接受。当前候选已补私有解码闭合/ASCII十六进制防护、单侧警告超限和side标注后真实20MiB溢出的永久测试。

警告新增100000项／20MiB序列化字节预算，超限整次失败，不返回部分正常结果；初始响应最多200项并包含总数，MCP使用独立warningOffset分页，JSON完整报告仍保留预算内全部警告。花括号孤立UTF-16代理项和全部五种JS行终止符已修复，[专项证据](evidence/2026-10-03-warning-budget-unicode-focused-proof.json)区分编译红、实际运行红与绿；[实际GUI](evidence/2026-10-03-warning-budget-unicode-gui-proof.json)验证位置、旧警告过期、100001项受控失败和401项恢复。保存菜单两次被交互工具拒绝后停止，该候选完整JSON保存界面仍未通过。没有连接真实Vault或生产。

## 历史：全窗口设置、系统主题回退与源码警告

当前冻结候选 `4465692c1ddb15cccc2fc655b6f99eaa7847374655d718cc94ba9a2737480d57`（120文件）的[12项门禁](evidence/2026-10-03-appearance-source-warnings-results.json)全部通过：Rust74、Swift96（10套）、Python16及原有HTTP/TLS、可信Node、188资源探针、打包签名/XPC/MCP。修复Dark→System内容残留深色及进入设置前已有marked text状态；[专项红绿记录](evidence/2026-10-03-appearance-source-warnings-focused-proof.json)区分测试作者编译错误与实际功能红。J07已实现安全位置警告、最后定义取值、中英文有界展示及完整JSON报告，不改变计数、完整性或MCP默认值保护。

[新包](evidence/2026-10-03-appearance-source-warnings-package-check.json)与[实际GUI](evidence/2026-10-03-appearance-source-warnings-gui-proof.json)验证整页设置、按钮/Esc返回、中英文警告与主题回退，PID12236；已恢复中文/深色偏好。[301警告GUI](evidence/2026-10-03-appearance-source-warnings-overflow-gui-proof.json)也已验证前200项及完整报告提示。CC/DS已[独立接受同一冻结候选](evidence/2026-10-03-appearance-source-warnings-review-synthesis.json)，原始目标未完成；普通12门禁不调用读取Vault凭证的工具，打包Vault授权/撤销完整链路仍需单独验证。

## 历史：全窗口设置、双语、个人资料与外观（c937）

用户最新明确要求设置占据整个窗口，左上角有返回按钮。设置打开后工具侧栏隐藏，只保留通用／个人资料／外观分类；主侧栏入口与 `⌘,` 可进入，返回按钮与 Esc 只关闭设置。工具视图保活，原工具、输入、比较结果和编辑器选区保留。双语、8个内置头像、本机显示名称、系统／浅色／深色与6个强调色均已实现，只有5项显示偏好保存本机。[设计与契约](superpowers/specs/2026-10-03-settings-and-language.zh.md)及主计划1.4已同步。

当前冻结修订候选 `c937450f7e2e256217bfb22c7c2ff99fadf2c14849af45ad728e1e60fb5ecba2`（117文件）的[12项完整本机门禁](evidence/2026-10-03-settings-full-page-final-results.json)全部通过：Rust70、Swift91（9套）、Python16；HTTP/TLS9、Node Debug/Release各1152对、188项资源探针、签名包内XPC与stdio MCP。[12项设置专项](evidence/2026-10-03-settings-full-page-native-proof.json)已绿：10项偏好/状态测试加2项实际原生文本输入测试。隐藏编辑器不可编辑、选择、接受firstResponder或插入文本／标记文本；返回恢复有界选区，可见只读输出仍可选择。测试直接走NSTextInputClient方法，不冒称真实GUI输入法或VoiceOver验收。首次用了错误开发工具链缺Testing模块，随后正确工具链缺新API为编译红，二者与最终12项绿分开归档。

此前7b26211b双侧栏候选已有12门禁、GUI样本与CC/DS接受，但用户随后要求全窗口，不能继承。首份全窗口2a6751c5有原生标签残留，保留实际AX红并修复。82689fe0已有[12门禁](evidence/2026-10-03-settings-full-page-8268-results.json)、[包](evidence/2026-10-03-settings-full-page-8268-package-check.json)、[实际英文GUI](evidence/2026-10-03-settings-full-page-8268-gui-proof.json)；[CC](evidence/2026-10-03-settings-full-page-first-cc.json)接受并列P2多窗口焦点风险，[DS](evidence/2026-10-03-settings-full-page-first-ds-deepseek.log)要求显式输入禁用及独立关闭设置。两者共同提示隐藏键盘焦点保护；源码已补禁用整个工具层和原生协议、全部App窗口撤焦点、closeSettings独立关闭。Esc现只返回，设置期间Stop菜单禁用。

[新候选包与ZIP](evidence/2026-10-03-settings-full-page-final-package-check.json)解压字节与深度严格签名核验通过；[新候选GUI](evidence/2026-10-03-settings-full-page-final-gui-proof.json)实际启动PID21896，验证英语与中文全窗口设置、Esc及左上角按钮返回、原文total5/diff3保留，最终停在中文通用设置。初次启动观察超时从同一实例恢复，未反复启动。一次Tab没有焦点报告，只记录观察而不写成完整焦点矩阵。[CC](evidence/2026-10-03-settings-full-page-final-cc.json)与[DS](evidence/2026-10-03-settings-full-page-final-ds-deepseek.json)已独立接受同一c937候选（ACCEPT_LOCAL_CHANGE），[Codex综合](evidence/2026-10-03-settings-full-page-final-review-synthesis.json)保留意见分歧和未验项；CC外层300秒超时后恢复原64244477会话的完整end_turn，未重启，CLI退出码未捕获；完整目标仍active，不因本增量通过关闭设备、真实非生产部署或完整GUI门槛。

## 历史增量：128 深度、正则预算修复与宽配置（ec44aa1a）

[113 文件清单](evidence/2026-10-03-regex-budget-final-candidate.manifest.sha256)与[12 项门禁](evidence/2026-10-03-regex-budget-final-results.json)全部通过：Rust70、Swift79、Python16、HTTP9、Debug/Release Node oracle、包内签名/XPC/MCP。新[188 项预算探针](evidence/2026-10-03-regex-budget-final-depth-guards.json)每种构建各94项，包含21种JS轴、JSON对象/数组与YAML流程、正则预算位置、40000/99000宽配置、20MiB精确边界及同进程恢复。部分超深YAML由依赖先返回YAML_PARSE_ERROR，属于有控制失败，不写成全部RESOURCE_LIMIT。

早前 `ea057db2` 的 [CC 原会话恢复评审](evidence/2026-10-03-depth-budget-first-cc.json)为 NEEDS_CHANGES：确实复现正则读取预算耗尽后越界 panic，以及600000游标预算错误拒绝部分合法宽配置；外层300秒超时后保留原CLI并取得end_turn，不重启，CLI退出码未捕获。[DS事实复核](evidence/2026-10-03-depth-budget-final-ds.json)接受的是旧ea057候选，不能覆盖CC实测问题或继承到ec44/设置候选。正则guard置于切片前，预算提高到3000000；2376个正则预算相位组合和宽配置有红绿证据。OXC保留发布包53个原文件、3个明确补丁文件和精确发布commit许可证，独立完整性门禁通过。

这份ec44候选已归档，但在新增设置前未取得新的双评审。下一轮审核包括这些资源修复与全部设置实现，不能写成已有双接受。

## 实现任务

- [x] Rust 类型树、严格 JSON、六类差异、精确数字与 UTF-16。
- [x] env.js 静态求值、对象身份、未知/不完整传播，不执行输入。
- [x] YAML CST 格式化、前后事件与注释核对、引用/多文档保护。
- [x] 原生 macOS 工作区、文件/粘贴、筛选/分页/详情/复制、新文件导出、XPC 隔离。
- [x] Vault URL/网页链接、遮罩 Token、可编辑 namespace/mount/目录/配置名称；两侧独立设置，预览后批量只读比较。
- [x] Namespace 与目录通配符：* 一层、** 任意层、? 单字符、. 当前范围。字面目录和通配结果使用相同配对键。
- [x] 本机 stdio MCP：env_compare、yaml_format、vault_preview、vault_compare、comparison_rows；凭证/范围不接受 MCP 参数修改。
- [x] App 主动授权后将两侧配置及逐条匹配清单写本机钥匙串；匹配清单改变拒绝读取；撤销后新读取/缓存分页都拒绝。
- [x] 历史本机 Release、包内 XPC、自签名/沙箱/依赖检查、合成 HTTP/MCP 与同候选 CC/DS 复核已有归档。
- [x] 历史82689fe0全窗口候选的12项门禁、打包/解压/签名与列出的实际GUI样本。
- [x] 最新c937全窗口/原生禁用候选的12项门禁、打包核验与列出的中英文GUI返回样本。
- [x] 最新c937候选的同候选CC/DS独立接受（本增量；wholeGoalAccepted=false）。

以上勾选表示列出的本机实现或历史验证已有证据，不能代替当前候选、正式分发或所有历史语义矩阵通过。

## 历史候选与包（8540e486）

- 候选 SHA256：8540e4862c3e1dce558b449b70c08868b4b1280ac07157ccd622b385f2b640a1。
- [51 文件冻结清单](evidence/2026-10-03-tree-model-final-candidate.manifest.sha256)：最终重新计算全部条目，无不匹配；只读评审没有修改这些文件。
- 本机 Release：build/Config Compare.app；arm64、macOS 26.5.2、Swift 6.2.1、Rust 1.97.1；使用完整 Xcode 的进程内 DEVELOPER_DIR，不改变系统默认选项。
- 主二进制 SHA256：17f2f42523c0e36cab27b58978ad145aa5288e87aa7f1639fd7664132fb0b4ca。
- worker SHA256：c6c003b214f9bb1eb82d3af6605a30d04a3ccd9900dd58bef320a3f01b43b137。
- [当前 ZIP 解压核验](evidence/2026-10-03-tree-model-final-package-check.json)：SHA256 2dd3b415441f28fd213fc281a728e6c9f0cec36a9de14cd36efb1b2d26124bfb；解压后主二进制一致，codesign 深度严格校验通过。
- ad-hoc + hardened runtime；codesign --verify --deep --strict 实际通过。App Sandbox + network.client + 用户选择文件；worker 仅 Sandbox，无网络/文件 entitlement；没有 network.server。
- otool 实测仅系统/Swift framework，Rust/MCP 依赖已编入包；最终用户不需要 Node、Python、Rust、Vault CLI 或 RTK。
- 本次未提交、推送、发布，真实 Vault 部署没有访问；用户给出的 UAT 地址仅用于理解网页链接形式。
- 本轮新增树文件后首次索引36 parsed/116 skipped，随后增量3 parsed/150 skipped和1 parsed/152 skipped，均0 errors；控制器修复后29 parsed/146 skipped，树性能首次30 parsed/172 skipped、迭代修复13 parsed/202 skipped，均0 errors；是索引结果，不作为语义验收证明。

## 历史本机实际验证（8540e486）

| 验证 | 实际结果 |
| --- | --- |
| Rust | 62 测试通过；Clippy --all-targets -D warnings 无问题；核心数字精度、重复 Key、未知、对象身份、特殊 JS/JSON/YAML 回归 |
| Swift | 74 测试通过：桥接/文件保护/generation，Vault 通配、请求/namespace header、不同配置名、动态 engine 拒绝、403 整批失败、字面/通配配对；MCP 参数、默认脱敏、授权清单改变不读值、扩大 namespace 清确认、撤销缓存保护 |
| 包内 XPC | 构建脚本签名后自动运行 --self-test，实际通过嵌套 JSON 精确数字/UTF-16/机器路径、JS 特殊类型树/BOM 首行偏移、YAML、JS 续行/原型/完整性/数字、非法 JSON 转义与未执行分支声明拒绝 |
| Vault 真实本机 HTTP + GUI（历史 b8e9e5f 候选） | loopback 合成服务；A mount FPMS-NT-V2 + uat-swim，B mount OTHER-KV + qa-other；各 2 配置，总计 4、相同 2、类型变化 2、仅 A/B 均 0 |
| MCP 真实 stdio | initialize、tools/list、env_compare、yaml_format、默认脱敏、范围参数拒绝、EOF 正常退出、stderr 空；从打包的同一 App 启动，实际使用包内 XPC |
| MCP Vault 真实集成（历史 b8e9e5f 候选） | GUI 保存合成钥匙串授权，MCP 预览/读取两个 mount、两套名称；GUI 撤销后新预览和已有 session 的 includeValues 分页都拒绝 |
| 凭证清理 | 测试前确认无已有本工具授权；测试只存 synthetic-token，结束后通过 GUI 删除，重新检查该 Keychain 项不存在；没有覆盖其他凭证 |

[打包 MCP 实测记录](evidence/2026-10-03-mcp-packaged-check.json)。本机截图及 AX 保存在 build/vault-live-final.png / build/vault-live-final-ax.txt，仅含合成输入。早期 GUI 已验证 env.js 七项样本和 YAML 引号/anchor/alias/多文档及 NSSavePanel 新文件导出；后续产品核心保留这些回归，当前 MCP/XPC 再验证两功能链路。

## CC / DS 讨论、修复与最后复核

- 初始纯离线阶段完成 env.js/JSON/YAML 核心。随后用户明确纠正：Vault 必须 URL + Token 直连；namespace/secret 目录均需通配，mount 与配置名称均可编辑；后续增加 MCP，确认三功能全部开放并同意钥匙串授权。旧离线“所有环境不连接”边界已被纠正，不能用于拒绝本轮功能。
- 新集成候选 770163c33d5e022603f20472c97c13367cc4b21b959e1d56f53d36e45ef7e866：CC NEEDS_CHANGES，指出授权仅存通配模式会自动扩大新目录/namespace范围，以及扩大 namespacePattern 未清非生产确认。DS NEEDS_CHANGES，指出字面目录与通配目录配对键不同。
- 三项均修复并增加回归；配对键用例先观察失败再修复。另补授权预览 5 分钟有效、单测注入拒绝授权避免真实钥匙串读取。
- [最终 CC 原始结果](evidence/2026-10-03-vault-mcp-final-cc.json)：LOCAL_ACCEPT，本次修订代码复核；额外只读核对核心会话 FIFO，不运行测试、不核对文件 hash，不是整个仓库/发行验收。
- [最终 DS 原始结果](evidence/2026-10-03-vault-mcp-final-ds.json)：LOCAL_ACCEPT，针对同一 b8e9e5f 候选的修订代码；请求 deepseek-chat，API 实际返回 deepseek-flash，如实登记。
- DS 最后复核第一次 TLS EOF，无结果；保留失败，不写通过；以相同候选重新请求取得完整 END_REVIEW。历史 CC 超时/旧稿结论不继承为当前接受。
- Codex 综合：两位同意三项修复及当前本机范围。DS 早期自行撤回的淘汰队列/钥匙串推测没有被当作阻断；明确单根配对与通配配对的相对路径契约。非生产真实性不能从 URL 命名证明，用户需核实来源；最终包运行/Keychain/MCP 证据由本次实际执行提供，评审判断不代替设备或发行证据。

## 完整目标仍 OPEN

Developer ID、公证/stapling、干净目标 Mac/Gatekeeper、Intel 真机、最低 macOS 14 真机、VoiceOver 全矩阵、历史稿所有语义用例、恶意输入/性能/内存压力全矩阵、依赖许可证完整发行审查、真实非生产 Vault/代理/TLS/namespace 部署兼容性尚未完成。

当前是本机开发包；旧设置候选 CLI/XPC/MCP 及实际 GUI 冷启动已有样本，新全窗口候选需要自己的 GUI 证据。已验证本机合成 HTTP，未验证用户真实 Vault，不要求 root Token，不用生产做验证。生产禁止，env.js 与 YAML 模式不联网。默认 Token 不落盘；只有主动授权 MCP 才写本机钥匙串。ad-hoc 重新签名可能导致旧 Keychain 授权失效，需要 App 重新授权，不绕过。

## 历史完整质量推进（cac794c6 候选）

[全量审计](quality-completion-audit.zh.md)保留91最低用例、11需求、6阶段和性能/GUI/发行门槛，没有把成功标准改成当前已通过部分。

- 新增7 Rust性质/精确数字/分页/YAML/变异测试，固定种子包含600对独立预期、1000数字等价、2400解析变异。
- 新增Vault故障矩阵及9个实际URLSession HTTP/TLS测试：不可信证书、跨origin重定向、Cookie不存、断网/超时、声明/流式20MiB限制、40并发、立即和中途取消及重用。取消URLError被误报网络失败已修复；逐字节收集改为受锁保护的分块delegate。
- 新增WorkspaceQuality实际核心状态测试：手算七项、筛选/详情/过期、Unknown、语法错误恢复、YAML、Vault编辑零请求和固定预览、文件失败保留输入。不是完整GUI自动化的替代。
- 新增7 Python验证器负向测试；空请求/跳过/缺路径/重定向/Cookie/非GET/-O不可能被当作通过。普通MCP验证不查询钥匙串或调用凭证工具，消除保存授权竞态导致意外联网的可能。
- [规范验证结果](evidence/2026-10-03-quality-final-results.json)：9条命令均exit0；Rust54/Swift42/Python7；清理后重新链接Rust，Release/XPC/MCP/EOF通过。[实际HTTP记录](evidence/2026-10-03-quality-final-network-check.json)列出9个HTTP用例和实际请求。实际-O的验证器及打包MCP额外通过。
- 当前GUI冷启动未证实：Computer Use读取App和Finder均失败（cgWindowNotFound/timeout、ScreenCaptureKit -3811）；不能把捕获失败当作App零窗口或入口根因。同步GUI入口与MCP托管结构已经编译及CLI复测，但窗口、三入口真实UI仍需恢复图形测试后完成。之前GUI/钥匙串批量链路属于b8e9e5f候选历史证据。
- CC初次调用因allowedTools参数消费了prompt而失败，未算通过；原失败结果保留。重新调用同候选并轮询原handle取得完整结果，未因观察等待重启。当前CC仅增量ACCEPT_LOCAL_CHANGE；[DS事实复核](evidence/2026-10-03-quality-final-ds.json)接受同一cac794c6候选。原NEEDS_CHANGES及TLS EOF失败保留，Apple取消契约和每次操作预算反证后DS主动撤回错误阻断。完整GUI条件和全量终审仍OPEN，不宣称完整目标完成。

目前无有效Developer ID Application身份（已读元数据确认0个）。仍有大量本机可继续验证/修复的工作；设备、真实非生产Vault、正式分发的外部条件缺失不用于提前关闭完整目标。


## 历史增量：交换、文件保护与独立语义验证（7b1a5c3a）

- A/B 交换同时移动内容、文件保护关联、标签、根候选、根选择和 JSON 包装类型；实际核心控制器测试验证 ONLY_A/ONLY_B 方向反转。Vault 的 URL+Token+范围成对移动，清除确认/固定计划，要求重新预览，不发请求，也不修改保存的 MCP 授权。YAML 和正在运行的操作不能交换。
- 普通文件限制基于非阻塞打开的实际描述符，FIFO 无 writer 时也立即拒绝；目录/设备/远端 URL 拒绝。实际测试20MiB可读、20MiB+1拒绝、非法UTF8拒绝、空文件及主动选择的符号链接；首次用例发现Foundation吞掉BOM，已修复并保留原文/换行。导出新文件0600，ENOENT不再误报已有文件。
- 7项scope_contracts专门验证未绑定简写、保守嵌套作用域、未知调用后新对象值恢复但程序不完整、BOM/LF/CRLF中文第二行字节列、业务data.data、明确混合KV包装、path-map精确键/schema及删除/重复包装整批拒绝。
- 固定种子Node独立oracle只运行脚本生成的8个可信模板，1024对/4189行的path、机器路径、状态、两侧类型/显示/存在性及汇总均比对通过。它不是用户JS执行能力，不声称全JS语义证明，Node不进入App运行依赖。
- 验证器新增文件/删除文件/改内容都会改变冻结清单，所有证据脚本AST检查禁止优化可移除assert；9个Python负向测试通过。
- [当前规范验证结果](evidence/2026-10-03-scope-files-results.json)：10条 cleanbuild 命令均exit0，Rust61/Swift48/Python9，[独立oracle](evidence/2026-10-03-scope-files-js-oracle.json)，实际HTTP/TLS9、签名/XPC/stdioMCP通过；本机ZIP SHA256为1b2260927374f120098d91144cfb634f41c9acea105ab965426b2eefb255f3eb。
- GUI：Finder重新可捕获，但旧进程终止后新包冷启动仍timeout/cgWindowNotFound；[PID90836采样](evidence/2026-10-03-scope-files-gui.sample.txt)显示正常App.main→NSApplication.run，命令行没有--self-test。不能把截图失败推断成零窗口或某个入口根因；真实窗口与交互验收仍OPEN。
- DS 首轮 NEEDS_CHANGES 与事实复核完整保留；方法内busy guard、已有30秒XPC超时/90秒packager限制、实际self-test exit0和BOM处理反证后撤回错误P1。[最终一致判定](evidence/2026-10-03-scope-files-final-ds.json)为ACCEPT_LOCAL_CHANGE，wholeGoalAccepted=false；请求deepseek-chat，返回deepseek-flash。原事实复核标题和末尾判定矛盾，单独追问统一JSON判定，未覆盖原记录。
- [CC 同一45文件候选最终评审](evidence/2026-10-03-scope-files-final-cc.json)为 ACCEPT_LOCAL_CHANGE。外层 MCP 300秒超时，原 CLI session fc080968 已写完整 end_turn 结论，直接恢复原结果，没有重新启动。两位仅接受本轮增量；GUI调查、跨XPC特殊值/取消、性能/无障碍/分发等仍OPEN。CC用了规定Sky流程之外的CGWindowList窗口枚举，这条只读线索不纳入GUI通过证据；验收仍须实际Sky/AX/交互。
- [同一包的额外副作用/类型探针](evidence/2026-10-03-scope-files-packaged-side-effect-and-types.json)：4类 require/fs、require/subprocess、fetch loopback、dynamic import 经 MCP→Swift XPC→Rust 只有静态结果，无3类文件标记或loopback连接。7类JS特殊值类型、显示与孤立surrogate编码单元无损往返，先验证默认differences不返回SAME，再用显式all分页取得。首个测试驱动忘记all导致KeyError，改测试调用后通过，源文件/候选未改；常驻规范回归与完整JSON类型树矩阵仍待补。


## 历史增量：完整 DTO 与生命周期（5e77bea4）

- Swift 类型树保留嵌套 entries/items、精确数字字面量、UTF-16 Key/值及区分 Key/索引的机器路径；真实 C ABI 与打包 XPC 验证 JSON 大整数、1e10000、-0、孤立 surrogate，以及 JS BigInt/NaN/Infinity/undefined/空槽。非法机器路径拒绝。
- JS/JSON 保留 BOM 原始定位，首行中文列位置回归先失败后修复；实际包内 MCP 为20/17列。YAML 输出沿用移除前导 BOM，原输入保留。
- 文件导入有独立 A/B pending 状态，阻止执行/交换；替代导入和取消使旧回调失效。导出错误保留可能不完整的新文件，不按路径删除别的操作替换后的文件；真实描述符故障注入验证两种情况。
- HTTP 验证读取 Swift 实际发现的清单，只在 HTTP suite 成功区间核对全部方法；12 个 Python 负向测试及 -O 实测通过。MCP 启动失败返回1，正常 EOF 返回0。
- 4 类恶意表达式副作用探针、7 类特殊值和首行 BOM 偏移纳入 scripts/check-mcp.py，实际打包 App→XPC→Rust 无标记文件、无 loopback 连接；普通验证不触碰钥匙串 Vault。
- [当前规范验证](evidence/2026-10-03-dto-lifecycle-results.json)：10 条命令 exit0，Rust62/Swift56/Python12；[打包探针](evidence/2026-10-03-dto-lifecycle-packaged-boundary.json)绑定主二进制 SHA。Node 独立 oracle 仍只验证 debug 核心有限模板，release-oracle、版本/corpus 与完整状态汇总待补。
- [DS 独立结果](evidence/2026-10-03-dto-lifecycle-final-ds.json) ACCEPT_LOCAL_CHANGE，无 P0/P1；[CC 同候选结果](evidence/2026-10-03-dto-lifecycle-final-cc.json)也为 ACCEPT_LOCAL_CHANGE，无 P0/P1，48/48 文件哈希一致；未重跑测试或进行 GUI 检查。DS 的导出后守卫建议不符合现有源码，该守卫已存在。GUI/完整目标/正式分发仍 OPEN；本轮没有真实 Vault 访问。

本轮再次通过 Sky 读取现有 Config Compare 进程，仍返回 cgWindowNotFound。现有 GUI 进程可能属于旧包；不把这次捕获失败当成当前候选的窗口数量、根因或交互验收证据。

5e77bea4 双评审综合：两位均认可该轮类型树、BOM 原始定位、导入代际和验证器边界。CC 额外指出一般选项变化会同时作废两侧导入、导入中根检查仍可读取旧文本、JSON BOM 注释过时；这些 P2 在该候选尚未修复；后续修复见当前增量。DS 的保存对话框后 guard 建议已有源码反证，不当作当前缺陷。离线 Node oracle 的 Release/版本/corpus、完整 GUI 与设备发行门槛继续 OPEN。


## 历史增量：选项变化保留导入与 Debug/Release oracle（4758a507）

- 上轮CC的三项P2已修复：选项变化不丢掉正在导入文件，停止计算不连带取消另一侧导入；导入中不读旧文本检查根；JSON BOM 注释与实际 importer 行为一致。四个回归先失败再通过，原有代际/取消/全局根用例继续通过。
- [全部本机门禁](evidence/2026-10-03-import-oracle-results.json)十条通过，Rust62/Swift60/Python14，Python -O 实测14通过；当前包内XPC/MCP/EOF及签名均通过。没有访问真实Vault或本工具已有钥匙串授权。
- [固定 Node oracle](evidence/2026-10-03-import-oracle-js-oracle.json)对两种构建各验证1152对/4317行，五个可比较状态含79项TYPE_CHANGED；固定种子/corpus哈希、oracle源码哈希、实际二进制哈希与Node/Rust版本留证。仅固定可信模板在开发验证中执行，最终App无Node运行依赖，不执行用户JS；Unknown仍由核心单测证明。
- [Release十万结果核心基线](evidence/2026-10-03-import-oracle-release-core-benchmark.json)：M3/24GiB，单次比较142.611ms，120次预热后路径查询P50 5.980ms/P95 7.013ms，峰值RSS154599424字节；全部匹配数与分页路径独立验证。含stdio/JSON解码，不含GUI/XPC，也不是冷启动、滚动或全包内存验收。
- [CC](evidence/2026-10-03-import-oracle-final-cc.json) 与 [DS](evidence/2026-10-03-import-oracle-final-ds.json) 均为当前同候选 ACCEPT_LOCAL_CHANGE，无 P0/P1；CC 本机核对48/48清单，DS审阅所提供文件而未本机复算。DS首次TLS失败及同候选重试记录完整保留，API实际返回deepseek-flash。两者只接受本轮增量；完整目标仍 active。

当前双评审综合：两位认可导入选项保护、根检查守卫和 Debug/Release 独立对照。CC 指出单独文件导入时 Esc 命令仍禁用（仅 busy 启用）及 SEED 在 Python/JS 两处重复常量；两项继续修复。DS 的“文件中9个@Test”计数不准确，该文件为7例，另2例位于WorkspaceTests；规范日志实际60例通过。DS未收到稍后新增的核心性能报告，其“无benchmark”只描述当次审阅材料，不抹去已归档性能样本，也不关闭GUI性能门槛。


## 历史增量：结果树与停止导入（c74e1d90）

主表新增平面/当前页树切换，机器路径分组不改变摘要、完整性、匹配数或导出。纯分组保留原生选择焦点，不成为真实结果；选中字段仍按原ID获取详情。详情树只读展示完整容器DTO，单侧容器/类型变化子项不再计数，UnicodeScalar有界预览保留原literal。菜单Esc与toolbar由canStop控制，单独导入也可作废旧结果并保留输入。

[全门禁](evidence/2026-10-03-result-outline-results.json)十条通过，Rust62/Swift70/Python14、HTTP9、包内XPC/MCP/EOF/签名实际通过；17项树/导入/选择专项通过。清选择后旧详情回填真实回归先失败再修复。树新API的编译红记录不冒充旧实现的运行期语义失败。

[当前GUI冷启动](evidence/2026-10-03-result-outline-gui-status.json)仍未通过：精确核对并终止旧自有测试进程后新包路径timeout、bundle ID cgWindowNotFound，Finder亦ScreenCaptureKit -3811。[CC](evidence/2026-10-03-result-outline-final-cc.json)与[DS](evidence/2026-10-03-result-outline-final-ds.json)独立接受同一c74e1d90增量，无P0/P1；CC复算51/51文件并正常完成，DS实际返回deepseek-flash。下一增量修复导入单独停止保留有效结果、模型选择失效和Unicode分组路径显示。树构造成本及展开状态稳定性尚未实测，不采纳评审中的性能/界面推断为通过证据。折叠/展开/真实Esc/键盘、VoiceOver、巨型树帧时间、设备发行均OPEN，不宣称完整目标完成。


## 历史增量：导入停止保留有效结果（ccaae0f7）

只有导入正在进行时，“停止”作废两侧导入但保留有效比较会话/选择详情与YAML输出；切换工具依然清旧结果。selected直接清除/改选立即拒绝旧详情，无须界面回调。同ID保持已显示详情。

[运行期红](evidence/2026-10-03-import-preservation-red.log)4项8处失败，修复后[14项专项绿](evidence/2026-10-03-import-preservation-focused-green.log)及[全部十项门禁](evidence/2026-10-03-import-preservation-results.json)通过（62 Rust / 73 Swift / 14 Python）。[ZIP解压和签名](evidence/2026-10-03-import-preservation-package-check.json)通过。[CC](evidence/2026-10-03-import-preservation-final-cc.json)与[DS](evidence/2026-10-03-import-preservation-final-ds.json)均独立接受新候选，无P0/P1；CC复算51/51，原调用正常结束。DS实际deepseek-flash。GUI/性能/设备/发行与真实非生产部署继续OPEN。


## 历史增量：深层树性能与崩溃恢复（8540e486）

Branch复用显示前缀并改为显式后序freeze；真实CABI 200×深度120回归保留24000节点/200结果、完整路径与计数及报告不变。小线程栈的递归投影曾signal10退出，核心、DTO和报告已返回；阶段红与同测试源快照修复绿均归档。最终[十门禁](evidence/2026-10-03-tree-model-final-results.json)全部通过（62 Rust / 74 Swift / 14 Python）。[参考机纯模型复跑](evidence/2026-10-03-tree-model-final-benchmark.json)深树P95由1332.222ms降至60.376ms，[额外深层MCP/XPC](evidence/2026-10-03-tree-model-final-deep-packaged-mcp-check.json)通过，不能代替GUI/完整资源矩阵。[当前GUI状态](evidence/2026-10-03-tree-model-gui-status.json)仍OPEN。[CC](evidence/2026-10-03-tree-model-final-cc.json)与[DS](evidence/2026-10-03-tree-model-final-ds.json)均独立接受同一最新冻结候选，无P0/P1；CC复算51/51、原调用正常完成，DS实际deepseek-flash且仅收范围文本，未本机复算。128/129边界、析构小栈与GUI帧时间继续补，不继承上一版本接受；完整目标active。

## 最新设置增量交付

c937450f的117源码文件保持冻结；12项完整门禁、12设置专项、实际中英文全窗口/返回GUI、ZIP解压与深度严格签名、CC/DS同候选独立接受均登记。最终App为本机arm64开发包，未提交、推送或发布；没有真实Vault/生产连接。主计划1.4已包含整窗设置、顶部返回、独立关闭与原生禁用契约。

后续仍需完整Tab/多窗口、真实IME与预先marked状态、主题回退、VoiceOver/undo/滚动和已保留的全目标矩阵；双接受不能代替这些门槛。

## Vault 逐条来源与错误恢复（e84a5f23）

2026-10-03 · 1.7 当前来源增量：冻结候选 `e84a5f23b1f8a9e7c1f765b23ccbc3168fac3567e5ec5d04715751aff087b64f`（127文件）的[12项本机门禁](evidence/2026-10-03-vault-provenance-final-results.json)通过（Rust93 / Swift114 / Python17，共224项），真实HTTP/TLS11例、Debug/Release可信Node对照、188资源探针、包内XPC/stdioMCP继续通过。[新包GUI](evidence/2026-10-03-vault-provenance-final-gui-proof.json)验证混合KV、四笔来源、KVv1未知、KVv2计划删除可读、右侧展开不挤压表格、中英文整页设置返回、完整JSON来源、已删除/销毁/未确认404整批失败及恢复；重预览/重读取不保留旧行来源，原用户三行多变量结果已恢复。[包核验](evidence/2026-10-03-vault-provenance-final-package-check.json)通过。[CC/DS同一新候选独立接受](evidence/2026-10-03-vault-provenance-final-review-synthesis.json)；只接受本增量，完整91项、读期间修改/回退、真实非生产部署、完整GUI/IME/VoiceOver/性能、目标设备与正式发行仍OPEN。没有真实Vault或生产访问。

Rust严格业务提取保留大数/UTF16，metadata独立白名单、unknown=null、Token/custom_metadata不进入来源DTO。只有现有GET，没有metadata附加请求。deletion_time可能计划删除，可读对象保持readable；已删除/销毁直接停止整批，不产出相同/缺失结论。详情按typed UTF16键匹配，来源随session淘汰与授权撤销保护。旧源码回归和实际GUI发现均保留，未提交/推送/发布。


## 历史测试增量：类型报告与 CSV（02cb144e4b85）

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

完整剪贴板复制/恢复尚未执行；原始输入通过编辑器设置恢复，未点击复制按钮，原剪贴板各格式及内容恢复未验证。Vault加入来源装饰后的JSON重编码、更多GUI/IME/VoiceOver/性能、真实worker恢复、干净目标设备、已批准的真实非生产Vault与正式发行仍OPEN。两位提出的逐run隔离历史旁侧日志、目录fsync及证据落盘失败时保留原诊断等非阻塞建议留在综合记录；不由局部接受宣称100%。没有真实Vault或生产访问，没有执行用户JS。


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

## 多变量多层嵌套与分页状态修订（d776ce0a36c0）

本轮按用户新增的多层嵌套要求，递归比较所有选中变量的对象分支与数组元素；显示env.api.retries.max、env.servers[0].tls.enabled、happy.options.cache.enabled。父对象变成字符串只在父节点显示类型变化，特殊点号键与实际多层路径保持独立，深层Unknown不抹掉已知兄弟。比较核心已有此能力，没有执行用户JS或更改递归算法。[本轮专项证据](evidence/2026-10-03-nested-batch-final-focused-proof.json)保留8个新增命名测试和作者错误纠正边界。

当前候选完整13门禁runID `29086c2a-01f7-475c-ace2-37a5c0b9c42d`，起止源码稳定，Swift零警告；实际HTTP/TLS、可信Node双profile、资源探针、包内XPC/stdioMCP继续通过。新包的401行分页分别从k000/k200/k400开始，编辑后禁止分页/筛选/显示/导出选项，重比较恢复；深层树展开、类型详情、Unknown和原始三行恢复共11组AX/JPEG。[包/ZIP核验](evidence/2026-10-03-nested-batch-final-package-check.json)与[评审后完整性](evidence/2026-10-03-nested-batch-final-post-review-integrity.json)通过。

实际CC原调用session `ffaee288-ab29-43f7-b503-bdb333779dfa` 正常exit0/timedOut=false，核对8个范围源码哈希并读代码/AX，不是独立重演测试或GUI；DS请求deepseek-chat，实际deepseek-flash，仅文本审阅。双方接受只属于这一冻结增量，不转成完整目标或正式发行接受。

下一项核验：CC N1从源码推断行请求尚未返回时，被export/inspectRoots推进generation取代或请求失败，可能留下已更新页码与旧行；尚未复现，需确定性运输门控实测。N2取消导入的迟到恢复等待强度、N3重复行请求、N4Unicode行/分组显示差异也保留。DS对单个按钮未叠加stale的疑问没有新的产品反证：父HStack统一disabled，实际AX已证明两个分页按钮禁用。禁止生产连接保持不变；完整91项、GUI/键盘/IME/VoiceOver/性能、设备、真实获准非生产、许可证/正式分发仍OPEN。

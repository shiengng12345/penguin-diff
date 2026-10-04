# 全量验收审计与继续执行清单

> **2026-10-04 最新 Vault URL 协议增量：**候选 `b7c5ca5b3eff90d65e3ee8b94519cc53fae8a8024c67f136116cde0b9a6ef778` 移除了入口处 HTTPS-only 校验，并新增 HTTP 与 `vault://` 解析回归；账号、密码、fragment、端口、路径和生产标识校验保留。完整门禁 15/15、Swift 251 tests／30 suites 通过，`realVaultAccessed=false`；CC 与 DeepSeek 对同一 SHA 均 `ACCEPT_LOCAL_CHANGE`，blocking 为空。非 HTTP scheme 仅代表解析接受，不代表 URLSession 已验证连通。详见[协议专项](evidence/vault-url-scheme-review-synthesis.json)、[本轮门禁](evidence/vault-url-scheme-main-rerun.json)。整体严格审计仍为 51 项完整、26 项部分、14 项 OPEN，完整关闭率 56.0%。

> **2026-10-04 最新目录优先／共同配置过滤增量：**候选 `aa270086dc10dd2c933b7f5e2baccc3666bc6456324dfa571df65f2bd969f567` 已完成 15/15 本机门禁、Swift 250 tests／30 suites；`VaultDiscovery` 定向测试在修复后为 29 tests／2 suites。根目录 `.` 使用单层读取并不再携带 matcher，只有真实 `**` 读取才可产生全目录交集；空目录会使交集为空，切换 namespace、mount、目录和匹配范围会清理无效配置名称。CC 与 DeepSeek 对同一 SHA 均返回 `ACCEPT_LOCAL_CHANGE`，blocking 均为空。loopback 网络、NOTICE、资源、严格签名、打包 self-test 与 ZIP 均通过；`realVaultAccessed=false`、`formalReleasePassed=false`。本增量不改变全量审计的严格分类：51 项完整关闭、26 项部分证据、14 项纯 OPEN，完整关闭率仍为 56.0%。详见[目录过滤专项](vault-directory-filter-quality.zh.md)、[CC](evidence/vault-directory-filter-cc.json)、[DeepSeek](evidence/vault-directory-filter-ds.json)、[双审合成](evidence/vault-directory-filter-review-synthesis.json)和[本轮门禁](evidence/vault-directory-filter-main-rerun.json)。

> **2026-10-04 最新 Vault 取消／迟到响应增量复审结果：**候选 `088678478a170a3d9b4283ea7f6f53dd9819c03200d52a098dc5f4fab5b710d6` 的 CC 与 DeepSeek 均返回 `ACCEPT_LOCAL_CHANGE`，blocking 均为空。CC 留下固定等待、已有结果后 scope 变更和 gate miss 释放 continuation 等 non-blocking；这些不被误记为完整关闭。`realVaultAccessed=false`、`formalReleasePassed=false` 保持不变。详见[专项记录](vault-cancellation-quality.zh.md)、[CC](evidence/vault-cancellation-cc.json)、[DeepSeek](evidence/vault-cancellation-ds.json)和[合成](evidence/vault-cancellation-review-synthesis.json)。

> **2026-10-04 最新 Vault 取消／迟到响应增量：**本地候选 `088678478a170a3d9b4283ea7f6f53dd9819c03200d52a098dc5f4fab5b710d6` 完成 15/15 门禁、Swift 245 tests／30 suites；新增 KV v1/v2 的 403/404/429/503 中途失败整批丢弃与显式重试、取消后的迟到 data 回复丢弃、Vault scope 变化后的 Workspace generation 守卫。`realVaultAccessed=false`，`formalReleasePassed=false`；本轮只把 V15/V16 从纯 OPEN 调整为本机模型部分通过，未宣称真实 Vault、打包 worker、GUI 或正式发行完成。严格分类为 51 项完整关闭、26 项部分证据、14 项纯 OPEN，完整关闭率 56.0%。详见[Vault 取消／迟到响应专项](vault-cancellation-quality.zh.md)与[本轮证据](evidence/vault-cancellation-main-rerun.json)。

> **2026-10-04 最新 J18/C07 文件编码与特殊值增量：**主源码候选 `a7d7f9714c8b50fedf8732dee368581387500cbf92163aa4428cb8554237008b`（331 文件）已完成 15/15 本机门禁、Swift 243 tests／30 suites。新增真实文件→匿名进程内 NSXPC→Workspace 的 BOM/无 BOM、LF/CRLF、中文路径／字节列矩阵，以及经 NSXPC 的 Missing/null/undefined/空字符串／三种类型变化详情矩阵均通过；loopback 网络、打包 XPC self-test、MCP、NOTICE、资源和 ad-hoc 签名核验通过，`realVaultAccessed=false`。J18 从纯 OPEN 改为“本机模型通过、完整 GUI 与打包 worker OPEN”；C07 的特殊值模型、NSXPC 与详情证据已补齐，但完整 UI 仍未验。malformed BOM+CRLF 的 EOF 错误行列仍为 0/0，未伪造偏移。CC 与 DeepSeek 针对同一 SHA 均 `ACCEPT_LOCAL_CHANGE` 且 blocking 为空；双审仍没有把 GUI/打包 worker/正式发行边界算作完成。按 91 项严格分类：51 项完整关闭、24 项部分证据、16 项纯 OPEN，完整关闭率 56.0%。详见[文件编码与特殊值增量](file-encoding-ui-quality.zh.md)、[本轮证据](evidence/file-encoding-ui-quality-main-rerun.json)和[双审合成](evidence/file-encoding-ui-quality-review-synthesis.json)。

> **2026-10-04 最新 N4 Unicode 行／分组一致性增量：**主源码候选 e503684dc4c354c2b0c96bcd493e1a60ad187cb9fc1d41cbb617059a5d833154（331 文件）已合入。核心与 Swift 统一 ASCII 点号／Unicode 括号路径规则，UTF-16 分组保留 NFC/NFD、中文、点号及 lone surrogate identity；正式 15/15 门禁、Swift 237 tests／30 suites、包内 self-test／签名／MCP／资源核验及同 SHA 的 CC／DS ACCEPT_LOCAL_CHANGE 已记录。N4 已关闭；真实 GUI／设备／非生产部署／正式发行仍开放。详见[N4 证据](evidence/unicode-groups-quality-review-synthesis.json)。

> **2026-10-04 最新导入生命周期 N2 增量：**主源码已更新为 `d73132e2c1b6512054cfd99fc8015f82368eb368eb8f1852d254c6a04de8ec00`（331 文件）。取消导入后的迟到成功／失败等待改为真实 import Task 完成事件；正式 15/15 门禁、主工作区 `swift test --no-parallel` 的 236 tests／30 suites、成功 token guard 突变负向验证通过；Claude Code／DeepSeek 对同一 SHA 均 `ACCEPT_LOCAL_CHANGE`。这只关闭 N2 导入等待测试强度，N4、真实 GUI／设备／性能／非生产部署／正式发行仍开放。详见[导入生命周期 N2 修订](import-lifecycle-quality.zh.md)。

> **2026-10-04 最新行请求去重增量：**主源码已更新为 `8d0a33f5bf778c5941c545b04177d740e24d058e0ea74c5177403b553af5566a`（331 文件）。相同 rows 请求在途合并、token 精确清理和失败等待回归已合入；正式 15/15 门禁及主工作区 `swift test --no-parallel` 的 236 tests／30 suites 通过，CC／DS 对同一 SHA 均 `ACCEPT_LOCAL_CHANGE`。这只关闭重复 rows 请求的局部风险；N2/N4、真实 GUI／设备／性能／非生产部署／正式发行仍开放。详见[行请求去重修订](rows-dedup-quality.zh.md)。

> **2026-10-04 最新单实例增量：**主源码已更新为 `e20e0d03be1bb7c36a67de352cb39370ab00e65f609cea1ab77282fc6dc55403`（331 文件）。用户级 `fcntl` 锁、正式 bundle 约束、已完成启动 peer 过滤和异步复用 handoff 已合入；隔离候选 15/15 门禁通过，Swift 235 tests／30 suites，真实 Vault=false；CC／DS 对同一 SHA 均 `ACCEPT_LOCAL_CHANGE`。这只关闭重复 GUI 实例的本地增量，不关闭真实桌面、键盘／IME／VoiceOver、设备、完整性能、非生产部署或正式发行门槛。详见[单实例修订记录](single-instance-quality.zh.md)。

> 上一轮主源码 `56b6d94b…`（329 文件）：[代码显示／行号裁剪修复](editor-ruler-visibility.zh.md)已通过 15 项完整本机门槛、Rust 95／Swift 229 项测试、新包 10 项核验及同候选 CC／DS 独立增量接受；Vault 链接＋Token 下拉发现与批量比较保留。代码文字在整页原生图像中恢复，实际桌面／输入法／设备／完整性能／正式发行和原 91 项仍未全部验收。没有启动、关闭、切换用户 App 或改变其输入。

> 下文旧版本的“当前”哈希、运行窗口、深浅色和计数均只对应各自历史记录；本轮没有重新核对用户窗口 PID，不继承旧版接受为完整目标通过。

> 最新[许可证／NOTICE资源交付](license-delivery-quality.zh.md)：0fd389候选315项源码、14门禁／361项命名测试、105份原生渲染、新包177文件及同候选CC／DS独立源码接受通过；仅开发构建与本地资源增量已合入。当前App与输入保留，完整目标／正式发行仍active。

> 历史[测试记录与自有进程组清理](run-lifecycle-quality.zh.md)：同一ed3423候选13门禁／345项命名测试、105份原生渲染、ZIP核验与CC／DS独立源码接受通过；两个脚本已合入，当前App与输入保留。完整目标仍active。

> 当前主源码已更新为36fbb707／143文件：[Vault四尺寸滚动与整次测试门禁](minimum-window-and-run-gate.zh.md)通过13门禁／335项测试、105份原生图像和同候选双源码接受；当前App与输入保留，完整目标仍active。下文具体哈希、计数与结论属于原候选历史。

> 上一[Vault首屏表单与绑定修订](vault-form-quality.zh.md)：8a6e候选已合入主项目，13门禁／325项命名测试、三尺寸71份原生渲染、ZIP核验及CC／DS独立源码接受通过。本文下方较早的统计保留为历史；当前App与输入保留，完整目标／设备／真实性能／正式发行继续开放。

> 后续[Unicode 输入／结果过期修订](unicode-workspace-quality.zh.md)：5项完整页面回归在旧代码复现17条断言；修复后13门禁／322项测试、三尺寸19状态原生布局、ZIP核验及同候选CC／DS源码接受通过。确切修订已合入项目；比较核心与当前用户窗口未替换，完整目标仍active。

> 后续[编辑器生命周期调查](editor-lifetime-investigation.zh.md)：补强隔离候选200项原生回归通过，20 MiB Debug／Release固定样本通过500ms断言。CC同意继续实验，DS仍要求修改；旧Swift Testing残留及普通窗口动画释放未完成归因，完整应用集成与最终双验收开放。该布局／所有权实验未进入主源码，当前用户窗口未替换，不声明完整目标通过。

> 后续[非连续布局／绑定同步实验](noncontiguous-layout-investigation.zh.md)：独立 20 MiB Debug／Release 往返样本已改善，但 196 项完整原生回归有两项对象释放检查失败（退出码 1）。普通 NSTextView 校准同样保留，原因未明；实验未进入主工作区，不替代原性能、内存／100 次循环、实际设备或最终同候选双评审门槛。完整目标保持 active。

> 2026-10-04 上一轮行号修订候选 `2f080310…`（140 文件）：[13 门禁／317 测试及新包核验](gutter-quality.zh.md)已通过，同候选 CC／DS 独立接受与评审后完整性核验均通过。以下为各历史增量证据。当前运行窗口仍为白鹅视觉基础版 `8df029ff…`；[20 MiB 完整挂载实验](editor-performance-investigation.zh.md)未达性能预算，实验代码未进入新包。完整原 91 项、实际桌面／输入法／设备／正式发行仍开放。

> 本轮视觉清理已在现有原生架构实现：界面仅使用中性 SF Symbols，App 图标使用用户提供的本地 PNG，动物插画与冬日主题已移除。当前只有奶油白浅色主题，旧深浅色 GUI 证据属于历史。原 91 项全量标准及设备/性能/真实非生产/发行门槛仍有效，不能用视觉增量接受替代完整目标。

> 后续[编辑器精修](editor-quality.zh.md)候选 `20bc16ef…`：13 门禁／314 测试、Release 原生专项及同候选 CC／DS 独立源码接受通过。JS／JSON／YAML 高亮、增量行号、10.2 MB 编辑及延迟刷新的颜色尾部补原生回归；三项额外原生边界探针与 CC 离线模型均独立记录，不累加冻结门禁测试数。首次冷追加、整页绑定性能与实际桌面验证仍 OPEN。新包独立保存，当前用户窗口继续运行上轮白鹅视觉候选，未替换或修改输入。

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

> 2026-10-03 · 原始目标保持 active；不能因为本机测试通过或局部双评审接受就宣称 100%。
> 历史NSXPC修订：`3621fdd9c69a1d855737343d863ac9a8caa21acac683dacecf992abd9c539640`（131文件），[13项门禁](evidence/2026-10-03-ipc-lifecycle-final-results.json)全部通过（Rust93 / Swift132 / Python33，共258项）；真实NSXPC取消/中断/默认30秒及[当前新包多变量GUI](evidence/2026-10-03-ipc-lifecycle-final-gui-proof.json)样本通过。[DS接受、CC待额度恢复后评审](evidence/2026-10-03-ipc-lifecycle-final-review-synthesis.json)，双方接受未达成，完整目标仍active。
> 历史Vault导出验证候选：`5c44e36be89f4ff5111405dbe25a30b6f04382b2e6c19be2899a7360c3f088bd`（130文件），[13门禁](evidence/2026-10-03-vault-report-export-final-results.json)全部通过（Rust93 / Swift123 / Python33，共249项）；六项实际导出及六项运行期变异通过，新包默认保存GUI通过。[DS接受、CC因API429尚未评审](evidence/2026-10-03-vault-report-export-final-review-synthesis.json)，完整目标仍active，不能宣称双方已接受或100%。
> 历史状态/GUI增量：`d6f6e04ad3bd45318fd0ceaa3ba738493dba6003f0429a61324270f788cc9ec5`（129文件）的[13条门禁](evidence/2026-10-03-verifier-status-final-results.json)全部通过（Rust93 / Swift117 / Python33，共243项），总体passed/finished和manifestStable明确为true。新增12个验证器回归，真实新包[12份GUI记录](evidence/2026-10-03-verifier-status-final-gui-proof.json)与[6份JSON/CSV导出](evidence/2026-10-03-verifier-status-final-gui-file-proof.json)通过；[同候选CC与DS](evidence/2026-10-03-verifier-status-final-review-synthesis.json)均接受本增量。没有真实Vault/生产访问；复制/恢复、Vault装饰导出、全量GUI/设备/非生产/正式发行继续OPEN。
> 历史导出验证增量：`02cb144e4b85356addced8006c0793520dd3a9ba1d92ce9bb49e916051483cc0`（129文件），[13条门禁](evidence/2026-10-03-report-roundtrip-final-results.json)全部通过（Rust93 / Swift117 / Python21，共231项）。[独立报告证据](evidence/2026-10-03-report-roundtrip-final-report-proof.json)和真实FFI→新文件→读取→DTO覆盖类型/UTF-16/精确数字/长文本/240行/过滤/隐藏值；[同候选CC与DS](evidence/2026-10-03-report-roundtrip-final-review-synthesis.json)均接受本增量。没有新的GUI/剪贴板证据，没有真实Vault或生产访问；全量91项及设备、非生产部署、正式发行仍OPEN。
> 历史来源增量：冻结候选 `e84a5f23b1f8a9e7c1f765b23ccbc3168fac3567e5ec5d04715751aff087b64f`（127文件）的[12项本机门禁](evidence/2026-10-03-vault-provenance-final-results.json)通过（Rust93 / Swift114 / Python17，共224项），真实HTTP/TLS11例、Debug/Release可信Node对照、188资源探针、包内XPC/stdioMCP继续通过。[新包GUI](evidence/2026-10-03-vault-provenance-final-gui-proof.json)验证混合KV、四笔来源、KVv1未知、KVv2计划删除可读、右侧展开不挤压表格、中英文整页设置返回、完整JSON来源、已删除/销毁/未确认404整批失败及恢复；重预览/重读取不保留旧行来源，原用户三行多变量结果已恢复。[包核验](evidence/2026-10-03-vault-provenance-final-package-check.json)通过。[CC/DS同一新候选独立接受](evidence/2026-10-03-vault-provenance-final-review-synthesis.json)；只接受本增量，完整91项、读期间修改/回退、真实非生产部署、完整GUI/IME/VoiceOver/性能、目标设备与正式发行仍OPEN。没有真实Vault或生产访问。

本轮从当前源代码和计划1.16逐项核对；原1.1最低91项门槛继续保留。测试层包括 Rust 核心、Swift 状态逻辑/真实 FFI、实际 loopback URLSession HTTP/TLS、打包 XPC 与 stdio MCP。前端状态测试不代替真实 GUI/VoiceOver；合成 Vault 不代替实际非生产部署；固定种子变异不代替持续 fuzz。

可复现入口：`rtk proxy python3 scripts/verify-local.py`。它清理 Swift 构建以重新链接 Rust，执行 fmt/Clippy/Rust 测试、完整 Swift + 本机 HTTP/TLS 测试、Release 打包/签名/XPC self-test 和实际 MCP。普通验证不会读取已有钥匙串 Vault。`build/verification/results.json` 与逐项日志绑定冻结清单。

## 需求和阶段

| 项 | 当前证据 / 仍需完成 |
| --- | --- |
| R01–R06 | 本机三入口实现及手算/类型/真实包验证已有；全 UI 矩阵仍独立执行 |
| R07 | 原生设计已实现，完整状态/主题/小窗口、动画与录屏仍待完成 |
| R08 | 本机包不依赖外部开发运行时；Intel/最低系统/干净设备与正式签名未证明 |
| R09 | 只读范围、确认、参数限制、重定向/TLS/错误保护已测；生产真实性依赖核实来源，不伪造自动检测能力 |
| R10 | 本清单保留未完成项；持续补前后端完整测试，不按成本缩减 |
| R11 | 只做用户指定三功能及 MCP/测试/交付；不增加 SRE 平台功能 |
| P0 | 工具链/FFI/样本已验证；完整 DTO/资源/真实 Vault 支持矩阵未闭合 |
| P1 | env.js 本机纵向链路已有，完整键盘/文件/错误 UI 待验 |
| P2 | 静态语义与核心回归已有；以下 J/C、树视图、无障碍与动效待验 |
| P3 | Vault live/import 与 MCP 已实现；以下 V 和真实非生产部署待补 |
| P4 | 筛选/分页/详情/导出已有；复制/全部格式/来源与 UI 全矩阵待补 |
| P5 | 本机 ad-hoc 包通过不等于正式发布；签名、设备、许可证、支持矩阵仍待完成 |

## 1.1 第14节最低用例（91项）

1.1 第7.3节另外使用 U01–U10 作为页面状态 ID，不能与这里的第14.5节测试 ID 混用。该页面状态全矩阵仍 OPEN。

| ID | 原场景 | 状态 | 直接证据 / 下一步 |
| --- | --- | --- | --- |
| C01 | 对象 Key 任意重排 | 样本通过 | contracts: compares_reordered_json；quality_matrix: seeded_scalar_oracle (600 对) |
| C02 | 嵌套对象重排 | 样本通过 | quality_matrix: nested_key_order_array_order_and_empty_container_matrix |
| C03 | 仅 A 字段 | 样本通过 | quality_matrix: seeded_scalar_oracle 独立预期 ONLY_A |
| C04 | 仅 B 字段 | 样本通过 | quality_matrix: seeded_scalar_oracle 独立预期 ONLY_B |
| C05 | 同类型不同值 | 样本通过 | quality_matrix: seeded_scalar_oracle 独立预期 VALUE_CHANGED |
| C06 | 数字与字符串 | 样本通过 | 手算七项 + scalar oracle + Swift actualRustBridgePreservesTypeChanges |
| C07 | 缺失/null/undefined/空字符串 | 部分通过 / 本机模型与详情已补齐 | nested container matrix + JS typed special values + 文件→NSXPC→Workspace 的 Missing/null/undefined/empty 与 TYPE_CHANGED 详情；完整 UI 展示仍待验，见[file-encoding-ui-quality](file-encoding-ui-quality.zh.md) |
| C08 | 空对象与空数组 | 样本通过 | nested container matrix，空 Object/Array 不消失 |
| C09 | 数组重排 | 样本通过 | nested container matrix，数组交换产生两项变化 |
| C10 | 数组空槽与 undefined | 样本通过 | contracts: sparse_array_is_distinct_from_undefined |
| C11 | Key 含点号、斜杠、空字符串 | 样本通过 | quality_matrix: decimal_scale_equivalence_and_utf16_paths |
| C12 | Unicode、emoji、孤立 surrogate | 部分通过 | surrogate 回归 + UTF16 路径与规范化字符；Swift 类型树与包内 XPC 保留编码单元已验证，完整 GUI 显示仍待验 |
| C13 | 大数与指数表示 | 样本通过 | 精确大数/指数边界回归 + 1000 组十进制等价 |
| C14 | -0 / +0 / NaN / Infinity / BigInt | 部分通过：实际GUI/文件样本通过 | d6新包真实JSON/CSV导出保留-0/+0/NaN/Infinity/BigInt，核心及FFI文件覆盖±Infinity等；完整GUI/平台数值矩阵不由列出的样本代替。 |
| C15 | A/B 交换 | 样本通过 | quality_matrix: 600 对 A/B 对称性（包含状态、两侧 DTO） |
| C16 | 同输入重复比较 | 样本通过 | quality_matrix: 600 对逐字重复输出一致 |
| C17 | 折叠/展开树 | 部分通过 / 完整GUI与键盘VoiceOver OPEN | 已有核心深树/身份样本；[d776当前新包GUI](evidence/2026-10-03-nested-batch-final-gui-proof.json)实际展开env.api.retries及happy.options.cache多层分支、数字/字符串叶子详情与15项计数，另有实际FFI分组身份/点号键回归；原[c487三行折叠/展开](evidence/2026-10-03-variable-tree-addendum-proof.json)保留为历史样本。完整特殊键/分页树/键盘/VoiceOver GUI仍OPEN。 |
| C18 | 搜索过滤后 | 样本通过 | quality_matrix 分页/搜索摘要；WorkspaceQuality 过滤保持汇总 |
| C19 | 不同名对象明确配对 | 样本通过 | quality_matrix: alpha/beta 单根相对路径配对 |
| C20 | 未知对象形状但已知字段相同 | 样本通过 | unknown_spread 保留 fixed + WorkspaceQuality 不完整诊断 |
| C21 | JSON 数字与 UTF-16 DTO 往返 | 样本通过 | TypedTreeTests 与实际包内 XPC self-test 核对嵌套 entries/items、机器路径、精确大整数、1e10000、-0、孤立 surrogate 键和值；JS BigInt/NaN/Infinity/undefined/空槽无损。仅证明列出的样本，不代表完整语言矩阵。 |
| C22 | 差异过滤与全相同判断 | 样本通过 | WorkspaceQuality: unknownDiagnosticsSurviveFilteringAndParseErrorCanRecover |
| J01 | 用户原始 devConfig/env/module.exports | 样本通过 | 手算七项 + global_mode 回归 + 独立导出根 |
| J02 | var/let/const 的受支持定义 | 样本通过 | var/let/const、hoisting/TDZ/conflict 回归 |
| J03 | 同文件已知简写属性 | 样本通过 | quality_matrix 简写 x 与已知展开覆盖顺序 |
| J04 | 简写属性缺绑定 | 样本通过 | scope_contracts：未知简写 NOT_COMPARABLE、已知字段 SAME、不完整与对应路径诊断。 |
| J05 | 已知对象展开 | 样本通过 | quality_matrix 已知展开覆盖顺序 |
| J06 | 未知对象展开 | 样本通过 | unknown_spread 回归；禁止不完整集合制造缺失 |
| J07 | 同名重复普通属性 | 样本通过 / 完整 UI OPEN | Rust duplicate_properties 4项、真实核心Swift状态/MCP、包内MCP及Node独立覆盖顺序；301警告完整报告。新包中英文位置警告、零匹配行与设置返回保留通过；大量警告的完整UI/无障碍仍待验。 |
| J08 | 已知后续属性赋值 | 样本通过 | assignment 左引用捕获、delete 与 alias 修改回归 |
| J09 | 别名修改 | 样本通过 | quality_matrix: 共享 alias 修改 env |
| J10 | module.exports 后 env 重绑定 | 样本通过 | contracts: export_reference_survives_binding_reassignment |
| J11 | exports 别名断开 | 样本通过 | quality_matrix: exports 别名断开不改 module.exports |
| J12 | 同样的 process.env 表达式 | 样本通过 | contracts: unknown_runtime_expressions_never_become_same |
| J13 | 未知函数修改 env | 样本通过 | contracts: opaque_call_can_rebind_a_root_and_must_not_leave_known_rows |
| J14 | getter/原型特殊语义 | 样本通过 | accessor 明确拒绝 + array prototype Unknown 回归 |
| J15 | 动态 import/require | 样本通过 | 当前打包 MCP/XPC 合成 require 文件写入/子进程和动态 import 模块副作用探针通过；无文件标记或本机连接，complete=false。有限样本；已纳入 scripts/check-mcp.py 常驻打包门禁。 |
| J16 | 嵌套作用域同名变量 | 样本通过 | scope_contracts：块/函数内同名变量保守失效，不保留假 SAME；内层变量不成为根，选内层根返回 ROOT_NOT_FOUND。不宣称支持嵌套声明语义。 |
| J17 | 语法错误、已知异常终止 | 样本通过 | parser/binding/readonly 回归 + WorkspaceQuality 错误恢复 |
| J18 | BOM、LF/CRLF、中文行号 | 本机模型通过 / 完整 GUI 与打包 worker OPEN | 文件→匿名 NSXPC→Workspace 的 BOM/无 BOM、LF/CRLF、中文警告／字节列／详情矩阵通过；首行 BOM 偏移与包内 XPC/MCP 复验通过。SwiftUI 渲染、VoiceOver、打包 worker 独立服务和设备矩阵仍待验，见[file-encoding-ui-quality](file-encoding-ui-quality.zh.md)。 |
| J19 | 恶意脚本含文件/网络/进程操作 | 样本通过 | 4个可信合成恶意表达式经打包 App→XPC→Rust 比较后，文件/进程/import 标记未创建，loopback连接0；未知调用后新已知值保留但整体不完整。 |
| J20 | 超深/超大/超时 | OPEN / 部分证据 | 188资源/深度探针已有；[真实匿名NSXPC默认30秒](evidence/2026-10-03-ipc-lifecycle-final-swift-http-tls-controller-tests.log)及重连通过。独立包内worker运行中退出、完整UI压力/内存/目标设备仍未齐。 |
| J21 | 未知条件重绑定后属性写入 | 样本通过 | unknown_control_flow、unsupported_expression 回归 |
| J22 | 未知调用后创建未逃逸新对象 | 样本通过 | scope_contracts：未知调用后的新对象恢复两项已知 SAME，但程序 complete=false，保留根级诊断。 |
| V01 | KV v1 与 v1 | 样本通过 | VaultFaultTests: v1 路由 + 原始精确响应；本机合成环境 |
| V02 | KV v2 与 v2 | 部分通过 | Rust8来源契约与Swift版本差异不进入业务diff、大版本精确、时间/计划删除和缺字段null样本；混合KV GUI来源已验。真实部署与全失败状态矩阵仍OPEN。 |
| V03 | 两侧 KV 版本不同 | 样本通过 / 实际部署OPEN | 同一App/MCPService比较KVv1/v2、双synthetic Token/namespace/mount/name，真实loopback端到端及新包四笔来源GUI；不冒充真实授权stdioVault部署。 |
| V04 | 相同配置、元数据不同 | 样本通过 | contracts: unwraps_vault_only_when_user_selects_the_format |
| V05 | namespace/mount 不同 | 样本通过 / 实际部署OPEN | 真实loopback两个Token/namespace/mount/name分别校验GET header和路径，App/MCPService及新包GUI通过；用户实际环境未连接。 |
| V06 | 只读单 secret、无 list 权限 | 样本通过 | VaultFaultTests: literal scope 预览/读取没有 LIST（v1/v2） |
| V07 | list 成功但某 secret 403 | 本机样本通过 / 真实部署及完整矩阵OPEN | 当前按整批失败规则验收；KVv1/v2后段403/404/503回归及新包B最后一笔403前3条成功、旧结果标记/禁用导出/重试恢复通过，不返回部分成功。见[c487实际GUI](evidence/2026-10-03-vault-stale-results-final-gui-proof.json)。 |
| V08 | 403、不同含义的404 | 样本通过 | VaultFaultTests: 401/403/404/429/500/503 + ambiguous/exact404 |
| V09 | 子目录列举失败 | 本机样本通过 / 真实部署及完整矩阵OPEN | KVv1/v2后段子目录403停止剩余LIST、不读secret、不返回部分plan；新包真实loopback后段B子目录403、精确8请求/无data读取、旧结果中英文标记/禁用读取与导出、恢复通过。见[c487实际GUI](evidence/2026-10-03-vault-stale-results-final-gui-proof.json)。 |
| V10 | foo 与 foo/ | 样本通过 | VaultFaultTests: vaultLeafAndSameNamedDirectoryStayDistinct |
| V11 | 已知软删除或销毁元数据 | 部分通过 / 全矩阵OPEN | HTTP状态传Rust，同次KVv2严格404包装+null业务体+合法版本/destroyed直接错误；Rust/Swift/真实HTTP及GUI删除/销毁整批失败、导出禁用、恢复通过。未知404仍错误；真实部署与完整失败来源UI未全量关闭。 |
| V12 | HTTP 重定向跨域/降级 | 部分通过 | HTTPTransportIntegration: 双 HTTP origin redirect 不转发；TLS 降级链未独立覆盖 |
| V13 | 非 KV 动态 engine | 样本通过 | dynamicEngine 及 mountMismatch 回归，识别后无 secret GET |
| V14 | mount 识别接口不可用 | 样本通过 | 识别 403/404/500 + path/version 不匹配停止；不猜 engine |
| V15 | 断网/限流/超时 | 部分通过 / 外部网络矩阵OPEN | 合成 Reader 已覆盖 KV v1/v2 的 403/404/429/503 中途失败、整批丢弃、停止后续读取和显式干净重试；真实断网/代理超时/自动退避策略仍未验证。 |
| V16 | 取消与晚到响应 | 部分通过 / GUI与打包worker OPEN | 合成传输覆盖取消后的迟到 data 回复，以及 Vault scope 变化后的 Workspace generation 丢弃；真实桌面、打包 worker 外部退出和网络传输矩阵仍未验证。 |
| V17 | 递归预算到达 | 样本通过 | VaultFaultTests: 深/宽目录、namespace、500 请求、20MiB；全批停止 |
| V18 | 读取期间源发生变化 | 部分通过 / 变更回退OPEN | 每条实际namespace/path/配对键/KV版本/时间、缺失null、每次本机读取区间随App/MCP/完整JSON；metadata不算业务diff、snapshotAtomic=false。实际读取中修改/回退/版本竞态仍需专门证明。 |
| V19 | 离线 JSON 业务字段 data.data | 样本通过 | scope_contracts：plain-object 保留 data.data.PORT 与 data.metadata.version 两条业务路径；明确 v1/v2 混合包装后才提取 PORT。 |
| V20 | 离线导入范围不全 | OPEN / 部分证据 | scope_contracts 验证 path-map 缺一个输入路径产生 ONLY_A；仅说明供应内容树，不推断 live inventory。导入来源与范围限制 UI 待补。 |
| V21 | 打开/编辑档案 | 样本通过 | WorkspaceQuality: 编辑和无预览 Run 的请求数为 0；preview 不读值 |
| V22 | 错误响应含敏感信息 | 部分通过 | VaultFaultTests 错误正文 synthetic-secret 不进入诊断；普通日志全矩阵仍待验 |
| V23 | JSON 重复 Key | 样本通过 | 核心嵌套/包装重复键 + live control JSON 重复键拒绝 |
| V24 | path-map schema/范围不符 | 样本通过 | scope_contracts：空路径、null/数组/标量条目、重复路径/字段、旧 scope/entries 包装及非对象根明确拒绝，没有伪造比较结果。 |
| V25 | 整个 secret 缺失/删除/无内容 | 部分通过 / 全矩阵OPEN | 已知deleted/destroyed直接失败、未确认404不作缺失、整批失败无新结果/无导出；不伪造成功来源或跳过条目。完整缺失/空业务体/失败来源矩阵仍待补。 |
| V26 | 离线缺少时间或版本 | 部分通过 / 全矩阵OPEN | 实际Workspace离线JSON导出不附加之前的直连来源或伪造时间/版本，精确业务数字保留且无新增HTTP；不同导入包装与完整GUI仍待补。 |
| V27 | Vault 两侧输入方式选择 | 部分通过 | App仍使用同一live/import选择器；live两侧KV版本/URL/Token/namespace/mount/name独立，混合实际loopback App/MCPService及GUI已验；两侧同时不同输入方式未新增承诺。 |
| U01 | 默认文件模式 | OPEN / 部分证据 | App 默认 env 离线已有实现；真实零联网观测需当前包复测。 |
| U02 | A/B 拖放和交换 | OPEN / 部分证据 | 交换按钮/快捷键已实现；实际核心控制器验证文件、标签、根、格式和差异方向移动，Vault 清确认/预览且零请求，busy/YAML/文件导入中不交换；异步替代导入、取消后旧成功/错误均不能覆盖新输入。实际拖放/键盘/交换 UI 仍待补。 |
| U03 | 只看差异 | 样本通过 | WorkspaceQuality: 状态过滤与 unknown 诊断保持 |
| U04 | 长值与多行 | 部分通过：长值GUI样本通过 | 实际新包表格有界预览、完整详情与真实JSON/CSV长值导出通过（中文/emoji/换行转义）；完整多行/键盘/滚动/无障碍矩阵仍待验。 |
| U05 | 大表列宽 | OPEN / 部分证据 | 当前 App 大表真实列宽/滚动/帧时间未验。 |
| U06 | 刷新中选中行 | 部分通过 / GUI OPEN | 新增取消选择/选中分组后晚到真实核心详情拒绝回填，先运行期失败后修复；分组选择与真实结果ID分开。刷新保留/焦点/滚动与GUI矩阵仍待补。 |
| U07 | 奶油白浅色、小窗口（用户最新要求） | 部分通过 / 实际桌面 OPEN | 用户要求所有页面浅色，旧深浅色条目属于历史范围；当前三尺寸全状态原生渲染及 Vault 最小窗口专项已有证据，真实桌面／滚动／键盘全矩阵继续待验，不恢复已取消的深色 UI。 |
| U08 | Reduce Motion / VoiceOver | OPEN / 部分证据 | Reduce Motion / VoiceOver 全键盘核心路径与动效录屏待验。 |
| U09 | 输入法与键盘 | OPEN / 部分证据 | 输入法组合态、全键盘焦点/查询专项待验。 |
| U10 | 复制 | OPEN / 部分证据 | 复制用完整 literal 已实现；真实剪贴板恢复/完整值验证待补。 |
| U11 | 导出缺失/未知/非普通数值 | 部分通过：实际非Vault导出样本通过 | 实际NSSavePanel完整/隐藏值/仅A JSON与CSV各3份通过，保留Missing/Unknown/特殊数字/类型/UTF-16及筛选身份；Vault来源装饰经实际Workspace/FFI/重编码/新文件的246行样本已验；不同来源完整GUI矩阵仍待验。 |
| U12 | CSV 公式样式内容 | 部分通过：真实GUI CSV样本通过 | 实际完整/隐藏值/仅A CSV共3份，标准库核对引用/逗号/控制转义/Unicode/CRLF及负数前缀；原核心8种ASCII/全角公式样式字符串矩阵继续通过。未证明所有电子表格保存再打开。 |
| U13 | 导出目标等于输入或别名 | 样本通过 | BridgeTests: symlink/hardlink/已有文件 O_EXCL 保护，原输入不变 |
| U14 | 输入/导出磁盘权限失败 | OPEN / 部分证据 | 文件缺失保留文本已测；真实描述符注入已验证部分写入及其他操作替换路径后不误删，EEXIST 错误类型准确；读/写权限、同步失败等完整矩阵仍待补。 |
| U15 | 重启 App | OPEN / 部分证据 | 禁用恢复与清 Token 已实现；当前包重启后无明文/无自动连接实测待补。 |
| U16 | 调试日志/崩溃报告 | OPEN / 部分证据 | 默认错误脱敏/MCP stderr/worker 权限已测；日志/崩溃附件完整审计待补。 |
| U17 | worker 异常退出 | 部分通过 / 包内运行中矩阵OPEN | [历史真实空闲worker首次恢复](evidence/2026-10-03-worker-recovery-addendum-proof.json)通过；[当前真实匿名NSXPC](evidence/2026-10-03-ipc-lifecycle-final-focused-proof.json)已测取消/中断/默认30秒/迟到回复与重连，不能替代独立包内worker运行中外部退出及完整GUI/压力。 |
| U18 | 干净 arm64 Mac | OPEN / 部分证据 | 需要干净 arm64 Mac 的安装/卸载/无工具链验证。 |
| U19 | 承诺支持的 Intel Mac | OPEN / 部分证据 | 需要承诺 Intel 原生构建与真机系统证据。 |
| U20 | 首次下载打开 | OPEN / 部分证据 | 需要 Developer ID、公证/stapling 与首次下载 Gatekeeper 真机验证。 |

## 性能、恶意输入与交付

| 门槛 | 状态与证据 |
| --- | --- |
| 性质与变异 | 固定种子 `0x5e20261003`；600 对标量独立预期/交换/确定性，1000 数字等价，2400 JS/JSON/YAML 变异；持续 fuzz/corpus 扩展仍 OPEN |
| 大输入与资源 | 当前 Release 核心样本每侧50001节点、十万结果，比较142.611ms、峰值RSS154599424字节；另有20MiB/节点/指数/alias回归。每侧十万节点、全包总内存与深度128全矩阵仍待补 |
| 冷启动 P95≤2秒 | 需参考硬件、Release、完整冷启动样本，不能拿构建耗时替代 |
| 搜索 P95≤100ms | 当前 Release 核心样本为十万结果、12 次预热与120次查询，P50 5.980ms/P95 7.013ms；不含 XPC/GUI，完整页面搜索门槛仍 OPEN |
| 滚动/长帧 | 需60Hz帧时间证据、不同列宽/值长度，不拿静态截图代替 |
| 取消/超时 | 网络立即/中途取消+重试、一般generation晚到回归已有；实际worker30秒/退出与完整UI取消预算待补 |
| 完整双评审 | 本轮仅复核当前网络读取/测试增量；最终全部实现与全量证据完成后还需两位接受同一候选 |
| 用户手册/支持矩阵 | README与计划存在；实际支持OS/架构/部署与完整错误帮助需最终登记 |
| License/NOTICE | [资源交付](license-delivery-quality.zh.md)已通过：新隔离测试包包含104第三方组件的166份原文及索引/收据/README，177包文件、离线来源校验、15项回归与同候选双接受通过。旧运行App未替换。实际链接范围、源码头许可正文是否需随包、法律兼容性及正式发行审核继续OPEN，不将dev/build/platform超集都视作已链接依赖。 |
| .app/ZIP/DMG | 当前 .app/ZIP 已核对二进制并通过解压后 codesign；正式签名 DMG/校验与干净设备安装待补 |
| 生产边界 | 所有自动测试使用合成loopback；没有真实Vault访问。真实连接验证只在用户已核实的非生产范围进行 |

继续顺序：先关闭模型复核指出的当前缺陷；随后补核心/适配器专门样本、真实XPC恢复/压力、完整GUI/键盘/可访问性与导出，最后处理目标设备/许可证/正式分发及已批准非生产部署证据。存在可做工作时继续，不把外部条件缺失当成整个任务停止的理由。

## 本轮恢复验证与审查状态

当前 cleanbuild 10条命令均 exit0：62 Rust、74 Swift、14 Python验证器负向测试；固定种子 Node 独立对照 Debug/Release 各 1152 对/4317 结果项，以及 Release 包内 XPC 与实际 stdio MCP。Node 只运行脚本生成的 9 类可信合成模板，不接受用户输入，也不进入交付包。9个HTTP/TLS测试全部实际运行，49必需请求路径存在；空记录/跳过/-O不会通过。源文件冻结结束时重新扫描，可检测新增/删除/修改。正常MCP验证从不查询钥匙串或调用凭证消耗工具；未访问真实Vault。新增 runtime HTTP 清单核验、MCP 启动失败退出码和常驻打包副作用探针通过；Python -O 下 14 个负向测试也通过。旧候选的本机HTTP/GUI/钥匙串集成属于历史证据，不能自动覆盖当前GUI冷启动。

当前GUI证据OPEN：最近ccaae0f7候选的Sky读取App路径及bundle ID均cgWindowNotFound；Finder在05:38:17 UTC成功捕获，后续打开测试App的Sky序列又出现ScreenCaptureKit -3811，未证明快捷键是否已执行或窗口数量/根因。最新8540e486的交互未执行，不继承历史GUI。同步入口与实际MCP/XPC已验证，[当前GUI状态](evidence/2026-10-03-tree-model-gui-status.json)仍不是通过证据。

历史网络读取候选 `cac794c6` review：[CC](evidence/2026-10-03-quality-final-cc.json)为ACCEPT_LOCAL_CHANGE，明确只涵盖该轮增量并要求运行证据。[DS事实复核](evidence/2026-10-03-quality-final-ds.json)为ACCEPT_LOCAL_CHANGE。DS第二稿NEEDS_CHANGES已保留；基于[Apple官方cancel文档](https://developer.apple.com/documentation/foundation/urlsessiontask/cancel%28%29?language=_8)的suspended task取消回调保证以及明确的每次操作预算，DS主动撤回错误P0和预算推测。第一次事实复核请求TLS EOF无结果，保留失败后重试同候选取得完整结果。这些结论不自动继承为最新候选接受。

历史 `7b1a5c3a` 增量评审：DS 首轮 NEEDS_CHANGES 及事实复核保留，撤回了当前 busy 方法守卫可被绕过、无 XPC 超时、BOM 比较差异等不符合源码或执行证据的判断；最终统一判定 ACCEPT_LOCAL_CHANGE，没有当前可到达 P0/P1。[CC 同一候选最终评审](evidence/2026-10-03-scope-files-final-cc.json)为 ACCEPT_LOCAL_CHANGE：外层 MCP 300 秒观察超时后，读取原 CLI session 的完整 end_turn 结果恢复，没有重启或继承旧候选接受。GUI 和正式分发仍 OPEN，完整目标没有完成。

冻结源文件不变时补充[实际打包副作用与类型探针](evidence/2026-10-03-scope-files-packaged-side-effect-and-types.json)：4个合成恶意调用零文件/进程/import标记与零本机连接；7个JS特殊类型经真实XPC/MCP无损，默认差异筛选不显示SAME，显式all分页才返回。首个探针未选择all而出现KeyError，属于测试驱动错误；更正调用后通过，产品源文件未改。这组实测不是常驻门禁脚本，也不等于完整GUI或全部JSON类型树矩阵。

已实查正式分发外部条件：当前Mac上有效Developer ID Application identity数量为0；已安装Rust目标含aarch64-apple-darwin，没有x86_64-apple-darwin。不能把ad-hoc包写成Developer ID/公证通过；尚有大量可执行测试，不因这些条件停止整体任务。

评审证据边界：历史 DS 将30次“立即取消”描述为覆盖attach前后时序，这超出测试实际断言，Codex不采纳该覆盖声明。它主要覆盖入口取消；确定性的register/attach/cancel交错和20MiB精确网络边界仍为待补项。历史 CC 提出的全部验证器AST回归、新文件冻结扫描已在本候选补齐；当前已使用 Swift 实际发现的 HTTP 方法清单代替源码宏正则，并验证 MCP 启动失败返回非零；复杂参数化/重载/自定义测试标题会保守失败，实际 GUI 条件仍为待办，局部接受不关闭这些质量事项。当前 InputFileTests 的20MiB精确文件边界不能冒充网络传输边界。


## 历史增量：完整类型树、导入生命周期与常驻验证（5e77bea4）

[48 文件清单](evidence/2026-10-03-dto-lifecycle-candidate.manifest.sha256)、[10 项规范验证](evidence/2026-10-03-dto-lifecycle-results.json)和[实际打包探针](evidence/2026-10-03-dto-lifecycle-packaged-boundary.json)属于当前候选，源文件逐项重新核对无变化。类型树与原始 BOM 偏移、文件失败保护、异步导入状态、HTTP runtime 清单、MCP 启动失败退出码均有专项回归。

[DS 独立评审](evidence/2026-10-03-dto-lifecycle-final-ds.json)为 ACCEPT_LOCAL_CHANGE，无 P0/P1；请求 deepseek-chat，实际返回 deepseek-flash。DS 关于导出需增加对话框后 generation 检查的 P2 建议与当前 Workspace.export 已有守卫不符，不重复实施。[CC 同一冻结候选评审](evidence/2026-10-03-dto-lifecycle-final-cc.json)也为 ACCEPT_LOCAL_CHANGE，无 P0/P1；实际核对48/48文件哈希及规范日志，没有重跑测试或做图形检查。两者仅接受本轮增量，整体目标仍未完成。

5e77bea4 双评审综合：两位均认可该轮类型树、BOM 原始定位、导入代际和验证器边界。CC 额外指出一般选项变化会同时作废两侧导入、导入中根检查仍可读取旧文本、JSON BOM 注释过时；这些 P2 在该候选尚未修复；后续修复见当前增量。DS 的保存对话框后 guard 建议已有源码反证，不当作当前缺陷。离线 Node oracle 的 Release/版本/corpus、完整 GUI 与设备发行门槛继续 OPEN。


## 历史增量：导入选项保护与 Release 独立对照（4758a507）

- 四个 Workspace 回归在旧代码共9处断言失败，修复后通过；选项变化保留两侧导入，内容编辑只作废被编辑侧。停止计算与取消导入分开；Esc/切换工具仍取消全部。导入中根检查方法和按钮都拦截。JSON BOM 注释已纠正，解析容忍范围不变。
- [规范验证](evidence/2026-10-03-import-oracle-results.json)：10条命令全部exit0，Rust62/Swift60/Python14，HTTP9、包内XPC/MCP通过；[48文件清单](evidence/2026-10-03-import-oracle-candidate.manifest.sha256)逐项核对不变。
- [独立 Node 对照](evidence/2026-10-03-import-oracle-js-oracle.json)：Debug/Release 各1152对4317项，五个可比较状态全部非零；加入79项TYPE_CHANGED，全部summary独立核对。固定corpus哈希、oracle源码哈希、二进制哈希、Node/Rust工具版本均记录。可信模板不执行未知外部代码，NOT_COMPARABLE由核心专项回归证明；不宣称持续fuzz或全JS语言完成。
- [Release 核心性能样本](evidence/2026-10-03-import-oracle-release-core-benchmark.json)附[可重跑驱动](evidence/2026-10-03-import-oracle-release-core-benchmark.py)：M3/24GiB、macOS26.5.2，双侧各50000字段、738891字节，十万结果；132次路径查询全部与独立预期匹配，剔除12次预热后P95为7.013ms。计时包含stdio与JSON解码，不含Swift/XPC/GUI。单次比较与峰值RSS仅为此样本，不能关闭所有资源门槛。
- [ZIP解压校验](evidence/2026-10-03-import-oracle-package-check.json)通过，当前主程序SHA与探针一致。GUI、全量语义/性能/无障碍、目标设备和正式分发仍 OPEN。
- [CC](evidence/2026-10-03-import-oracle-final-cc.json) 与 [DS](evidence/2026-10-03-import-oracle-final-ds.json) 均对当前同一候选 ACCEPT_LOCAL_CHANGE，无 P0/P1。CC 实际复算清单及48/48文件，未重跑测试；DS 只读所提供源码/证据，未本机复算，实际模型 deepseek-flash。首次 TLS 握手失败[记录](evidence/2026-10-03-import-oracle-initial-ds-failure.json)保留，进程终止后同候选重试获得结果。局部接受不关闭完整目标。

当前双评审综合：两位认可导入选项保护、根检查守卫和 Debug/Release 独立对照。CC 指出单独文件导入时 Esc 命令仍禁用（仅 busy 启用）及 SEED 在 Python/JS 两处重复常量；两项继续修复。DS 的“文件中9个@Test”计数不准确，该文件为7例，另2例位于WorkspaceTests；规范日志实际60例通过。DS未收到稍后新增的核心性能报告，其“无benchmark”只描述当次审阅材料，不抹去已归档性能样本，也不关闭GUI性能门槛。


## 历史增量：结果树、详情树与导入停止（c74e1d90）

- [51文件清单](evidence/2026-10-03-result-outline-candidate.manifest.sha256)与[十项完整本机门禁](evidence/2026-10-03-result-outline-results.json)：Rust62/Swift70（6套）/Python14、HTTP9、真实包内XPC/MCP与签名全部通过。
- 新增7个真实CABI树投影用例；机器身份不把UTF-16 key/index、点号键/嵌套键、孤立surrogate/replacement或不同Unicode编码序列合并。分页/过滤只组织当前页，单侧容器详情不重复计数，完整报告逐字不变。
- 导入停止、清选中后晚到详情、分组保留焦点但拒绝旧字段详情共3个控制器回归；树/停止新API先产生明确缺失成员编译错误，晚到详情旧代码真实失败1处断言，修复后17个专项全部通过。编译红与运行期语义红分开记录。
- 真正包内XPC self-test断言2组4结果/2差异和JSON容器详情树的UTF-16/精确数字；详情列表固定240pt、逐层子项、cell仅240UnicodeScalar预览。树模型构造/巨型容器帧时间仍待测，不能拿Rust核心基线冒充GUI性能。
- [当前ZIP解压校验](evidence/2026-10-03-result-outline-package-check.json)通过；[当前GUI记录](evidence/2026-10-03-result-outline-gui-status.json)仍未通过：旧测试PID90836精确核对后终止，新包路径读取timeout、bundle ID读取cgWindowNotFound；Finder也出现ScreenCaptureKit -3811。不能推断App零窗口或源代码根因。
- [CC 最终结果](evidence/2026-10-03-result-outline-final-cc.json)与[DS 最终结果](evidence/2026-10-03-result-outline-final-ds.json)均为同候选 ACCEPT_LOCAL_CHANGE，无P0/P1。CC 实际复算51/51文件，原调用正常完成、未超时；DS 请求deepseek-chat、实际返回deepseek-flash，未本机复算清单或重跑门禁。
- 双评审综合：两位认可当前页树/详情树、机器身份、计数与报告契约、停止导入入口以及旧详情拒绝。CC 提出的导入单独停止清掉已有有效结果、选择失效仍依赖视图回调、Unicode分组与核心显示写法不一致，列为下一增量修复。两位的大树构造性能建议继续OPEN；CC所称200行开销可忽略、稳定ID保证展开状态不丢仅为推断，未作为测量或GUI证明。DS数字键与索引显示相同的措辞与其自身不同字符串示例矛盾，已有正向不等断言，不添加等价反向断言。完整目标仍active，真实GUI/无障碍/设备/发行继续OPEN。


## 历史增量：取消导入保留结果与模型选择失效（ccaae0f7）

- [51文件冻结清单](evidence/2026-10-03-import-preservation-candidate.manifest.sha256)与[十项规范门禁](evidence/2026-10-03-import-preservation-results.json)：Rust62/Swift73（6套）/Python14、HTTP9、包内XPC/MCP与签名全部通过。
- 仅有文件导入时停止，保留有效session/rows/summary/selection/detail及YAML输出；switchTool仍明确清全部旧结果。两侧导入令牌作废，旧成功/失败不能覆盖输入。计算与导入同时运行仍停止两者。
- selected直接改为nil或另一个ID立即使selectionToken失效并清detail，无需SwiftUI触发inspectSelection；同ID赋值保留现有详情。分组选择仍独立于真实结果ID。
- [运行期红](evidence/2026-10-03-import-preservation-red.log)4项实测8处失败；[专项绿](evidence/2026-10-03-import-preservation-focused-green.log)14项通过。实际CABI比较后另查$.y成功证明仍有可用会话；真实YAML输出在取消导入后保持有效。清选择测试去掉视图回调，新增切另一字段迟到回复拒绝；switchTool测试扩充已有结果断言。
- [新ZIP解压核验](evidence/2026-10-03-import-preservation-package-check.json)通过。[CC](evidence/2026-10-03-import-preservation-final-cc.json)与[DS](evidence/2026-10-03-import-preservation-final-ds.json)均独立ACCEPT_LOCAL_CHANGE，无P0/P1；CC复算51/51文件并正常完成，DS实际deepseek-flash、未在本机重跑门禁。接受结果与GUI/性能证据分开记录，不继承c74历史接受。Unicode分组显示和大树性能仍待处理。


本轮双评审综合：两位认可只停导入保留有效结果、工具切换清旧结果和selected同步失效。CC新增的P2包括已有error=true时停止提示仍为错误样式、后台文件读取只丢弃回调未主动终止、busy+import专门取消用例和红测试文本快照。红阶段后仅加强了既有switchTool用例，四项红回归的断言未修改；仍不能声称保存了红阶段最终测试全文的hash。后续轮次保存红阶段快照。DS“两个导入都pending才保留”的措辞不准确：源码importing为A||B，两项新增用例均只有A导入；刷新令牌本身也不额外发送请求。CC“两项CABI均再查rows”措辞不准确：仅比较用例再查询$.y，YAML用例验证输出和stale。以上事实修正不改变接受结果，也不扩大证据范围。


## 历史增量：深层树性能与小线程栈恢复（8540e486）

- [51文件清单](evidence/2026-10-03-tree-model-final-candidate.manifest.sha256)与[十项完整本机门禁](evidence/2026-10-03-tree-model-final-results.json)全部通过：Rust62 / Swift74（6套）/ Python14、HTTP9、Debug/Release Node1152对/4317项、真实包内XPC/MCP/签名。
- Branch缓存每条显示前缀，不再为每组从根重复拼接；机器路径、行路径、身份、顺序及计数不变。freeze改显式后序遍历，防递归在小栈耗尽。新增真实CABI深度120×200枝测试：24000不同节点、200真实结果、每组计数1、所有前缀及叶路径正确，报告逐字不变。
- [失败门禁](evidence/2026-10-03-tree-model-failed-results.json)与[阶段红](evidence/2026-10-03-tree-model-deep-staged-red-2.log)保留：signal10发生在树投影，ffi/DTO/report已返回；实际线程栈536576字节。仅改迭代freeze后，同一[红测试源码快照](evidence/2026-10-03-tree-model-staged-red-tests.swift)和线程[8例绿](evidence/2026-10-03-tree-model-deep-staged-green.log)通过，[证据hash](evidence/2026-10-03-tree-model-crash-proof.json)一致；最终去掉临时诊断后完整74例仍通过。LLDB被系统拒绝attach，不更改权限，不声称取得调用栈。
- [旧基线](evidence/2026-10-03-tree-model-baseline.json)、[性能红](evidence/2026-10-03-tree-model-performance-red.json)、[首版缓存](evidence/2026-10-03-tree-model-optimized.json)和[最终复跑](evidence/2026-10-03-tree-model-final-benchmark.json)区分：200×120互异前缀，P95从1332.22175ms到最终60.376416ms；浅200为0.347084ms，共享深枝2.426833ms，50000详情一层7.222ms。5次预热、30次计时，包含构造/返回值释放；DTO解码不计入时间。参考主机纯Swift -O默认部署target，未控制负载，开发模型100ms预算不代替App14-target或完整GUI性能。探针RSS267059200字节包含全部fixture/DTO分配，不能称App内存通过。附[可复跑脚本](evidence/2026-10-03-tree-model-benchmark.py)与[Swift驱动](evidence/2026-10-03-tree-model-benchmark.swift)。
- [追加包内深层MCP→XPC](evidence/2026-10-03-tree-model-final-deep-packaged-mcp-check.json)：每侧242500字节可信合成env.js，200结果、深度120、完整路径全部匹配，默认值为占位，随后小比较可用，EOF0/stderr空。单次耗时1.021秒不是性能验收。首次探针误要求display键不存在而失败，实际脱敏契约为占位；[原失败](evidence/2026-10-03-tree-model-deep-mcp-first-failure.log)保留，修正探针后通过，不归为产品泄露。
- [ZIP解压核验](evidence/2026-10-03-tree-model-final-package-check.json)通过。[CC最终结果](evidence/2026-10-03-tree-model-final-cc.json)与[DS最终结果](evidence/2026-10-03-tree-model-final-ds.json)均独立ACCEPT_LOCAL_CHANGE，无P0/P1；CC复算51/51并正常完成、未超时，DS请求deepseek-chat实际deepseek-flash。当前源码接受不继承ccaae历史结果。GUI/VoiceOver/完整帧时间、深度128全矩阵、设备/发行和真实非生产部署仍OPEN。


8540e486双评审综合：两位认可显示前缀复用、显式后序freeze、原机器身份/顺序/计数/报告契约及深层红绿证据。CC以树仅单父、后序先子后父、对象仍被持有证明ready强制解包不变量；DS提出guard/将来DAG的建议，不是当前可达缺陷，也不扩展本工具为DAG。CC提示浅页增加不足1ms、128/129边界、递归析构更小栈、按根顺序明确断言和帧时间待补；保留为下一质量增量。DS仅通过API收到三份范围源码与选定证据文本，无本机文件工具；它自称读取本机manifest/通配目录的措辞不作为独立复算事实，候选hash由提示提供。DS“默认拒绝MainActor”不是代码机制：实际测试没有加MainActor，536576字节线程仅诊断样本。最后结果不继承旧候选接受，不关闭整个目标。


## 新增需求与最新开发验证

用户新增双语、可扩展设置页、本机显示名称、默认头像、主题。主计划已更新1.4；原91用例/设备/性能/无障碍门槛保留。设置10项专项已通过，实际GUI/新包/同候选双评审待执行，不能以控制器测试替代界面证明。

[设置设计](superpowers/specs/2026-10-03-settings-and-language.zh.md)、[设置专项证据](evidence/2026-10-03-settings-focused-proof.json)、[上轮完整资源门禁](evidence/2026-10-03-regex-budget-final-results.json)和[188项深度/预算矩阵](evidence/2026-10-03-regex-budget-final-depth-guards.json)分别记录新增实现和历史已完成验证。128/129JSON/JS/YAML及完整DTO小栈回归、百万层恶意JS/JSON/YAML有控制失败、正则2376预算相位、99000合法宽配置已补；完整App内存、worker超时/退出与UI性能仍OPEN。

GUI已在ea057候选恢复：确认旧进程退出后新进程出现实际窗口；外层观察超时后重读同一App，没有因超时重启。env.js小样本、树展开/折叠、键盘选择详情及YAML2/4空格保留样本通过。此证据不含设置功能，不代表完整GUI/VoiceOver通过；更早的捕获失败说明属于历史，不继续把它描述为最新一直无窗口。

## 历史全窗口设置样本（82689fe0，进一步原生保护前）

设置覆盖整个窗口，只保留自己的分类，左上角有返回按钮。工具视图保活，隐藏时忽略其无障碍子树并撤销编辑器焦点；工具打开/运行/交换/清空菜单禁用，设置期间停止菜单禁用，Esc只返回，避免把返回当成取消计算。新候选的[12项门禁](evidence/2026-10-03-settings-full-page-results.json)、[打包核验](evidence/2026-10-03-settings-full-page-package-check.json)、[实际GUI样本](evidence/2026-10-03-settings-full-page-gui-proof.json)均有自己的候选哈希。旧7b26211b双接受与第一版2a6751c5无障碍标签残留失败完整保留，不继承接受。

新候选英文GUI验证真实包内XPC结果total5/same2/差异3、从B编辑器快捷键进入设置、无隐藏控件/标签、隐藏输入不收字符、工具菜单禁用、返回后原配置及结果保留，以及8头像/现有名称。用户同时操作页面导致两次中文选择被工具拒绝，随后结束GUI操作并保留当前个人资料页面；本轮中文GUI、系统主题回退、真实IME、undo/滚动及VoiceOver完整矩阵仍明确未验，不用历史截图替代。

## 最新全窗口设置与原生输入隔离（c937450f）

[117文件清单](evidence/2026-10-03-settings-full-page-final-candidate.manifest.sha256)绑定[12门禁](evidence/2026-10-03-settings-full-page-final-results.json)、[包](evidence/2026-10-03-settings-full-page-final-package-check.json)、[实际GUI](evidence/2026-10-03-settings-full-page-final-gui-proof.json)。Rust70、Swift91/9套、Python16以及既有HTTP/TLS、Node、188资源探针、XPC/MCP全部通过；[12设置专项](evidence/2026-10-03-settings-full-page-native-proof.json)区分工具链错误、缺API编译红和最终绿，不冒称隐藏输入曾真实修改配置。

最新包实际启动PID21896，全窗口设置只有自己的分类和顶部返回。英语与简体中文切换，以及Esc/顶部按钮返回均保留合成配置原文、total5、difference3；隐藏工具不在完整AX树。原生协议输入/标记/焦点和选区在自动测试验证；真实GUI多窗口、全Tab循环、IME、undo/滚动、VoiceOver和系统主题回退仍OPEN。[CC](evidence/2026-10-03-settings-full-page-final-cc.json)和[DS](evidence/2026-10-03-settings-full-page-final-ds-deepseek.json)已对同一c937冻结代码独立接受，意见分歧见[综合记录](evidence/2026-10-03-settings-full-page-final-review-synthesis.json)，不继承82689fe0的不同结论。CC的原会话在外层300秒超时后恢复完整终态，未重启或臆测未捕获退出码。

追加[无显示窗口的原生协议探针](evidence/2026-10-03-settings-premarked-probe-proof.json)：先建立marked text再禁用，文本不变且拒绝焦点，但marked状态仍在。它只测试隔离进程中的原生对象，不操纵用户窗口，不代替真实GUI输入法流程。进入设置前已有组合的提交/保留规则与专项回归仍需完成；不改写DS原始非阻塞P2结论，不据此宣称整体输入法验收。


## 主题回退、已有组合与 J07 源码警告（4465692c）

[120文件冻结清单](evidence/2026-10-03-appearance-source-warnings-candidate.manifest.sha256)、[12门禁](evidence/2026-10-03-appearance-source-warnings-results.json)和[最终源码/包完整性](evidence/2026-10-03-appearance-source-warnings-post-review-integrity.json)绑定同一版本。Rust74、Swift96/10套、Python16、HTTP9、可信Node1152对双profile、188资源探针、签名/XPC/MCP通过；[专项记录](evidence/2026-10-03-appearance-source-warnings-focused-proof.json)明确测试作者编译错误不作为功能红。

旧c937包的[真实主题GUI红](evidence/2026-10-03-appearance-source-warnings-old-theme-gui-red.json)是Dark→System时正文仍深；当前[新包GUI](evidence/2026-10-03-appearance-source-warnings-gui-proof.json)验证内容与标题栏同时回浅，并保留中英文警告、原输入和total2/same2。原生已有组合结束标记且可见原文不变，恢复选区夹取；这是非显示AppKit对象测试，真实IME门槛仍OPEN。[301警告GUI](evidence/2026-10-03-appearance-source-warnings-overflow-gui-proof.json)补前200项限制与完整JSON提示；不宣称VoiceOver全量通过。

[CC原会话终态](evidence/2026-10-03-appearance-source-warnings-cc.json)与[DS原响应](evidence/2026-10-03-appearance-source-warnings-ds-deepseek.json)独立接受同一冻结源，完整目标仍active。[综合记录](evidence/2026-10-03-appearance-source-warnings-review-synthesis.json)区分模型观察与核实事实。CC首次调用因CLI无prompt退出1，无评审；修正参数后原88306会话外层300秒超时，随后恢复09:05:17UTC end_turn，不重启，未虚构CLI退出码。CC核对源码/证据hash而未跑完整测试或目视截图；DS仅阅读所给全文与证据，未自行核对本机hash，其原始措辞不得写成已本机验证。

继续优先处理：warning独立条数/字节预算及MCP大响应，花括号孤立surrogate转义、单CR/U+2028/U+2029定位；再补多窗口显示名称同步、真实输入法/无障碍和完整GUI。warning目前只有静态求值到的对象字面量会报告，未走分支和未知调用内部不做AST lint。交换后的旧警告仍属于过期结果，需要清晰呈现。[60000定义压力样本](evidence/2026-10-03-appearance-source-warnings-dense-probe.json)返回119998条/23.65MB响应，Release核心约0.218秒、子进程峰值173.60MB；仅核心CLI样本，不关闭App内存/完整资源门槛。DS的超预算数字“假SAME”已由[实际只读探针](evidence/2026-10-03-appearance-source-warnings-ds-observation-probes.json)否定：JSON解析先返回RESOURCE_LIMIT；TypedNode引用索引由解码器内部生成，不是外部JSON可提供的索引。

## Vault 逐条来源与严格删除语义增量（e84a5f23）

2026-10-03 · 1.7 当前来源增量：冻结候选 `e84a5f23b1f8a9e7c1f765b23ccbc3168fac3567e5ec5d04715751aff087b64f`（127文件）的[12项本机门禁](evidence/2026-10-03-vault-provenance-final-results.json)通过（Rust93 / Swift114 / Python17，共224项），真实HTTP/TLS11例、Debug/Release可信Node对照、188资源探针、包内XPC/stdioMCP继续通过。[新包GUI](evidence/2026-10-03-vault-provenance-final-gui-proof.json)验证混合KV、四笔来源、KVv1未知、KVv2计划删除可读、右侧展开不挤压表格、中英文整页设置返回、完整JSON来源、已删除/销毁/未确认404整批失败及恢复；重预览/重读取不保留旧行来源，原用户三行多变量结果已恢复。[包核验](evidence/2026-10-03-vault-provenance-final-package-check.json)通过。[CC/DS同一新候选独立接受](evidence/2026-10-03-vault-provenance-final-review-synthesis.json)；只接受本增量，完整91项、读期间修改/回退、真实非生产部署、完整GUI/IME/VoiceOver/性能、目标设备与正式发行仍OPEN。没有真实Vault或生产访问。

CC/DS的初次设计讨论只决定实现方向，不是接受。3ac4候选双方曾接受本增量，但CC发现旧行来源在stale/busy仍可见；新增真实运行期回归3处失败后清详情/选择并增加视图守卫，再执行新候选完整门禁/GUI/独立双评审，不继承旧接受。新增操作层缺httpStatus、403、KVv1+404负向回归，均不输出业务值或元数据。DS旧轮NEEDS_CHANGES与自身无阻断描述矛盾，原响应和同候选澄清均保留；任何最新接受以当前冻结候选实际结果为准。


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

完整剪贴板复制/恢复尚未执行；原始用户输入通过编辑器设置恢复，未点击复制按钮，原剪贴板各格式及内容的恢复未验证。Vault加入来源装饰后的JSON重编码、更多GUI/IME/VoiceOver/性能、真实worker恢复、干净目标设备、已批准的真实非生产Vault与正式发行仍OPEN。两位提出的逐run隔离历史旁侧日志、目录fsync及证据落盘失败时保留原诊断等非阻塞建议留在综合记录；不由局部接受宣称100%。没有真实Vault或生产访问，没有执行用户JS。

评审后的补充界面核对：已退出本轮解压测试App，恢复主路径App的原始A/B代码，两侧均为“全部变量”，状态选择“全部”，一次显示 `env.x`、`env.y`、`happy.x` 三行。`happy.x` 引用未声明的 `y`，明确为无法比较；已知的 `env` 继续正常比较。[实际AX记录](evidence/2026-10-03-verifier-status-final-canonical-app-restored.ax.txt)与[截图](evidence/2026-10-03-verifier-status-final-canonical-app-restored.jpeg)为本机追加证据，两位评审未重演此次操作。源码、门禁与包的完整性再次核对通过。


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

# Vault 下拉发现与批量比较

本次落实「只先填写链接与 Token，再选择选项」。现有 SwiftUI/AppKit、XPC 和 Rust 架构不变；比较算法、env.js、YAML、MCP 授权边界不改。源代码与可运行包均已更新，当前正在使用的 App 未被关闭或替换。

## 使用方式

1. A/B 各自输入 HTTPS Vault 服务根、`/ui/` 首页或 secret 网页链接及 Token；确认实际来源和 namespace 范围为非生产，再点击「读取选项」。输入本身不会触发联网。
2. 选择真实返回的 namespace 与 KV mount。namespace 菜单列出当前确认根和直属子 namespace；选子 namespace 会清除原选项与确认状态，提示重新确认并读取该 namespace 的选项。更深层或跨多个 namespace 的已确认范围可在高级设置中用 `*` / `**` 指定。
3. 点击「读取配置名称」，选择从 LIST 得到的名称，目录范围选「全部目录」即可一次比较 auth、payment、promotion 及子目录下的同名配置。这里的 auth 等是 KV 目录，与 Vault Enterprise namespace 分开处理。
4. A/B 的地址、Token、mount、namespace 根、配置名称均独立；例如 A 的 `uat-swim` 与 B 的另一名称按相对 namespace／目录配对。每侧仍只选一个 mount。
5. 点击「预览匹配范围」，核对真实清单，再「读取并比较」。目录与配置名称发现只读取名称和路径，尚未取得 secret 值；读取失败不会伪装成空结果、缺失或全部相同。

没有发现接口或 LIST 权限时，明确报错并展开高级设置，保留手工输入。可以直接指定目录与名称，把目录匹配设为 `.`；仍须有定向 mount 识别和 secret GET 权限。namespace 列举不可用时保留当前 namespace 与可见 mount 并显示提示，不要求管理员权限。

链接中的 mount／名称仅作为经过服务器返回验证的选择提示，不自动选第一个 mount；名称提示只能用于链接对应的 mount。secret 网页链接带 `?namespace=` 时，若与当前 namespace 不同，联网前拒绝，按提示在高级设置点击「拆解链接」后重新确认。重复或非法 namespace 参数拒绝；服务根／首页不支持 query。自动拆解不联网。

重新读取名称遵循当前已确认的目录／namespace 匹配，不自动扩大范围。因此先选具体目录再刷新只得到这个目录的选项；若需要重新列举全部目录，先在高级设置把目录匹配设为 `**` 再读取名称。

## 本次修改

| 文件／组件 | 作用 |
| --- | --- |
| `VaultDiscovery.swift`、`VaultModels.swift` | 连接发现输入、无凭证选项 DTO、首页与 namespace 链接校验 |
| `VaultReader.swift` | KV mount 可见列表、namespace 与目录 LIST、名称去重／目录关联、KV 版本严格识别、生产路径排除与预算 |
| `Workspace.swift` | 两侧独立发现、输入变化失效、取消与晚到回复防护、链接提示、范围重新确认提示 |
| `VaultConnectionPanel.swift`、`ConfigCompareApp.swift`、`AppPreferences.swift` | 双语下拉界面、折叠高级设置、现有流程接线 |
| `AppEntry/main.swift`、`PackagedSelfTest.swift` | 包内 XPC 自测直接走命令行，不创建 SwiftUI App 场景；原断言保留 |
| `Package.swift`、测试辅助窗口及测试文件、`test-cli-entry.py`、`verify-local.py` | 新增回归／布局验证、既有测试后台执行、完整校验入口 |

完整改动清单与冻结源码 SHA 见同目录证据索引。没有修改 Rust 比较核心。

## 检查证据

冻结源码：`a97afa130311d4ce77ce1d96ba8a5d4e22b0b10bdd98f2a21347a0c9a8aacc26`，328 个源码文件，22 个变更文件。完整本机 gate RunID `ee8ab5ca-ba60-4078-8aa7-01f7fe008e79`，15/15 命令成功、源码清单前后一致。

| 检查 | 实际结果 |
| --- | --- |
| Swift 完整运行及发现清单逐项核对 | 227 项，28 个 suite，0 失败／遗漏 |
| Rust fmt、clippy、全部测试 | 成功；95 项测试通过 |
| CLI 路由／验证器负例／第三方文本 | 5／52／15 项测试通过 |
| 独立 JS oracle、类型化 JSON／CSV、深度预算 | 成功 |
| 实际 URLSession HTTP／TLS | 11 个用例；仅 loopback，重定向落点 0，Cookie 请求 0，不修改信任 |
| Release 构建、开发签名、包内 XPC、实际包内 MCP | 成功；主进程打包自测窗口数 0 |
| 新包复制、ZIP 解压、完整文件字节与可执行权限、签名／资源／XPC 再消费 | 10 项交付检查成功，181 个文件一致 |

端到端合成 Vault 测试覆盖 A=KV v2／B=KV v1、不同配置名、auth／auth/nested／payment／promotion 四组实际配对，再通过真实 Rust FFI 得到 8 项、4 个类型变化、4 个相同、0 仅 A／B。来源并非真实部署。

新增回归保留实际失败记录。最初完整 gate 因参数化测试与严格运行清单格式不符失败；改回无参数测试、内部仍执行全部参数情况，未放宽校验器。修订测试一次遗漏 Xcode 环境导致 Testing 模块不可用，纠正工具链后才验证业务失败；两条测试请求头预期也纠正为现有 `namespace/` 格式。上述失败均保留。

证据：[完整 gate](evidence/vault-dropdown-discovery/verification/results.json)、[网络／Swift](evidence/vault-dropdown-discovery/network-check.json)、[合入完整性](evidence/vault-dropdown-discovery/post-review-integrity.json)、[交付包](evidence/vault-dropdown-discovery/package-check.json)。

新包：[Config Compare Vault Discovery.app](../build/Config%20Compare%20Vault%20Discovery.app)，[ZIP](../build/Config%20Compare%20Vault%20Discovery.zip)。新包没有自动打开，也没有正式公证。

原生布局检查中英文各三个尺寸：1280×800、1440×900、1720×1000，覆盖初始简化表单、已发现下拉和展开高级设置。共 12 张受控 NSHostingView 位图，不是操作系统桌面截图；人工查看最终英语 1440 简化、中文 1280 高级及中文 1720 简化图。高级表单使用现有滚动区域，较小窗口不会为容纳字段压掉结果区域。

不弹出测试界面：布局／编辑器测试窗口不呈现、不取得焦点。独立原生鼠标测试需要 WindowServer 的事件路由，使用透明、置于所有普通窗口下、忽略实际鼠标、拒绝 key/main 的自有窗口，仍发送真实 NSApplication 鼠标事件并使用原生 field editor。它不是「零窗口对象」；打包 XPC 自测才记录主进程窗口数为 0。没有打开、关闭、切换或重新启动用户 App。

## 独立评审

Claude Code（实际模型 `claude-opus-5-5[1m]`，session `215836bc-3ea6-43ee-b91c-bfb5095b4541`）与 DeepSeek（请求 `deepseek-chat`，实际返回 `deepseek-flash`）独立审查同一最终 SHA `a97afa130311d4ce77ce1d96ba8a5d4e22b0b10bdd98f2a21347a0c9a8aacc26`，均为 `ACCEPT`，没有阻塞意见。

两位一致接受受限只读发现、逐侧失效与批量配对；测试由 Codex 实际运行，评审本身不冒充测试或真实部署证明。非阻塞建议及各自证据限制完整保留，Codex 的结论只接受本项本地增量。

DeepSeek 曾对最终 SHA 提出阻塞意见。Codex 对照固定 plan.secrets 读取、mount 菜单清空名称、高级按钮非空 mount 的外层条件，并明确透明 WindowServer 测试面与用户桌面验收的区别，提交源码事实复核。过程中一次 API 请求 URLError，不计为接受；最终裁决与先前意见、澄清请求均保留于 review-clarifications。此澄清没有改动冻结源码或放宽测试门槛。

[Claude 原文](evidence/vault-dropdown-discovery/boundary-review-claude.json)、[DeepSeek 原文](evidence/vault-dropdown-discovery/boundary-review-deepseek.json)、[综合结论](evidence/vault-dropdown-discovery/review-synthesis.json)。

首个已接受候选之后继续修正了 namespace 参数、切换范围提示、不同 mount 的名称提示和过期加载提示；保留对应实际失败与通过记录，并对最终冻结代码重跑完整检查、重新提交两位评审。本次接受仅覆盖这项增量，不代表此前暂停的全部项目质量目标完成。

## 边界与未验证内容

没有连接任何真实 Vault、生产环境，也没有使用截图中的实际 Token。HTTP/TLS 测试仅用自有临时 loopback 服务，其余 Vault 发现／批量用例使用明确的合成响应；真实部署的内部 mount 接口、Enterprise namespace、Token ACL 兼容性尚未验证。已确认范围依赖用户核实非生产来源，URL 名称与勾选本身不能证明环境身份。

生产识别沿用独立词段 `prod` / `production` / `prd`，不是任意子串匹配；含已知标识的 mount、目录、名称不作为选项、不进入递归或配置读取。无法表示的 mount 名称和非法响应会让本次发现失败并提示手工回退，避免将不完整清单冒充完整扫描。多 namespace 通配范围遇到生产 namespace 仍整批拒绝，需收窄已确认根。

网络仅允许明确的可见 mount GET、定向 KV 识别、namespace／KV 路径 LIST 和确认后的 secret GET；重定向、Cookie、动态 engine、写入等原边界保留。发现 DTO 不带 Token；MCP 不接收新 URL／Token，不因发现选项自动授权或扩大既有授权。

本地 arm64/macOS 检查不等于全设备支持、OS 桌面交互或正式分发验收。新包是本地开发签名，未公证；没有自动打开。此前独立的编辑器绘制／性能调查不在本次合并范围。

网页链接目前只覆盖上文的服务根、`/ui` 首页和项目已有 secret 路由；其他 UI 路由／变体尚未验证，遇到拒绝时使用服务根及下拉或高级手动范围。namespace LIST 的 `404 {"errors":[]}` 当前按空子 namespace 处理，不能据此证明部署是否支持 namespace；其他已识别的列举不可用错误会显示提示。这些限制与评审的其余非阻塞建议保留在评审记录中。

# 测试完成记录与自有进程组清理

> 最新[许可证／NOTICE资源交付](license-delivery-quality.zh.md)：0fd389候选315项源码、14门禁／361项命名测试、105份原生渲染、新包177文件及同候选CC／DS独立源码接受通过；仅开发构建与本地资源增量已合入。当前App与输入保留，完整目标／正式发行仍active。

2026-10-04。本增量沿用已经落地的奶油白、草莓粉、马卡龙与本地白鹅原生界面，不修改产品页面、比较算法、编辑器、网络行为或 MCP。完整目标仍 active。

[候选清单](evidence/run-lifecycle-quality/candidate.manifest.sha256)、[旧进程树原始证据](evidence/run-lifecycle-quality/process-tree-probe/result.json)、[时长红灯](evidence/run-lifecycle-quality/duration-red.log)、[真实进程红灯](evidence/run-lifecycle-quality/owned-process-red.log)、[结束／中断／阶段红灯](evidence/run-lifecycle-quality/finish-interrupt-stage-red.log)及[52项绿灯](evidence/run-lifecycle-quality/all-verifiers-first-green.log)均保留。

## 实际问题与修复

实际合成进程树证明，旧 subprocess.run 超时约一秒返回后，外层 rtk 已退出，但它的 Python 父进程和子进程仍存活；正常退出同样能留下后台子进程。最初“会等约五秒”的推断已由实测否定并纠正，不能作为缺陷事实。该证据只来自有限生命周期的自有合成进程，不证明此前 Swift 超时有实际残留。

check-network.py 为每次主测试／清单调用建立独立会话。正常完成、超时及中断均清理该次进程组：先 TERM，最多等待一秒，再 KILL；保留已收到的日志并传播原失败。不会向调用者进程组、当前 App 或其他进程组发送信号。另一个进程组持有管道时，日志收尾有界，但不跨组清理；这不是任意后代或完整 App 生命周期验收。

Swift Testing 的通过行限定非负数值秒数和精确结束文本，并识别／拒绝已知问题符号。真实 SDK 的已知问题输出使用 ━，旧版本已因缺少普通成功结尾而失败，不能宣称该原生用例曾假通过；独立损坏输出证明旧版本会接受带“known issue/warning”的 ✔ 行、无效时长以及普通结尾后的 ━ 事件。

运行记录保留 primary、discovery、validation 三种失败阶段，以及实际主测试和发现清单退出码。清单失败不会把主测试真实的退出0丢掉；主测试失败不发起发现清单，验证失败不记成功。

## 回归与验证

新增10项命名回归，Python从42增至52；3个既有捕获测试改用真实 rtk 与合成 Swift 可执行接口。自有进程树、TERM抵抗、正常退出与 SIGINT 实际执行，并只检查自己发布的 PID／状态。失败阶段测试使用真实临时 loopback 服务与 OpenSSL，只有 Swift 接口是合成边界。

[13项完整门禁](evidence/run-lifecycle-quality/verification/results.json)通过，运行ID `71881260-3257-4aef-915f-f1e4e3005d50`，143文件起止清单一致。Rust95＋Swift198／24套＋Python52＝[345项命名测试](evidence/run-lifecycle-quality/test-counts.json)，条件断言和重复运行不累加。Swift主测试和发现清单实际退出0，整套冷构建与捕获184.457秒；[HTTP／TLS](evidence/run-lifecycle-quality/network-check.json)11项、71个loopback GET，没有生产、真实Vault、真实Token、重定向、Cookie或信任改动。[原生绑定](evidence/run-lifecycle-quality/native-bindings.json)完成中英文32条断言，不算32项命名测试。

[105份原生图像及7份实际查看](evidence/run-lifecycle-quality/visual-proof.json)覆盖三尺寸19状态57整页、4独立编辑器、44 Vault初始／菜单计划及四尺寸滚动结果。Vault额外检查1050×700，中英文原生程序滚动字段／结果可达；其他页面最低1280。整页TextKit绘制层未捕获，单独保存编辑器图，不做拼图；图像不是桌面截图，1720不是物理宽屏证明。奶油白、草莓粉与白鹅资源沿用已实现的[视觉重设计](goose-visual-redesign.zh.md)，没有临时换画风或修改算法。

[新ZIP全新解压、8包文件／2执行权限和deep严格签名](evidence/run-lifecycle-quality/package-check.json)通过。交付 `build/Config Compare Run Quality.zip`，SHA256 `a8233af43d9cef77ce63026ccdb6e7c36b10065071efdfbdb1e5250bb5562a87`；只是本机ad-hoc Release，不是正式公证发行。

## 双独立评审与主源码

[CC／DS独立接受同一候选](evidence/run-lifecycle-quality/review-synthesis.json)，无阻塞，wholeGoalAccepted=false。候选 `ed3423a210cc8b3000fee0df8dee63ef901b3b6cd1a903c6602774d5ba3c9cd1`（143文件），[差异](evidence/run-lifecycle-quality/candidate.diff)只有check-network.py与test-verifiers.py。已合入主项目，[完整性核验](evidence/run-lifecycle-quality/post-review-integrity.json)确认主源码逐字节等于冻结候选、共享提示／ZIP未变、原App8个文件保留，仍仅原主进程PID47589。没有启动第二个主GUI或替换用户输入。

CC原会话 `182e4632-1032-40a0-b67f-c28acd17288a` 正常exit0／timedOut=false，实际claude-opus-5-5[1m]，没有因观察等待重开。[原会话工具事件](evidence/run-lifecycle-quality/review-claude-tool-events.json)确认CC现场复算两脚本及143文件完整manifest，阅读提供的diff与RED/GREEN；没有重跑门禁、看图、核验ZIP或基线文件。其test-verifiers哈希缩写尾码e39f不准确，原工具输出实际为正确的完整哈希尾码cfc67f，以该原输出和本机清单为准。CC另只写自己的计划文件；两处管道head没有rtk前缀，不声称其每段shell都遵守前缀要求。

DS实际deepseek-flash，只有官方API文本输入，没有本机工具或图像访问。其关于未来未知glyph自动fail-closed的判断不正确：新格式若不在已识别前缀中会被忽略，CC明确指出同一限制，留待加固。其负向失败计数也需纠正为两项命名测试、6个后缀＋5个时长子断言，共11条失败，不能重复计数。

双方非阻塞意见保留：未知glyph及运行中━回归、PGID复用窄竞态／EPERM、异常收尾wait可能覆盖原异常、日志显式UTF-8、自发SIGINT与慢机器时序、teardown失败阶段。当前真实Swift输出与自有进程范围通过，不因此声明所有未来输出或全部生命周期均已验收。

## 仍开放

源码增量接受与本机自动门禁不等于原91项完整验收。真实桌面鼠标／键盘／输入法／VoiceOver、20MiB冷P95与交互／内存、完整App与XPC生命周期、目标设备、明确获准的真实非生产部署、正式签名公证发行仍开放。当前用户 App、输入、通用剪贴板与真实 Vault Token 保留。

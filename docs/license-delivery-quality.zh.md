# 第三方许可证与 NOTICE 资源交付

2026-10-04。沿用既有原生白鹅界面，本轮只补依赖许可证资料和离线开发构建校验；不新增产品模块，不改比较、Vault、编辑器或MCP。完整目标仍active。

最终候选 `0fd389c4add66cc49868d3d3c69288016d686e743706a79d22f7c3051213b9cc`，315个源／测试／打包文件。[14项完整门禁](evidence/license-delivery-quality/verification/results.json)、[同候选双评审](evidence/license-delivery-quality/final-review-synthesis.json)与[主源码整合完整性](evidence/license-delivery-quality/final-post-review-integrity.json)通过；315项源码逐字节等于冻结候选。

覆盖104个第三方来源组件（97 Rust、7 Swift），166份原文。包含已锁定dev/build/platform-only超集，不能推断都链接进App或已经过发行法律审核；自有compare-core不列入第三方组件。

新增本地Packaging/ThirdPartyNotices：inventory、origins、README及166份原文；新建check-licenses、test-licenses、test-packaged-notices脚本；仅修改build-macos及verify-local两个既有脚本。Resources在签名前复制并校验，App不联网下载资料，不要求用户安装Python或rtk。

完整14门禁通过，Rust95／Swift198／Python52／许可证15／包消费者1，共361项命名测试。重复运行、原生32条件断言不累加。105张owned原生图像，7张实际查看；不是桌面／输入法／VoiceOver证明。包177文件，fresh extraction/deep strict签名及两个执行权限通过，ZIP SHA256 `5fcdf650b038abdc9bd1acaa046d17ff052e1660cdeabfb1a0c773933a9869d6`。

首轮d7ed候选：CC接受，DS要求修改，不能算双接受。6份Swift阈值／性能测试／模板误收已移除；3个文件类型子断言先在旧checker失败，修复后拒绝。另3项旧行为回归证明归档revision错配、包内正文与索引同时被修改、额外未登记文件曾被接受，补强后15项通过。首批7项为缺API契约红，不能冒称旧行为运行失败；已有3处真实变异实验另外记录。

来源正文与crate checksum锁定归档、SPM固定commit Git对象和本地vendor逐字节对照。3个fallback上游以crate .cargo_vcs_info revision与开发期固定Git blob收据校验；收据不是签名信任根。sourceTreeSHA1误填commit已经用官方root tree纠正。Swift origin为SPM本地repositories路径，直接要求等于远端pin URL会拒绝合法缓存。当前v4读取器不是通用TOML，未来锁格式/缓存布局需适配。

保留Python3.9缺tomllib的初次准备失败和隔离target相对链接错误导致的Rustclippy门禁失败；均已纠正，再完整重跑新候选，没有覆盖为成功。当前App8文件及PID47589保留。node_repl+sky本轮已初始化成功，但尚未操作实际App，不能继续把接口缺失当作当前事实，也不因此宣称桌面验收。

仍开放：真实桌面键盘／输入法／VoiceOver、20MiB冷P95与内存／完整App循环、最低macOS14及Intel／干净设备、获准真实非生产部署、实际链接／发行兼容性与正式签名公证。禁止生产边界不变。


## 本轮评审与证据边界

[CC原会话](evidence/license-delivery-quality/final-review-claude-cli.json) `59dbcbf2-e63c-42c2-a677-cfccc3ec0b40` 正常exit0/timedOut=false，实际claude-opus-5-5[1m]。现场核对315项源码与基线差异，复跑15项许可证及原包／解压消费者，核验来源、177包文件、签名和ZIP哈希；没有重跑全部14门禁、看图或联网。仅写自己的计划。最初ZIP相对路径错误，随后用正确路径核验，原[工具事件](evidence/license-delivery-quality/final-review-claude-tool-events.json)保留。

[DS最终接受](evidence/license-delivery-quality/final-review-deepseek-verdict.json)实际deepseek-flash，仅文本，没有本机工具／联网／图像访问。共享提示包含166份资料的66份去重全文，五份CRLF正文通过read_text规整换行；这不是模型独立复算原始字节hash。原始源码与包仍按bytes核对。DS“shipped Python3.9”措辞应理解为开发测试主机Python3.9，用户App无需Python/rtk。两者只接受本增量，wholeGoalAccepted均为false。

CC独立扫描未发现当前有名称的LICENSE／NOTICE文件遗漏，文件级来源发现尚未固化为门禁。SwiftNIO的NOTICE引用了一些只存在源码头中的BSD/MIT条款；是否需随实际二进制另附取决于链接范围与发行审核，本轮没有将它判为法律通过。收据不是签名信任根，未来锁格式／缓存布局／干净构建前提仍单独核验。

[361项命名测试](evidence/license-delivery-quality/final-test-counts.json)、[105份原生图像及7份实看](evidence/license-delivery-quality/final-native-image-proof.json)、[loopback HTTP/TLS](evidence/license-delivery-quality/network-check.json)、[原生绑定](evidence/license-delivery-quality/revision-native-bindings.json)、[新包全新解压](evidence/license-delivery-quality/final-package-check.json)、[实际解压消费者](evidence/license-delivery-quality/final-extracted-notices-check.log)及所有RED／准备失败均保留。原生Swift198/24套；HTTP11项/71个GET，没有真实Vault、生产、真实Token、Cookie、重定向或信任更改。

当前交付 [Config Compare License Quality v2.zip](<../build/Config Compare License Quality v2.zip>) 为本机ad-hoc测试包。当前运行的原App8文件与输入保持，并未切换到新包。用户刚提供四张毛绒白鹅图片；这是后续视觉素材修订，尚未继承本候选的双接受、门禁或包验证。

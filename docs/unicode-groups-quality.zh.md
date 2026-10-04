# Unicode 行与分组一致性修订

2026-10-04。本轮关闭 N4：比较核心和结果树对 Unicode 对象键的显示规则已统一，避免核心行路径与 Swift 分组路径出现不同 identity。

## 行为契约

- 非空且只含 ASCII A-Z、a-z、0-9、下划线的键使用点号形式，例如 $.plain。
- é、中文、组合字符、点号、空键、控制字符和 lone surrogate 使用带引号的括号形式，例如 $["é"]、$["é"]、$["\ud800"]。
- 判断在 Rust 中直接基于 UTF-16 code unit；只有确认全为 ASCII 后才转成字符串，因此 Unicode 键不会经过 from_utf16_lossy。
- Swift ResultOutline 保持原有 PathSegment.key([UInt16]) machine identity；显示规则与核心一致，NFC 与 NFD 不会因 Swift String 的规范等价比较而合并。

## 实际修改

- crates/compare-core/src/model.rs 新增 simple_path_key，替换原先 char.is_alphanumeric() 的 Unicode 点号判断。
- crates/compare-core/tests/contracts.rs 增加真实核心契约，覆盖 ASCII、预组合 é、中文、组合字符、点号和 lone surrogate。
- apps/macos/Tests/CompareTests/ResultOutlineTests.swift 增加真实 CoreBridge + ResultOutline 回归：用 UTF-16 数组比较路径，验证预组合 é 分支只有自己的 child，组合字符叶子保持独立。
- ResultOutline.swift 的 machine path identity 没有改动。

## 验证、评审与包

最终候选 source manifest SHA 为 e503684dc4c354c2b0c96bcd493e1a60ad187cb9fc1d41cbb617059a5d833154（331 文件）。

- 正式本机门禁 runID 96b79279-ae4a-4a85-8f67-3652a8336af8：15/15 命令通过，passed=true、manifestStable=true、realVaultAccessed=false。
- Swift loopback 网络／TLS 全量矩阵：237 tests／30 suites 通过；仅使用临时 localhost fixture，未访问真实 Vault。
- Rust Unicode 聚焦契约、Swift unicodeGroupedPathsMatchCoreDisplay 聚焦回归通过。
- Config Compare Unicode Groups Quality.app 深度严格签名、包内 XPC self-test、NOTICE 与本地资源核验通过；ZIP SHA-256：5cbbc06ef6a986b89c098aeb48359b5d67ff40ae69ba281d3faba5c7150f9c93。
- Claude Code 与 DeepSeek 对同一最终 SHA 均给出 ACCEPT_LOCAL_CHANGE，blocking findings 为空。

证据：

- [正式门禁结果](evidence/unicode-groups-quality-results.json)
- [Swift 全量网络证据](evidence/unicode-groups-quality-network-check.json)
- [CC 评审](evidence/unicode-groups-quality-cc.json)
- [DS 评审](evidence/unicode-groups-quality-ds.json)
- [双评审综合](evidence/unicode-groups-quality-review-synthesis.json)
- [评审后完整性与包核验](evidence/unicode-groups-quality-post-review-integrity.json)

本轮没有连接生产或真实 Vault，没有写入配置，没有启动或切换用户 App，也没有 commit 或 push。真实 GUI、键盘／IME／VoiceOver、目标设备、长时性能、获准非生产部署和正式签名／公证仍属于完整目标的开放门槛。

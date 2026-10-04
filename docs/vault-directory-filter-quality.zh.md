# Vault 目录优先选择与共同配置过滤

> 最新本地候选：`b7c5ca5b3eff90d65e3ee8b94519cc53fae8a8024c67f136116cde0b9a6ef778`；正式门运行 `3f42f257-f7a2-4d10-8304-4cfa5f82d11b`。CC 与 DeepSeek 针对同一 SHA 均返回 `ACCEPT_LOCAL_CHANGE`，blocking 均为空。

本轮调整 Vault 表单交互：先选 `Directory scope`，再按所选范围生成 `Configuration name`。

- 具体目录只显示该目录实际存在的配置名称。
- `All directories` 使用 `**`，只显示所有已发现子目录共同存在的配置名称；mount 根的单独配置不会污染子目录交集。
- 目录发现会记录已经读取的目录，即使某个目录返回空列表；只要范围中有这样的空目录，`**` 的共同配置名就是空，避免把根配置误当成“全部都有”。
- 切换 namespace、namespace 匹配、目录范围、mount、目录根或目录匹配时，当前不属于新范围的配置名会被清空；高级设置仍可直接编辑配置名称，直接编辑目录匹配也走同一条失效逻辑。
- A/B 两侧仍独立选择 namespace、mount、目录范围和配置名称。
- 手动非生产勾选已移除。网络层仍拒绝 URL、namespace、mount、目录和配置名称中的可识别 `prod`、`production`、`prd` 标识；没有连接真实或生产 Vault。

本轮修复了根目录 `.` 与全目录 `**` 的语义边界：`.` 使用无 matcher 的单层根目录读取，只有真正以 `**` 读取的目录范围才允许计算全目录交集；因此字面目录或根目录读取不会冒充 `**` 的共同配置结果。

新增回归覆盖 `auth`、`payment`、`promotion` 的共同 `uat-swim`／`qat-other`、只存在于部分目录的名称、空目录、根配置排除、目录切换后的 stale name 清理和生产标识拦截。最终完整门禁为 15/15，通过 Swift 251 tests／30 suites；定向 Vault 发现测试为 30 tests／2 suites。网络证据为 loopback 合成传输，`realVaultAccessed=false`；这不是生产 Vault 或真实非生产服务验证。

最新本机包：`build/Config-Compare-local-b7c5ca5b-arm64.zip`，SHA-256 为 `6db6cc58f45f9613fa231a10caf4bd8a724f399e7df7a228deba5ca29a7ac95f`。NOTICE、资源、严格签名和 packaged self-test 均通过；`formalReleasePassed=false` 仍表示没有完成正式发布门禁。

本次后续协议增量移除了入口处的 HTTPS-only 校验，并新增 HTTP 与非 HTTP scheme 的解析回归；解析通过不代表底层 URLSession 已支持该协议，详见 [协议复核记录](evidence/vault-url-scheme-review-synthesis.json)。

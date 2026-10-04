# Config Compare

给 SRE 使用的原生 macOS 配置工具，包含用户提出的三项功能：

- env.js 静态配置比较：按键和类型判断差异，不执行 JavaScript。
- Vault 批量比较：两侧填写 URL + Token，独立选择 namespace、KV mount、目录范围和可编辑配置名称。namespace 与 secret 目录支持 `*`、`**`、`?`；先预览匹配范围，再只读取得配置比较。
- YAML 格式化：保留注释、引号、引用和文档顺序，核对格式化前后内容。

禁止连接生产。App 的 Vault 网络层会自动阻止带有生产标识的来源、namespace、mount、目录和配置名称，只允许受限的 KV GET/LIST，阻止重定向和动态 engine，不绕过 TLS；env.js/YAML 不联网。计算进程无网络权限、不持有连接 Token。没有遥测、自动上传或写回 Vault。原文件和已有导出文件不覆盖。

## 本机使用

开发构建位置：`build/Config Compare.app`。env.js 默认一次比较整份文件中的多个变量，按名称配对，例如同时比较 `env` 和 `happy`，也保留独立的 CommonJS 导出；命名对象的导出别名按对象身份去重。也可在“比较范围”选择单一变量或 `module.exports`；刷新后变量消失会明确提示，保留选择供你更正。YAML 只需要 A 输入。快捷键 `⌘ Return` 运行，`Esc` 停止。

env.js 的结果直接显示变量及字段，例如 `env.x`、`happy.x`、`env.items[0]`；单一变量模式显示 `x`、`auth.host`、`items[0]`。含点号的属性保留 `["a.b"]` 形式以区分嵌套变量，报告保留完整机器路径。`var happy={x:y}` 中的 `y` 若未独立声明，会标为无法比较；引用已有对象字段应写 `env.y`。

设置占满整个窗口，左上角“返回工具”和 Esc 返回原输入/结果。可选择简体中文或 English、本机显示名称、4 个中性内置图标、奶油白浅色主题和强调色。

Vault 可直接粘贴浏览器链接，点击“拆解链接”填入 mount 和配置名称，然后自行修改。读取配置名称后先选择“目录范围”，再选择配置名称；选择“全部目录”时只显示所有已发现子目录都存在的共同名称。A/B 的 mount 和名称可以不同，按相对目录配对。Namespace 根留空表示 root，`.` 只使用当前 namespace，`*`/`**` 匹配其子 namespace；无 namespace 功能的 Vault 使用 `.`。界面不再要求手动勾选，生产标识由代码自动阻止；使用前仍应核对来源和 namespace 范围。每条读取不是同一时刻的原子快照。

Token 默认仅保留当前会话；切换功能/清空时移除。服务地址不再强制 HTTPS，可按输入解析常规 HTTP/HTTPS 或 Vault 网页/非 HTTP 链接形式；底层 TLS 仍由系统校验，不绕过证书验证，非 HTTP scheme 是否可直接读取取决于实际网络客户端支持。URL 名字或勾选不能证明环境性质，应使用已经核实的非生产来源；不能将未知共享根当作非生产。权限失败、歧义404或任一条读取失败会停止整批，不输出虚假的缺失结论。已有 JSON 导入保留为可选方式，正常使用不需要导出或复制配置。

## MCP 使用

App 左下方“复制 MCP 配置”提供本机 stdio 连接配置，示例：

```json
{
  "mcpServers": {
    "config-compare": {
      "command": "/绝对路径/Config Compare.app/Contents/MacOS/ConfigCompare",
      "args": ["--mcp"]
    }
  }
}
```

不需要启动窗口或安装 Node/Python。提供 `env_compare`、`yaml_format`、`vault_preview`、`vault_compare`、`comparison_rows`；工具参数可由客户端发现。MCP 配置不包含 Token。

Vault 需先在 App 填写两侧信息、预览匹配清单，再点击“授权 MCP 使用当前范围”。这一步明确把两侧凭证和清单保存到本机钥匙串。MCP 先调用 `vault_preview`，核对清单，再用 planId 调用 `vault_compare`。不能通过工具参数改变地址或扩大范围；匹配清单变化会要求回 App 重新预览授权。可在 App 撤销，删除这份凭证并禁止新的读取和旧 Vault 结果分页。ad-hoc 包重新签名后，钥匙串可能拒绝旧签名访问，需要在 App 重新授权；不会自动绕过。

比较默认只返回路径、类型、状态；`includeValues=true` 才向 MCP 客户端返回配置值。`comparison_rows` 每页最多 200 项。YAML 格式化会返回完整格式化文本。交给 CC/Codex 的内容可能进入该客户端的模型上下文，请按实际数据决定是否返回值。App 不主动调用 AI 服务。

`env_compare` 的 rootA/rootB 默认 `*`，一次比较所有顶层变量；若只比较 env，明确传入两侧 `rootA:"env"`、`rootB:"env"`。两侧不能混合全变量和单变量模式。

结果按类型区分数值与字符串、缺失与 null、undefined 与数组空槽。无法静态确认的 JS 内容不会判为相同，界面会显示不完整范围。输入或根改变后旧结果不能复制、导出为当前结果。详情复制完整值，列表只显示截断预览。

JSON 报告包含类型与机器可读路径；CSV 对公式触发字符做转义。可选择仅当前筛选、是否包含配置值。报告和剪贴板可能包含用户主动复制的配置值。导出必须使用新文件名。

## 开发构建与验证

需要本机 Rust、完整 Xcode、Python 3、Node 和 RTK；Node 仅用于固定合成 JS 的独立语义对照。这些只用于开发，打包后的 App 不需要它们。

```sh
rtk cargo test --locked -p compare-core
rtk cargo build --locked -p compare-core
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apps/macos
rtk proxy python3 scripts/build-macos.py
rtk proxy 'build/Config Compare.app/Contents/MacOS/ConfigCompare' --self-test
rtk proxy open 'build/Config Compare.app'
```

本机开发包使用 ad-hoc 签名；它不是已公证的正式分发包。支持范围与真实验证记录见 [执行记录](docs/offline-tools-execution.zh.md)。
## 完整质量验证

开发验证入口：`rtk proxy python3 scripts/verify-local.py`。清理 Swift 构建后重新链接 Rust，并运行核心、固定合成 JS 的 Node 独立对照、Swift 状态逻辑、实际本机 HTTP/TLS、验证器负向测试、Release 打包/XPC 和 stdio MCP。普通验证不读取钥匙串或连接任何已保存 Vault；JS 对照不接收或执行用户配置。验证前后重新扫描并核对源文件清单，新增、删除或修改都使候选失效。

当前完整目标仍在推进，见[逐项验收清单](docs/quality-completion-audit.zh.md)。本机自动测试通过不代表 GUI、无障碍、目标设备和正式发行验收全部完成。

# 类型报告与 CSV 导出验证计划

> **For agentic workers:** 使用 superpowers:executing-plans 在当前已授权会话逐项执行；不提交、不发布、不访问真实 Vault。

**Goal:** 为既有 JSON/CSV 导出补独立验证，推进 C14、U11、U12；完整 GUI/复制及设备门槛分别登记，不能由核心测试代替。

**Architecture:** Rust 真实 json_lines 进程产生报告，Python 标准库 csv.reader 解析 CSV 并与手算单元格比较。Swift 真实 FFI 报告经 InputFiles 新文件写入、读取、DTO 解码，保留类型与 UTF-16。所有输入为固定合成数据，静态解析用户 JS 的行为不变。

**Tech Stack:** Rust、Swift Testing、Python json/csv、已有本机质量门禁。

## 1. 完整类型报告文件往返

Create: `apps/macos/Tests/CompareTests/ReportRoundTripTests.swift`。

- [x] 真实 CoreBridge 请求 `compare → report`，用 `InputFiles.writeNew(Data(raw.utf8),to:target,inputs:[])` 写入临时目录，再 `CoreResponse.decode(InputFiles.read(target))`。
- [x] 明确断言 Number 的 `-0/+0/NaN/Infinity/-Infinity`、BigInt、Null、Undefined、Hole、Unknown.reason、Missing.present=false、容器 entries/items、孤立 surrogate units；长文本详情与报告保持完整。
- [x] 用 240 项结果验证默认报告包含全部行，初始页面仍为 200；过滤报告正确且摘要仍为全量；includeValues=false 不携带 literal/units/entries/items/reason。

Run: `rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apps/macos --filter ReportRoundTripTests`。既有行为的新增证据可以首轮通过；只有真实缺陷才记录失败后修复，不伪造红灯。

## 2. 独立 CSV 与 JSON oracle

Create: `scripts/check-reports.py`；Modify: `scripts/test-verifiers.py`、`scripts/verify-local.py`。

- [x] 先加入验证器负向回归，缺少新模块时应失败；再实现严格 `validate_csv(text,expected)`：`csv.reader(io.StringIO(text,newline=''),strict=True)`、固定六列、完整行数、逐单元格相等、CRLF 记录边界。
- [x] 固定手算样本覆盖 ASCII/全角公式样式字符串、制表符/CR/LF、逗号/引号、中文/emoji/组合字符、负数与 -Infinity、缺失/Unknown、长文本及容器；公式前缀规则针对真实报告单元格，不假设每个 JS String 的原始内容直接进入 CSV。
- [x] Debug/Release 各执行完整/过滤/隐藏值 JSON 与 CSV，原始 JSON 写入临时文件再 json.load；验证器必须拒绝损坏行数/列数/引号、错误值、缺失类型、遗漏行、未脱敏值。
- [x] 新增第 13 条门禁 `("typed-json-csv-reports", [sys.executable,"scripts/check-reports.py"])`；AST 检查包括新脚本，Python -O 不能禁用 require。

Run: `rtk proxy python3 scripts/test-verifiers.py`；`rtk proxy python3 scripts/check-reports.py`；然后 `rtk proxy python3 scripts/verify-local.py`。预期所有命令 exit0，并输出两种构建的独立报告证据。

## 3. 当前候选复核与证据

- [x] 冻结新的 source_manifest；保留旧 e84 证据，新增独立目录与 SHA256，核对 App/worker/ZIP。
- [x] 使用 claude-code-local 与官方 DeepSeek API 独立审查同一候选及本轮证据；不互相透露审查结论，不将局部接受写为完整目标完成。
- [x] 更新 `docs/quality-completion-audit.zh.md`、主计划与执行记录，区分核心/文件往返通过、实际 GUI 复制/导出、设备和非生产实测仍 OPEN。

CSV 以当前可读报告为契约，精确恢复使用类型 JSON。独立解析通过不能证明所有电子表格保存再打开的行为；没有实施导入报告 UI，也没有执行报告中的 JS literal。

本计划只完成列出的本机验证增量；实际GUI复制/导出与完整目标未关闭。最终候选、命名测试数量、两个独立评审和证据边界以综合记录为准。

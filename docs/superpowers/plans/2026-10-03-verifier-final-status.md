# 验证器最终状态与界面导出验收

> **For agentic workers:** 使用 superpowers:executing-plans 在当前授权会话执行；完整目标保持 active，不提交、不发布、不访问真实 Vault。

**Goal:** 修复 CC R1 的整轮结果不自洽问题，并继续取得真实包的界面导出证据。

**Architecture:** 既有13门禁不缩减；开始前原子落盘 passed=false，运行后重新哈希源码，只有命令、源码冻结及最终结果写入均成功才输出成功标记。GUI 用 Computer Use 操作当前候选新包与 NSSavePanel，合成配置结果由独立标准库读回，不将核心样本代替界面证明。

**Tech Stack:** Python unittest/真实短子进程、Swift/Rust现有测试、macOS Computer Use。

## 1. 结果文件自洽

Modify: `scripts/verify-local.py`、`scripts/test-verifiers.py`。

- [x] 先加入9个回归并运行：8个断言失败、1个真实子进程因旧passed记录退出19；没有执行任何App/Vault。
- [x] 添加runID、passed、finished、candidateSHA256、finalManifestSHA256、manifestStable、expectedCommandCount、failure；用临时文件、fsync及os.replace原子写结果，成功标记在最终写入之后。
- [x] 覆盖真实源码修改/命令exit7/初始缺文件/最终缺文件；超时、KeyboardInterrupt、spawn异常通过故障注入；异常内容不进入结构化结果。
- [x] 扩展为12个回归，最终结果写入失败不产生成功标记；命令数量改变先实际失败，再增加最终条件守卫。
- [x] `rtk proxy python3 scripts/test-verifiers.py` 和 `rtk proxy python3 -O scripts/test-verifiers.py` 均通过；完整13门禁按最终源码重跑，检查下列不变量。

```python
require(result["passed"] is True and result["finished"] is True, "Incomplete run")
require(result["manifestStable"] is True, "Source changed")
require(result["candidateSHA256"] == result["finalManifestSHA256"], "Identity differs")
require(result["failure"] is None, "Run failed")
require(len(result["commands"]) == result["expectedCommandCount"] == 13, "Missing gates")
require(all(command["exitCode"] == 0 for command in result["commands"]), "Failed gate")
```

## 2. 本候选真实GUI导出

Evidence: `docs/evidence/2026-10-03-verifier-status-final-*`。

- [x] 从当前候选包重新打开App，输入合成长值/多行/特殊类型；核对表格有界预览与完整详情。
- [x] 通过实际NSSavePanel导出JSON/CSV，标准库核对完整内容、类型和CRLF/引用；分别登记完整/筛选/隐藏值实际覆盖的样本。
- [x] 恢复用户原始env/happy代码、中文和原主题；保留截图/AX与包身份。复制及完整剪贴板恢复独立验收，不暗中修改原剪贴板。

## 3. 同候选双复核

- [x] 冻结新源码/包/提示；CC与DS独立评审同一候选、完整门禁及新GUI证据；CC观察超时只恢复原session。
- [x] 更新主计划、执行记录及91项审计，说明来源JSON再编码、完整复制、设备/非生产/正式发行仍需各自证据；评审后重新核对源码、App、worker、ZIP及提示哈希。

本计划中的增量任务完成；未完成项继续在原91项审计与综合记录中保留，完整目标保持active。

# 多变量深层比较与结果分页修订

用户要求一次比较多个变量，且每个变量内的多层对象、多个分支和数组都需要检查。保留纯静态解析、禁止生产连接、三项工具与双语设置范围。

当前候选：`d776ce0a36c0547b89e07c37018bd44515aa176c4dd17fdb97aa017300a6022b`，133个源码文件。本轮嵌套需求由现有递归核心支持，新增组合回归，没有执行用户JS或改写求值器。

- [x] Rust：15条独立预期路径与状态；两侧变量/键顺序不同、深层对象和数组、父节点类型变化、点号键独立、交换A/B缺失方向、深层Unknown与已知兄弟隔离。
- [x] Swift实际FFI：Workspace默认全变量、差异/全部筛选、完整变量名称、树节点唯一性和深层类型详情；MCP默认全变量、结果页与不返回值的DTO契约。
- [x] 分页修复：真实401行旧包已复现过期结果“页码2但仍显示k000”。模型在stale/busy/importing时先拒绝修改页码和请求，UI禁用分页、筛选/搜索、显示模式和导出选项；4项真实FFI状态/边界回归通过。
- [x] [完整13项本机检查](../../evidence/2026-10-03-nested-batch-final-results.json)：Rust95、Swift140、Python33，共268命名测试，源码起止一致、Swift零警告。
- [x] [最终新包11份AX/JPEG](../../evidence/2026-10-03-nested-batch-final-gui-proof.json)：三页对应k000/k200/k400；编辑后的旧结果标记和控件禁用、重比恢复；两个变量深层树展开、类型详情、Unknown与原始三行恢复。
- [x] [ZIP解压与严格签名核验](../../evidence/2026-10-03-nested-batch-final-package-check.json)。本机arm64开发包，不是正式发行证明。
- [x] [CC与DS独立接受同一最终候选](../../evidence/2026-10-03-nested-batch-final-review-synthesis.json)。CC原调用session `ffaee288-ab29-43f7-b503-bdb333779dfa` 正常exit0/timedOut=false，复算8个范围源码哈希并阅读代码/AX，未重跑测试或实际GUI；DS仅文本审阅。共享范围提示冻结一致，只接受本轮增量，完整目标仍OPEN。[评审后完整性](../../evidence/2026-10-03-nested-batch-final-post-review-integrity.json)确认源码/提示/主App/worker/ZIP未变化。

作者错误单独保留：首次Rust断言误用incomplete而非incompleteRanges；Swift动态String未转Testing Comment；首次组合测试忽略run恢复默认差异筛选及脱敏DTO保留type/present/display。更正后通过，不把这些当成产品缺陷。分页运行时红灯为另一组经过更正的真实状态测试，不与作者错误混淆。

完整91项、键盘/IME/VoiceOver、GUI性能、独立包内worker运行中退出、目标设备、实际获准非生产部署与许可证/正式发行门槛继续保留。

下一项：CC N1从源码推断行请求在途时被export/inspectRoots推进generation取代或请求失败，会留下先更新的page与旧rows；尚未实测，须用确定性运输门控独立复现再修复。N2取消后导入恢复的断言等待强度、N3重复行请求、N4Unicode行/分组路径显示差异也保留为后续核验。DS关于单个分页按钮未叠加stale守卫的观察不构成新缺陷：父HStack统一disabled，实际AX已核对两个按钮disabled。

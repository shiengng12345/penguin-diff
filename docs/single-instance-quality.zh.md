# 单实例与重复启动修订

2026-10-04。本轮针对 Dock 上出现两个 Config Compare 图标的问题，只修改单实例生命周期，不改变比较算法、Vault 读取范围、MCP 协议或用户输入。

## 实现

- `apps/macos/Sources/ConfigCompare/AppInstanceGuard.swift` 新增正式 GUI bundle 的单实例守护。`com.penguin.configcompare` 使用用户 Application Support 下的 `Config Compare/gui-instance.lock`，通过 `O_CREAT | O_RDWR | O_CLOEXEC` 与非阻塞 `fcntl(F_SETLK, F_WRLCK)` 竞争跨进程锁；持锁描述符由 application delegate 保留到进程退出，并在析构时解锁。
- 只有已完成启动且仍运行的旧 peer 才会接收 handoff。尚在 `applicationWillFinishLaunching` 的竞争者不会被当作旧实例，避免两个进程互相退出。锁不可用时仍只选择已完成启动的 peer，避免把竞争者误当旧实例。
- handoff 先调用 macOS 14 的 `yieldActivation(to:)`，再激活已有进程，并用 `NSWorkspace.OpenConfiguration`（`activates=true`、`createsNewApplicationInstance=false`）复用已有 bundle；异步完成或 1 秒兜底后才结束新进程。
- `ConfigCompareApp` 通过 `@NSApplicationDelegateAdaptor` 接入；命令行 `--mcp`、`--self-test`、图标渲染／资源校验在 `App.main()` 前分流，XPC worker 的 bundle ID 为 `com.penguin.configcompare.worker`，均不启用守护。
- `apps/macos/Tests/CompareTests/AppInstanceTests.swift` 覆盖首实例、当前 PID、旧 PID fallback、终止 peer、正式 bundle 限定和已完成启动 peer（含较大 PID）。

## 测试与冻结证据

按测试先行执行：新增策略测试先在缺少 API 时失败；实现后 6 项单实例测试通过。最终隔离候选为 `e20e0d03be1bb7c36a67de352cb39370ab00e65f609cea1ab77282fc6dc55403`，331 个 manifest 文件与主源码逐字节一致。

- [完整门禁结果](../build/quality-review/single-instance-v2/workspace/build/verification/results.json)：runID `19b75621-ec48-4364-8290-99f6d3a5a6b6`，15/15 命令 exit 0，`passed=true`、`finished=true`、`manifestStable=true`；`realVaultAccessed=false`、`formalReleasePassed=false`。
- Swift 汇总为 235 tests／30 suites；Rust fmt、clippy、workspace tests、深度预算、loopback HTTP/TLS、Release ad-hoc XPC self-test 和打包 MCP 均通过。
- [Claude Code 评审摘要](evidence/single-instance-quality-cc.json)与 [DeepSeek 评审摘要](evidence/single-instance-quality-ds.json)都针对同一个 SHA 给出 `ACCEPT_LOCAL_CHANGE`，没有 P0/P1；两者没有启动 GUI、访问 Vault 或重跑完整门禁。[综合记录](evidence/single-instance-quality-review-synthesis.json)保留接受范围与边界。
- [本地 ad-hoc 包](../build/Config%20Compare%20Single%20Instance%20Quality.zip)已由最终候选复制生成，ZIP SHA-256 为 `32937ed39be1092c0b1a0575e5ed28dcc8ff5b434f484f9a0a5fb1b9ff37508`；深度签名校验与 `PACKAGED_XPC_SELF_TEST_OK` 通过，self-test 窗口数为 0。MCP 门禁使用同一候选隔离包，Vault I/O 为 NOT_RUN。

## 尚未关闭的边界

本轮没有启动或切换用户 App，因此没有把真实双击、`open -n`、窗口全部关闭后的 reopen、焦点激活和 Dock 表现写成已验证。评审指出锁／delegate 尚无跨进程集成测试，退出中的旧 peer、LaunchServices 选择同一 bundle 实例和沙盒／ad-hoc 副本行为仍属于 P2 观察。完整桌面、键盘／IME／VoiceOver、目标设备、长时性能、获准非生产部署和正式签名／公证继续保持 OPEN。

没有连接生产 Vault，也没有向任何环境写入配置；未 commit、未 push。

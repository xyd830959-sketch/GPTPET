# 开发与验证

使用 Node.js 22+、Git 和 Windows PowerShell 5.1。无 npm 依赖，不需要 API key。保留旧版权、用户配置路径和插件身份；修改安装生命周期前先阅读安装文档。

## 仓库根目录与导出快照

本 Git 仓库保留原提交历史。先用 `git rev-parse --show-toplevel` 核对根目录，再运行历史检查。此前独立导出的源码快照不携带 `.git`，若从源码归档使用，不要把父目录的其他仓库扫描结果当成本项目历史。来源摘要见 [CANDIDATE_ORIGIN](CANDIDATE_ORIGIN.md)。

## 静态检查

`npm run check` 验证元数据、来源文档、内部链接及当前发布文件中的常见敏感信息模式。`npm run check:history` 额外扫描本地 Git 对象，并只报告路径、对象号和问题类型，不打印疑似密钥内容。扫描不是无泄漏保证，首次公开前还需人工检查历史、图片及归档。

## 自动测试

测试会创建和删除合成文件。必须先选择专用目录并明确同意该范围的测试清理。不要把源代码目录、正式安装或个人配置目录设为测试根目录。下面的允许变量仅表示执行者对其选定目录中测试生成数据的同意；自动代理仍须遵守用户要求的确认流程。

如不允许批量清理，先设置专用的 `GPTPET_TEST_ROOT`，运行 `node scripts/run-tests.mjs --keep-fixtures`。该模式保留测试目录与合成文件，不需要设置清理授权变量；运行时请求、锁和临时文件仍按被测功能正常结束。模拟文件缺失时将测试副本改名保留。报告和预览同样保留，之后清理须单独确认路径和数量。

```powershell
$env:GPTPET_TEST_ROOT = Join-Path $env:TEMP 'gptpet-isolated-tests'
$env:GPTPET_ALLOW_TEST_CLEANUP = '1'
npm test
```

统一入口为每轮新建子目录，并将 TEMP/TMP 与所有壁纸测试数据定向其中。Node 测试包含模拟 CLI/worker/CDP；Windows 测试包含安装隔离、生命周期、入口、语录、WPF 与壁纸菜单。常规测试使用模拟 Store 信息，不要求安装 Codex，也不连接真实账号。退出码非零即失败。

`npm run test:node` 仅运行 Node 测试；`npm run test:windows` 仅运行 Windows 测试。单独执行旧测试文件会绕过统一目录设置，不建议这样做。

需要本机 Store 定位检查时，在专用目录与清理授权都设置后，显式运行 `powershell.exe -NoProfile -STA -File tests/run-windows-tests.ps1 -LiveCodex`。它只运行启动器 CheckOnly，不启动、安装或导入账号配置；这仍不等于完成冷启动和壁纸实测。

## CI 与证据

工作流使用 Windows runner、Node 22/24、只读仓库权限；运行静态检查和隔离测试。不会发布、推送、安装真实插件或连接真实账号。只有将工作流提交并推送后才能出现 GitHub 上的运行结果；本地成功不能写成远端 CI 已通过。

测试报告保存于每轮专用目录；CI 上传报告和合成预览以便复核。提交前查看 `git diff --check` 与实际 diff。不要为通过检查而关闭必要断言。

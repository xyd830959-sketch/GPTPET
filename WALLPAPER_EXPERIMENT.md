# GPT 娘 Codex 壁纸实验版

## 范围与保护

本版本基于 GPT 娘额度挂件 v1.2.5。原项目是 PowerShell/WPF 挂件，Node.js 模块负责 Codex 额度读取；聊天、模型连接和账号数据属于 Codex 桌面客户端，不在本项目内。本实验只在挂件右键设置菜单增加“Codex 个性化”，不修改聊天或模型连接代码。

稳定版运行目录和原始源码目录均未修改。本地源码备份位于工作区的 `backup/source-v1.2.5`，个人数据备份位于 `backup/private-user-state-2026-10-17`。后者含私人设置与运行状态，**不得上传 GitHub**。`stable-repo` 是本地稳定版 Git 分支，`experiment` 是 `feature/codex-wallpaper` 的独立 worktree。实验数据单独放在工作区的 `experiment-data`。

## 使用

1. 在实验目录运行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-WallpaperExperiment.ps1 -CheckOnly` 检查依赖和隔离数据路径。
2. 需要试用挂件时，运行同一命令并去掉 `-CheckOnly`。此脚本不会运行安装器，也不会替换正式版程序或注册系统启动项。
3. 在实验挂件的右键设置菜单打开“Codex 个性化”。先点“导入本地壁纸”，选择 PNG、JPG 或 WebP；文件最大 10 MB，尺寸最多 16384 × 16384，像素总数最多 5000 万。
4. 点击“启用壁纸功能”，再点击“应用壁纸”。此操作需要 Codex 已通过受支持的本机 CDP 调试会话启动，默认连接 `127.0.0.1:9335`。如果没有连接，会明确报错，挂件其他功能继续运行。
5. “恢复默认背景”只移除本模块注入的样式。关闭开关时也会尝试恢复；如果 Codex 已退出或连接断开，请完全退出 Codex，再从普通官方入口启动，临时注入的样式会随会话消失。

本实验版不会替 Codex 打开调试端口，也不会改 Codex 官方安装文件、`config.toml` 或启动快捷方式。当前本机常见调试端口没有可用连接，真实 Codex 视觉效果尚未验证。

## 技术说明与限制

- 壁纸图片复制到实验数据目录的 `codex-wallpaper/images`，以 SHA-256 命名。开关和当前图片记录在独立的 `codex-wallpaper/state.json`，默认关闭，不写入原挂件的 `settings.json`。
- 应用和恢复通过本机 CDP `Runtime.evaluate` 操作地址以 `app://codex` 开头的渲染页面，只使用带 `gpt-niang-codex-wallpaper-style` 标识的样式。没有自动恢复、轮换、动态壁纸、透明度或模糊度控制。
- 注入样式的存在可通过模拟测试验证；实际壁纸可见性、文字对比度和新版 Codex 的页面结构仍需实机检查。Codex 更新可能使选择器失效。
- 导入器校验图片签名、尺寸和基本文件完整性，但不执行完整图像解码；个别损坏图片仍可能在 Codex 中无法显示。
- CDP 回环端口没有身份认证，同一电脑上的其他进程可能访问。关闭壁纸开关只移除样式；如果 Codex 仍带调试参数运行，调试端口仍开放。完整退出 Codex 后从普通官方入口重启才结束该风险窗口。
- 参考项目 [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 使用 MIT 许可证；本实验未复制其代码或素材。其 [Windows 文档](https://github.com/Fei-Away/Codex-Dream-Skin/blob/main/windows/README.md) 也记录了部分 Codex 版本不开放 CDP 端口的兼容问题。

## 构建与验证

本项目没有编译步骤或 npm 依赖安装步骤。已通过 Node 和 PowerShell 语法检查、实验启动脚本 `-CheckOnly`、挂件入口 `-CheckOnly`。完整 Node 测试为 **33/33 通过**，包括本机模拟 CDP 的导入、默认关闭、启用、应用、恢复及排除其他应用页面；完整 Windows 既有测试通过，包括 21 项隔离安装检查、7 项生命周期检查、入口、布局和挂件测试。新增 `tests/wallpaper-ui.test.ps1` 也通过，检查旧设置菜单、壁纸默认关闭，以及 PowerShell 5.1 能真正启动壁纸后台进程。测试数据保留在工作区 `verification-data`；既有测试仅清理本轮创建的临时文件，用户已授权该范围。

真实 Codex 当前没有开放受支持的 CDP 端点，因此这些结果不能证明实际桌面客户端已显示壁纸。正式运行目录与原源码目录在测试后再次和 50 文件备份逐项比较，哈希差异为 0。

## 代码修改清单

- `runtime/codex-wallpaper.mjs`：独立状态、图片导入校验、本机 CDP 应用与恢复。
- `runtime/wallpaper-ui.ps1`：设置菜单和后台任务调用。
- `runtime/ui-settings.ps1`、`widget.ps1`：把壁纸菜单接入现有挂件；模块加载失败时保留原挂件功能。
- `Start-WallpaperExperiment.ps1`：只使用工作区实验数据启动，不运行安装器。
- `tests/codex-wallpaper.test.mjs`、`tests/wallpaper-ui.test.ps1`：新增功能测试。

## 回退

1. 关闭实验挂件；如果壁纸仍在 Codex 中显示，点击“恢复默认背景”，或完全退出 Codex 后从普通官方入口重启。
2. 继续使用原正式版运行目录 `C:\Users\user\AppData\Local\Programs\GPTNiangUsage\gpt-niang-usage`。实验版没有改动它。
3. 保留 `backup`、`stable-repo` 和 `experiment` 以便审查。若以后要移除实验 worktree，先列出拟删除的完整路径、文件数量和影响，取得用户确认后再操作；不要对稳定版执行 `git reset --hard` 或删除个人数据。

## GitHub 保存状态

稳定版源码已在本地 Git 的 `stable/v1.2.5` 分支提交，实验版在 `feature/codex-wallpaper` 分支。尚未创建远程私人仓库，也未上传任何文件。上传前必须再次确认仓库账号、私人可见性与文件清单。

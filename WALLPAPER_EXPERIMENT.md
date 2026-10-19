# GPT 娘 Codex 壁纸实验版

> 历史开发记录：2026-10-17，经过测试的壁纸代码已用于本机正式运行版本。下文关于“稳定版未修改”等叙述仅反映实验阶段，不代表当前本机安装状态。当前使用说明见 [README](README.md)。

## 范围与保护

本版本基于 GPT 娘额度挂件 v1.2.5。原项目是 PowerShell/WPF 挂件，Node.js 模块负责 Codex 额度读取；聊天、模型连接和账号数据属于 Codex 桌面客户端，不在本项目内。本实验只在挂件右键设置菜单增加“Codex 个性化”，不修改聊天或模型连接代码。

稳定版运行目录和原始源码目录均未修改。本地源码备份位于工作区的 `backup/source-v1.2.5`，个人数据备份位于 `backup/private-user-state-2026-10-17`。后者含私人设置与运行状态，**不得上传 GitHub**。`stable-repo` 是本地稳定版 Git 分支，`experiment` 是 `feature/codex-wallpaper` 的独立 worktree。实验数据单独放在工作区的 `experiment-data`。

## 使用

1. 在实验目录运行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-WallpaperExperiment.ps1 -CheckOnly` 检查依赖和隔离数据路径。
2. 需要试用挂件时，运行同一命令并去掉 `-CheckOnly`。此脚本不会运行安装器，也不会替换正式版程序或注册系统启动项。
3. 在实验挂件的右键设置菜单打开“Codex 个性化”。先点“导入本地壁纸”，选择 PNG、JPG 或 WebP；文件最大 10 MB，尺寸最多 16384 × 16384，像素总数最多 5000 万。
4. 点击“启用壁纸功能”，再点击“应用壁纸”。“壁纸暗度”滑块可在 20%～85% 间调节，默认 60%；数值越大，整张壁纸越暗。松开滑块后会保存并尝试立即更新当前 Codex 页面。此操作需要 Codex 已通过受支持的本机 CDP 调试会话启动，默认连接 `127.0.0.1:9335`。如果没有连接，会明确报错，挂件其他功能继续运行。如果 Codex Dream Skin 正在使用，需先通过其自身的“暂停”功能关闭主题，本模块不会覆盖它。
5. “恢复默认背景”只移除本模块注入的样式。关闭开关时也会尝试恢复；如果 Codex 已退出或连接断开，请完全退出 Codex，再从普通官方入口启动，临时注入的样式会随会话消失。

本实验版不会替 Codex 打开调试端口，也不会改 Codex 官方安装文件、`config.toml` 或启动快捷方式。2026-10-17 在本机 Codex `26.1013.4894.0` 的既有 `127.0.0.1:9335` 调试会话中完成过一次应用与恢复测试；该端口由已安装的 Codex Dream Skin 提供，测试时将 Dream Skin 暂停。

## 技术说明与限制

- 壁纸图片复制到实验数据目录的 `codex-wallpaper/images`，以 SHA-256 命名。开关和当前图片记录在独立的 `codex-wallpaper/state.json`，默认关闭，不写入原挂件的 `settings.json`。
- 应用和恢复通过本机 CDP `Runtime.evaluate` 操作 `app://codex` 或当前版本的 `app://-/index.html` 主页面，跳过头像层和独立窗口，只使用带 `gpt-niang-codex-wallpaper-style` 标识的样式。可调深色遮罩与壁纸作为同一背景作用于整个窗口；中央、侧栏、聊天顶部渐变和输入区背后的额外底色在壁纸模式下局部透明。原有按钮、消息气泡和输入框仍由 Codex 绘制。没有自动恢复、轮换、动态壁纸或模糊度控制。
- 实机截图确认主页面、中央聊天区及输入区后方可见同一张壁纸，且底部黑块已消失。文字对比度受壁纸内容及暗度影响，其他复杂页面仍需试用。Codex 更新可能使选择器失效。
- 导入器校验图片签名、尺寸和基本文件完整性，但不执行完整图像解码；个别损坏图片仍可能在 Codex 中无法显示。
- CDP 回环端口没有身份认证，同一电脑上的其他进程可能访问。关闭壁纸开关只移除样式；如果 Codex 仍带调试参数运行，调试端口仍开放。完整退出 Codex 后从普通官方入口重启才结束该风险窗口。
- 参考项目 [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 使用 MIT 许可证；本实验未复制其代码或素材。其 [Windows 文档](https://github.com/Fei-Away/Codex-Dream-Skin/blob/main/windows/README.md) 也记录了部分 Codex 版本不开放 CDP 端口的兼容问题。

## 构建与验证

本项目没有编译步骤或 npm 依赖安装步骤。已通过 Node 和 PowerShell 语法检查、实验启动脚本 `-CheckOnly`、挂件入口 `-CheckOnly`。完整 Node 测试为 **35/35 通过**，包括本机模拟 CDP 的导入、默认关闭、启用、应用、恢复、排除其他应用页面和头像层，以及与 Dream Skin 的冲突保护；完整 Windows 既有测试通过，包括 21 项隔离安装检查、7 项生命周期检查、入口、布局和挂件测试。新增 `tests/wallpaper-ui.test.ps1` 也通过，检查旧设置菜单、壁纸默认关闭，以及 PowerShell 5.1 能真正启动壁纸后台进程。测试数据保留在工作区 `verification-data`；既有测试仅清理本轮创建的临时文件，用户已授权该范围。

实机测试将项目现有 `assets/gpt-dragon-niang-bust.png` 导入独立测试目录：Codex 主页面 1/1 应用成功，`body` 的计算背景包含该 PNG，`#root` 和页面表面透明；恢复后本模块样式和标记均消失，开关最终关闭。测试没有改动正式 GPT 娘数据或 Codex 安装文件。正式运行目录与原源码目录在此前测试后和 50 文件备份逐项比较，哈希差异为 0。

本次测试结束后再次核对：正式目录和原源码的 50 个备份文件差异仍为 0，Codex 页面没有残留本模块样式。用户选择让 Codex Dream Skin 继续保持暂停；其 `C:\Users\user\AppData\Local\CodexDreamSkin\paused` 标记仍在，未获用户同意前不删除。现有 Codex 会话的 9335 调试端口仍会开放，直到完全退出客户端并按普通方式重启。

用户试用时发现壁纸只在侧边可见，中央仍是黑色。检查定位到 `[data-app-shell-main-surface]` 的不透明背景，第一次修正为 42% 遮罩后，用户截图显示聊天文字背后太亮、输入区背后出现黑块。进一步检查发现聊天滚动区另有不透明底色和渐变。现已把中央默认遮罩调至 60%，增加 20%～85% 的设置滑块，并仅移除聊天滚动区的底色和渐变。重新应用后的实机截图显示底部黑块消失，中央壁纸可见；最终明暗仍以用户试用感受为准。该次修正通过 35/35 Node 测试和完整 Windows 测试。

用户再次指出顶部横条仍有明显明暗分界。检查当前 Codex 页面发现：顶部菜单栏没有遮罩，中央使用滑块暗度，侧栏固定为 65% 深色，聊天区顶部另有约 40px 的深色渐变。实验版现将暗度统一作用于底层整张壁纸，并在壁纸模式下移除中央、侧栏和聊天区顶部的重复遮罩。正式样式已重新应用；实机计算样式确认主内容区和侧栏透明、顶部渐变消失，临时预览截图也显示横向分界消失。用户回到聊天页面后确认明暗已基本一致。本轮 Node 测试 35/35 通过，完整 Windows 既有测试通过。

### 2026-10-18：资料库与插件页头

这两个页面的固定页头通过 `::before` 额外绘制不透明背景。壁纸模式现仅清除主内容区内、带 `data-app-shell-inline-page-header` 标记的固定可折叠页头背景。实机两页的该层计算背景均变为透明，顶部截图确认横条消失；搜索框、操作按钮和内容卡片保留。现有壁纸测试 4/4 通过，Node 语法检查通过。项目内容区的背景问题留待单独处理。正式安装同步前的模块备份在工作区 `backup/pre-library-plugin-header-2026-10-18/codex-wallpaper.mjs`。

### 2026-10-19：项目页与站点页背景

项目页和站点页都在主内容焦点区域的直属子节点上绘制 `bg-surface` 不透明背景；站点页还在内容容器及当前标签页容器上重复绘制同色背景。项目页固定页头的 `::before` 也绘制不透明背景，但该页头没有资料库、插件使用的 `data-collapsible` 标记。实验样式仅清除这些全页背景层和主内容区固定页头的伪元素背景，保留按钮、输入框及内容卡片的原有表面。当前 Codex 会话的两页计算背景已确认透明，本地预览截图显示壁纸连续可见；资料库、插件和聊天主页也已重新查看，未见原有页头修复回退。侧边聊天仍需定位具体视图。

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

稳定版源码已在本地 Git 的 `stable/v1.2.5` 分支提交，并上传到私人仓库 `xyd830959-sketch/GPTPET` 的 `main` 分支；远端提交为 `b28dc238692cb7ea80c219ee4f3b3668ea3c613c`。实验版仍在本地 `feature/codex-wallpaper` 分支，未合并、未上传，也未发布安装包。

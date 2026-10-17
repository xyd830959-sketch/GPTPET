# GPT娘额度挂件

这是 GPT 娘额度挂件的源码目录。Windows 挂件随 Codex 主窗口显示额度、语录，并在设置菜单提供可选的 Codex 壁纸功能。

- `Install.ps1`：检查依赖并安装；`-CheckOnly` 只检查，不修改系统。
- `widget.ps1` / `widget.xaml`：Windows WPF 挂件与界面。
- `runtime/mcp.mjs`：只读额度查询工具。
- `runtime/supervisor.ps1`：识别主窗口并自动恢复角色。
- `runtime/host-layer.ps1`：主窗口归属与遮挡顺序。
- `runtime/codex-wallpaper.mjs` / `runtime/wallpaper-ui.ps1`：本地壁纸导入、应用、暗度调整和恢复默认背景。
- `assets/quotes.json`：内置中文语录。
- `tests/`：额度、刷新队列、挂件及壁纸测试。

`installation.json` 在本机安装时生成，不包含在仓库中。默认个人数据位于 `%LOCALAPPDATA%\GPTNiangUsage\state`，停用后保留。

额度气泡在原有尺寸内显示剩余百分比、进度条和重置时间。展开动画结束后，前 2 秒显示距离重置多久，后 3 秒显示固定日期和重置时刻，然后自动收起；再次点击角色或刷新时重新计时。重置时刻、今日／明日及更新时间均按当前 Windows 机器的本地时间显示；悬停气泡可查看完整日期、时区偏移与倒计时。缺少重置时间时会明确提示，过期的额度等待刷新。

交互实现范围见[DSH功能对照](DSH功能对照.md)，图片生成来源见[素材说明](assets/生成说明.md)。

## Codex 壁纸

在挂件上右键打开设置，进入“Codex 个性化”。导入 PNG、JPG 或 WebP 图片后，打开“启用壁纸功能”，点击“应用壁纸”。可以用“壁纸暗度”滑块调节明暗；“恢复默认背景”移除本模块在当前页面注入的样式。新安装时壁纸开关默认关闭，壁纸状态单独保存在 `%LOCALAPPDATA%\GPTNiangUsage\state\codex-wallpaper`。

壁纸应用需要 Codex 当前会话开放本机调试连接 `127.0.0.1:9335`。如果连接不可用，挂件的原有额度功能继续工作。此功能不修改 Codex 官方安装文件或核心配置；关闭 Codex 会话后，注入样式也会消失。Codex 更新可能影响页面兼容性，且目前没有自动重涂、轮换或动态壁纸功能。

原[实验记录](WALLPAPER_EXPERIMENT.md)保留了开发和实机验证过程。运行 `node --test tests/*.test.mjs` 可执行 Node 测试，运行 `powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/run-windows-tests.ps1` 可执行 Windows 挂件测试。

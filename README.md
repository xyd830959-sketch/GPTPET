# GPTPET

GPTPET 是 [GPT-Niang](https://github.com/T7moris/GPT-Niang) **v1.2.5 的 Windows 衍生版本**，由 [xyd830959-sketch](https://github.com/xyd830959-sketch) 维护。继承上游的 Codex 额度与语录挂件，增加可选的本地壁纸功能。它不是 OpenAI 官方项目，也不提供或增加订阅额度。

当前源码版本：`1.2.5-gptpet.1`（候选版本，尚未发布）。原项目作者和贡献者的版权保留；角色图片不属于代码的 MIT 授权范围。[来源与许可](THIRD_PARTY_NOTICES.md)

## 来源、许可与审阅范围

原 GPTPET 仓库现已公开。本版本在提交 `bd4a972d5ff9fce4db3936ca188e7f87de5db5ed` 的工程准备基础上，整合保留龙娘的来源与素材说明；原开发历史保留，不伪装为全新原创。此前另行导出的本地源码快照不携带 `.git`，这与本仓库保留历史是两回事。[候选导出与整合来源](docs/CANDIDATE_ORIGIN.md)

本版本按用户选择保留龙娘图片，图片字节及上游声明均未改变。**代码与一般文档为 MIT；龙娘图片及派生图标不适用 MIT**，须遵守随附的单独声明和第三方权利边界。不得把整个含图副本描述为全部素材均可按 MIT 自由商用。[逐项素材范围](docs/ASSET_SCOPE.md)

## 功能与贡献范围

| 来源 | 内容 |
| --- | --- |
| 继承 GPT-Niang v1.2.5 | PowerShell/WPF 额度与语录挂件、Node.js 只读额度 worker、窗口跟随与安装生命周期 |
| GPTPET 后续改动 | PNG/JPG/WebP 壁纸导入、20%—85% 暗度调节、应用与恢复、独立启动器和加载重试、部分页面背景兼容与相关测试 |

壁纸初始关闭。它使用本机调试连接修改当前 Codex 页面的样式；客户端更新可能使它失效。没有动态壁纸、轮换或跨设备同步。源码和基线提交见 [PROVENANCE](docs/PROVENANCE.md)，版本记录见 [CHANGELOG](CHANGELOG.md)。

## 运行条件

- Windows 10/11、Windows PowerShell 5.1、WPF 和 Windows Script Host。
- Node.js **22 或更新版本**；壁纸模块依赖内置 WebSocket。本项目不安装 npm 依赖。
- 已安装并用本人 ChatGPT 账号登录的 Codex 桌面客户端。安装器需要能找到其 `codex.exe`；独立壁纸启动器当前只支持 `OpenAI.Codex` Store 安装。
- 仅包含 Windows 实现；不继承上游后续版本的 macOS 支持或新套餐适配承诺。[兼容范围](docs/COMPATIBILITY.md)

## 从源码使用

1. 将完整源码保存在长期使用的目录。保留隐藏的 `.agents`、`.codex-plugin` 和 `.mcp.json`。
2. 先安装 Node.js 并打开 Codex。运行 `powershell.exe -NoProfile -File .\Install.ps1 -CheckOnly`，检查文件、安装身份和依赖。检查不会安装插件或注册启动项。
3. 阅读 [安装影响和退出方法](docs/INSTALLATION.md)，确认愿意更改本机插件登记、启动项和用户计划任务后，再运行 `安装GPT娘.cmd`。
4. 挂件中点击角色查看额度，点击气泡切换语录，右键打开设置。

安装器使用本仓库自带的本地 marketplace。插件技术标识仍为 `gpt-niang-usage@gpt-niang-local`，用于兼容既有安装；显示名称和维护者信息已区分 GPTPET 与上游。若已有其他目录的原版安装，先按文档处理，不能直接覆盖其注册。

## 可选壁纸

在右键设置的“Codex 个性化”中导入本人有权使用的图片、启用壁纸并调节暗度。需要 `127.0.0.1:9335` 上的 Codex 调试会话。通过 `打开Codex壁纸模式.cmd` 或安装后的对应快捷方式启动；启动器不会强制关闭正在使用的客户端。

调试端口没有身份认证，同一电脑上的其他进程可能访问。关闭壁纸开关仅尝试恢复样式；要结束调试会话，完全退出 Codex，再从普通官方入口重新启动。默认新建独立配置目录，不自动复制其他软件的登录配置。[完整安全说明](SECURITY.md)

## 开发、测试与反馈

先运行 `npm run check`。自动测试会创建并清理合成测试数据，运行前须明确选择专用目录并同意该范围的清理；操作方式、测试分层及实机验收见 [DEVELOPMENT](docs/DEVELOPMENT.md)。自动测试通过不等于全部桌面交互已通过实机验证。 基准提交的已验证结果及本地候选的验证边界见 [验证记录](docs/VALIDATION.md)。

通过 [GitHub Issues](https://github.com/xyd830959-sketch/GPTPET/issues) 提供脱敏的版本、复现步骤和预期结果；仓库已公开；反馈和贡献可通过公开页面进行。贡献规则见 [CONTRIBUTING](CONTRIBUTING.md)。请勿上传账号文件、聊天、完整配置或私人壁纸。

## 许可

代码与一般文档沿用 [MIT License](LICENSE)，保留原版权行。角色图片、派生图标及第三方参考权利另行处理，不能视作 MIT 商用授权；当前附带图片限于权利人允许的用途。[第三方与素材说明](THIRD_PARTY_NOTICES.md)

当前没有经核实的外部用户数、下载量或生态影响力数据；上游的 stars、forks 和用户不属于 GPTPET 的指标。

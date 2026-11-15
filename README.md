# 灵剪组件工坊

为灵剪的灵动岛开发社区小组件。组件使用 JavaScript 返回卡片数据，由灵剪原生渲染，支持点阵科技、卡证拟物两种主题和单格、双格布局。

本仓库提供 Widget API 1、命令行工具、示例、公共组件目录，以及 Codex / Claude Code Skill。基础版本的发布包和目录托管在 GitHub，目录收录通过 Pull Request 审核。

## 运行条件

- 开发工具使用 Node.js 20 或更高版本。
- 发布和提交使用已登录的 GitHub CLI。
- 在 App 中安装需要支持 Widget API 1 的灵剪 macOS 版本，macOS 14 或更高。本仓库的宿主协议与运行器源码位于 `host/`，灵剪宿主已接入开发构建。

## 开发一个组件

```bash
git clone https://github.com/hanhang-han/cliperx-widgets.git
cd cliperx-widgets
node bin/widget.mjs create ../my-widget --id com.yourname.my-widget --name 我的组件 --author yourname
node bin/widget.mjs validate ../my-widget
node bin/widget.mjs preview ../my-widget
node bin/widget.mjs pack ../my-widget --out dist
```

修改生成的 `manifest.json` 和 `widget.js`。查看 [协议和示例](skills/cliperx-widget-development/references/protocol.md)，类型提示位于 [lib/sdk.d.ts](lib/sdk.d.ts)。TypeScript 项目应先编译成单个 `widget.js`。

打包生成 `.cliperxwidget` 文件，在灵剪「设置 → 小组件 → 创意工坊 → 导入组件」安装，也可以用灵剪打开组件包。安装页显示作者、版本和所需权限，安装后在「已安装」中添加到灵动岛。单排共 8 格，满额时先调整已有组件大小或移除一个。

## 示例

| 组件 | 功能 | 网络权限 |
|---|---|---|
| [专注计时](examples/focus-timer) | 开始、暂停、重置、原生倒计时、可配置时长 | 本地运行 |
| [GitHub 仓库](examples/github-stars) | Star、Fork、Issue、点击打开仓库、可配置仓库 | api.github.com |

```bash
node bin/widget.mjs preview examples/focus-timer --action toggle
node bin/widget.mjs preview examples/github-stars --live
node bin/widget.mjs pack examples/focus-timer
```

开发预览在 Node 中执行自己的脚本。App 使用独立、带 App Sandbox 的 JavaScriptCore 运行器。可在 macOS 使用相同运行器验收。

```bash
bash host/build-runner.sh
node bin/widget.mjs preview examples/focus-timer --action toggle --runner dist/CliperXWidgetRunner
```

## 上传到工坊

先把组件源码提交并推送到自己的公开 GitHub 仓库，再发布版本并提交收录。

```bash
node /path/to/cliperx-widgets/bin/widget.mjs publish /path/to/my-widget --repo yourname/your-repository
node /path/to/cliperx-widgets/bin/widget.mjs submit --entry /path/to/your-repository/dist/com.yourname.my-widget.entry.json
```

`publish` 上传不可覆盖的 GitHub Release 包，并生成包含 SHA256、源码提交和下载地址的目录条目。`submit` 创建工坊目录 PR，其他用户在 PR 合并后即可刷新工坊安装。[完整发布说明](skills/cliperx-widget-development/references/publishing.md)

## 安装 Codex / Claude Code Skill

克隆本仓库后，按使用的工具创建目录链接。

```bash
mkdir -p ~/.codex/skills
ln -s "$PWD/skills/cliperx-widget-development" ~/.codex/skills/cliperx-widget-development

mkdir -p ~/.claude/skills
ln -s "$PWD/skills/cliperx-widget-development" ~/.claude/skills/cliperx-widget-development
```

可以告诉 Codex「使用 `$cliperx-widget-development` 开发一个显示 GitHub Star 的灵剪组件并上传到工坊」，或在 Claude Code 中使用 `/cliperx-widget-development`。链接已存在时沿用现有安装位置。

## 宿主和目录维护

- `host/WorkshopContract.swift` 是包、清单和输出校验协议，`host/WorkshopRunner.swift` 是运行器。
- `registry/index.json` 是 App 读取的组件目录，包下载时由 App 校验 SHA256 和完整清单。
- 更新发布应递增组件版本，用户更新时会重新看到权限声明。
- 组件实例分别保存配置和状态，组件卸载后布局保留，重新安装可以恢复。
- `npm test` 验证打包、配置替换、输出限制和示例交互。

## 许可

SDK、开发工具、示例和 Skill 使用 [MIT](LICENSE) 许可。社区作者在组件清单中声明各自许可证，并负责所提交代码和资源的授权。

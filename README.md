# 灵剪组件工坊

为灵剪的灵动岛开发社区小组件。组件使用 JavaScript 返回卡片数据，由灵剪原生渲染，支持点阵科技、卡证拟物两种主题和单格、双格布局。

本仓库提供 Widget API 1/2/3/4、命令行工具、示例、公共组件目录，以及 Codex / Claude Code Skill。工坊网站支持账号登录、包上传和审核。已有 GitHub Release 与目录 PR 发布工具继续可用。

## 运行条件

- 开发工具使用 Node.js 20 或更高版本。
- 工坊投稿使用已有灵剪账号，GitHub Release 发布与目录 PR 使用已登录的 GitHub CLI。
- 在 App 中安装需要支持组件所声明 Widget API 的灵剪 macOS 版本，macOS 14 或更高。本仓库的宿主协议与运行器源码位于 `host/`，灵剪宿主已接入开发构建。

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

从当前灵动岛布局起步，可用 `--template info` 创建顶部信息卡，或用 `--template task-context` / `--template task-text` / `--template task-basket` 创建单格任务卡。任务卡复用剪贴板下方的原生工作区；脚本负责卡片内容和操作，不负责绘制原生任务区。选型和限制见 [基础组件](skills/cliperx-widget-development/references/base-components.md)。

打包生成 `.cliperxwidget` 文件，在灵剪「设置 → 小组件栏 → 创意工坊 → 导入组件」安装，也可以用灵剪打开组件包。安装页显示作者、版本和所需权限，安装后在「已安装」中添加到灵动岛。单排共 8 格，满额时先调整已有组件大小或移除一个。

## 示例

| 组件 | 功能 | 网络权限 |
|---|---|---|
| [专注计时](examples/focus-timer) | 开始、暂停、重置、原生倒计时、可配置时长 | 本地运行 |
| [Bug 单整理](examples/bug-report) | 作者定义输入、表单和指令，使用本机 Codex 整理证据与 Bug 单 | API 4 上下文任务 |
| [上下文准备](examples/context-preparation) | 岛内多选、任务输入、真实 Codex 对话和来源预览 | API 2 原生能力 |
| [文本处理](examples/text-processing) | 改写、总结、翻译、本机清理 | API 2 原生能力 |
| [AI 用量](examples/ai-usage) | Codex / Claude 剩余额度、重置天数和缓存状态 | API 2，本机 CodexBar |
| 收集篮基础模板 | `create --template task-basket`，共用原生收集篮任务区 | API 2 原生能力 |
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

使用浏览器登录已有灵剪账号，再上传本地组件包。macOS 的工坊令牌保存在系统钥匙串，其他开发系统保存在仅当前用户可读的配置文件。

```bash
node bin/widget.mjs login
node bin/widget.mjs upload ../my-widget --source https://github.com/yourname/my-widget
node bin/widget.mjs status
node bin/widget.mjs status SUBMISSION_ID
```

`upload` 执行打包、建立草稿、上传和提交审核，打印真实投稿 ID、版本、SHA256 与状态。使用 `--draft` 可以只保存草稿，再通过 `submit --submission ID` 提交。待审稿可用 `withdraw ID` 撤回后修改。公开版本的内容需要递增版本号再上传。

组件工程可提供 `workshop.json`，填写 `category`、`tags`、`readme`、`changelog`、`minAppVersion` 和 `feedbackURL`，也可以用 `--metadata FILE` 指定。截图在网页投稿页上传。使用 `--api URL` 对接明确的本地开发服务，默认地址为 `https://api.cliperx.com/api/workshop`。

已有 GitHub Release 条目可以导入同一审核流程。

```bash
node bin/widget.mjs publish ../my-widget --repo yourname/your-repository
node bin/widget.mjs import --entry dist/com.yourname.my-widget.entry.json
```

已有目录 PR 流程仍可使用 `submit --entry FILE --catalog owner/catalog`。完整说明见 [发布文档](skills/cliperx-widget-development/references/publishing.md)。

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

## 官方 AI 组件

三个 AI 组件要求支持 Widget API 2 的灵剪开发构建。默认执行端为本机已登录的 Codex CLI，也可选择可用的 Apple Intelligence 或配置自己的 OpenAI 兼容接口 / Ollama。AI 用量读取用户本机 CodexBar 的已登录账户。

核心逻辑与 SwiftUI 集成源码位于 [host/integration](host/integration)。待开发方向记录在 [BACKLOG.md](BACKLOG.md)。


## 统一可拔插宿主

API 3 将内置原生组件和外部脚本组件接入同一注册、安装和生命周期管理。`examples/native-*` 提供官方原生声明，可独立打包更新。创建、配置和开发方法见 [基础组件文档](skills/cliperx-widget-development/references/base-components.md)。

原生模板可使用 `native-music`、`native-agent`、`native-metric`、`native-basket`。原生声明包提供 manifest，标准脚本包提供 manifest 和 widget.js。CLI 预览原生包时输出声明，实际原生界面由 App 提供。

## 开发自定义 AI 组件

使用 `task-ai` 模板定义接受的材料、参数、指令和 Markdown 结果，宿主提供选材、表单、任务进度、取消、重试和结果复制。

```bash
node bin/widget.mjs create ../my-ai --id com.yourname.bug-report --name 我的Bug单 --author yourname --template task-ai
node bin/widget.mjs validate ../my-ai
node bin/widget.mjs preview examples/bug-report --fixture examples/bug-report/preview.json
node bin/widget.mjs pack ../my-ai
```

`manifest.task.prompt` 可引用 `{{question}}` 和 `{{parameters.KEY}}`。参数内的内容按原文填入，未知变量会在打包时报告错误。`preview --fixture FILE` 从 fixture 的 parameters 与 question 展示实际任务指令，缺少必填值时显示具体参数错误。真实 AI 执行需要支持 Widget API 4 的灵剪及本机已登录的 Codex。

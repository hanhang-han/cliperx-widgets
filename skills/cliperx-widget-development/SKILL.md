---
name: cliperx-widget-development
description: 开发、预览、打包灵剪 CliperX 社区小组件，并在用户要求上传或发布时通过工坊账号提交审核，也可沿用 GitHub Release 和目录 PR。适用于编写 Widget API 1/2/3/4 组件及修改现有组件。
---

# 灵剪社区组件

使用 Widget API 1/2/3/4 开发可安装的 `.cliperxwidget` 包。先阅读 [协议](references/protocol.md)；从现有岛内布局起步时阅读 [基础组件](references/base-components.md)；发布时阅读 [上传流程](references/publishing.md)。

## 找到工具

官方仓库为 `https://github.com/hanhang-han/cliperx-widgets`。仓库内的 `bin/widget.mjs` 是工具入口，要求 Node.js 20+。优先使用当前工作区的克隆，或 `CLIPERX_WIDGETS_HOME` 指向的目录。缺少工具时可克隆到当前任务的工具目录。

## 开发与验收

1. 先区分纯展示组件与打开下方原生任务区的组件。需要复用音乐、指标、Agent 或收集篮的完整原生卡片时，使用 API 3 的 `native-music`、`native-metric`、`native-agent`、`native-basket` 或 `native-ccswitch` 模板。前者用 `info` 模板；后者按工作流用 `task-context`、`task-text` 或 `task-basket`。音乐和 AI 用量等无需选材的组件保持顶部操作。需要其他行为时从 `basic` 或官方示例起步。
2. 用 `create --template info|task-context|task-ai|task-text|task-basket` 初始化独立组件目录，填写真实作者和稳定的反向域名 ID。编辑 `manifest.json` 和 `widget.js`，不要沿用官方组件 ID。
3. 原生声明模板编辑 manifest 的 presentation 和权限，通过宿主注册中心加载。标准脚本模板用 `defineWidget` 提供同步 `render(context)` 和可选 `onAction(action, context)`。UI 使用宿主提供的卡片字段，状态使用 `context.state`，每个实例独立保存。
4. 原生任务模板使用 API 2，按模板声明 contextPreparation、textProcessing 或 collectionBasket 权限，并使用 `prepare`、`process` 或 `open` 主操作。宿主负责选材、输入、结果及收集篮的内容和粘贴。AI 用量可参考官方示例。脚本读取计数、可用性和标准化状态，原生任务区由已注册的宿主渲染器提供。API 3 支持 Agent 工作区、音乐效果及能力事件订阅，具体字段见协议。普通展示组件继续使用 API 1。
5. 自定义 AI 任务使用 `task-ai` 的 API 4 模板，在 manifest.task 声明输入类型和条数、表单参数、prompt 与 Markdown 输出。模板变量仅支持 `{{question}}` 和 `{{parameters.KEY}}`。原生宿主负责选材、凭据、运行和来源映射，脚本仍通过 context.prepare 打开任务区。先用 examples/bug-report 及其 preview.json 理解模板，再填写用户自己的要求。
6. HTTP GET 数据源写在清单中，宿主预取后通过 `context.data` 提供。检查无数据、服务错误及配置变化的行为。网络域名、系统指标、点击打开网页和写剪贴板按实际用途声明。
7. 执行 `validate`、`preview`，对点击操作执行 `preview --action ID`。联网组件可用 `--live` 验证真实数据，也可用 `--fixture` 提供确定的输入。自定义 AI 组件的 fixture 可包含 parameters 和 question，preview.taskPreview 显示指令或必填参数错误。
8. 在 macOS 可构建 `host/build-runner.sh`，用 `preview --runner PATH` 在 App 的相同沙箱运行器中验证。使用 App 验证卡片大小、主题、配置和点击行为。
9. 用 `pack` 生成包并报告真实输出路径、验证结果和仍需处理的限制。

运行器提供标准 JavaScript 和 JSON 上下文。模块引用应在开发时打包进单个脚本。协议支持的系统能力见参考文档，界面和数据均按其中的大小限制生成。

## 发布

用户已经要求上传或发布时，在完成本地验收后继续执行发布。默认工坊流程为 `login` 浏览器授权，再执行 `upload DIR --source HTTPS_URL`，使用 `status ID` 查询审核状态。缺少源码仓库时可以填写组件工坊详情地址，真实作者和组件用途需完整。`workshop.json` 可提供分类、标签、使用说明、更新记录和兼容要求，截图通过网页上传。

`upload --draft` 保存草稿，`submit --submission ID` 提交审核。待审核内容需先 `withdraw ID` 撤回才能修改。已发布版本修改时递增 manifest.version。登录凭据由 CLI 存储，避免把令牌写进脚本或组件文件。

用户明确沿用 GitHub 分发时，提交并推送公开源码，执行 `publish` 生成 GitHub Release 与目录条目，再执行 `import --entry FILE` 导入工坊审核。已有目录 PR 入口为 `submit --entry FILE --catalog owner/catalog`。

交付中报告实际包路径、SHA256、投稿 ID 与状态。已上传、待审核和已发布分别对应真实结果。遇到登录、网络或权限阻塞时，保留已完成的包并说明具体失败。开发阶段以经过必要验证的组件和可安装包为交付，发布授权范围沿用用户当前请求。

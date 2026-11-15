---
name: cliperx-widget-development
description: 开发、预览、打包灵剪 CliperX 社区小组件，并在用户要求上传或发布时通过 GitHub Release 和目录 PR 提交到创意工坊。适用于编写 Widget API 1/2 组件及修改现有组件。
---

# 灵剪社区组件

使用 Widget API 1/2 开发可安装的 `.cliperxwidget` 包。先阅读 [协议](references/protocol.md)，发布时阅读 [上传流程](references/publishing.md)。

## 找到工具

官方仓库为 `https://github.com/hanhang-han/cliperx-widgets`。仓库内的 `bin/widget.mjs` 是工具入口，要求 Node.js 20+。优先使用当前工作区的克隆，或 `CLIPERX_WIDGETS_HOME` 指向的目录。缺少工具时可克隆到当前任务的工具目录。

## 开发与验收

1. 根据用户需求决定组件名称、单格或双格、数据源和点击操作。优先使用现有模板与两个官方示例。
2. 用 `create` 初始化独立组件目录，填写真实作者和稳定的反向域名 ID。编辑 `manifest.json` 和 `widget.js`。
3. 用 `defineWidget` 提供同步 `render(context)` 和可选 `onAction(action, context)`。UI 使用宿主提供的卡片字段，状态使用 `context.state`，每个实例独立保存。
4. AI 组件使用 API 2，按用途声明 contextPreparation、textProcessing、aiUsage。素材选择与模型配置通过原生能力操作完成，脚本仅读取计数、可用性和标准化额度。普通组件继续使用 API 1。
5. HTTP GET 数据源写在清单中，宿主预取后通过 `context.data` 提供。检查无数据、服务错误及配置变化的行为。网络域名、系统指标、点击打开网页和写剪贴板按实际用途声明。
6. 执行 `validate`、`preview`，对点击操作执行 `preview --action ID`。联网组件可用 `--live` 验证真实数据，也可用 `--fixture` 提供确定的输入。
7. 在 macOS 可构建 `host/build-runner.sh`，用 `preview --runner PATH` 在 App 的相同沙箱运行器中验证。使用 App 验证卡片大小、主题、配置和点击行为。
8. 用 `pack` 生成包并报告真实输出路径、验证结果和仍需处理的限制。

运行器提供标准 JavaScript 和 JSON 上下文。模块引用应在开发时打包进单个脚本。协议支持的系统能力见参考文档，界面和数据均按其中的大小限制生成。

## 发布

用户已经要求上传或发布时，在完成本地验收后继续执行发布。使用明确的公开目标仓库，提交并推送组件源码，然后执行 `publish` 生成 GitHub Release 与目录条目，再执行 `submit` 创建工坊收录 PR。

每次修改公开版本递增 `manifest.version`。保留 CLI 返回的下载地址、SHA256、源码提交和 PR 链接。最终交付中区分已上传发布包和已经合并进工坊的状态。GitHub 登录、网络或仓库权限存在实际阻塞时，保留已完成的包与目录条目并说明具体失败。

涉及普通组件开发请求时，以经过验证的组件和可安装包为交付。发布授权范围沿用用户当前请求，Skill 本身提供工作流程。

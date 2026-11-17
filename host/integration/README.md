# API 2 宿主集成

这些 Swift 文件为灵剪 macOS 原生 AI 组件实现快照，使用仓库 MIT 许可。

- `WorkshopAICore.swift` 提供上下文整理、预算、文本变换和会话数据结构。
- `IslandAIWorkspace.swift` 管理选材、实例草稿、当前会话、流式回答及逐条文本处理。
- `WorkshopAIViews.swift` 提供岛内问答、文字与图片附件和历史对话选择。
- `WorkshopTextProcessing.swift` 提供翻译语言、请求缓存指纹和流式响应解析，`WorkshopTextProcessingView.swift` 提供单卡即时处理与来源设置。
- `WorkshopAnswerView.swift` 渲染 Markdown，`WorkshopConversationContent.swift` 保存材料信息和来源映射。
- `WorkshopCodexConversation.swift` 通过 Codex App Server 创建和续接真实会话，分页读取历史，接收回答增量。
- `WorkshopContextRuntime.swift` 准备图片附件，并创建本次调用使用的只读灵剪 MCP 凭据。
- `WorkshopCodexClient.swift` 为文本处理提供 Codex CLI 适配。
- `WorkshopAI.swift` 提供组件入口、模型请求、Keychain 和用量读取。

## 宿主接线

宿主需要现有的 `ClipboardLibrary`、隐私过滤、`ClipboardMCPServer`、`ClipboardMCPConfiguration`、`PasteQueueService`、岛内布局及应用服务。将原生文件加入应用 target，并在退出时调用 `IslandAIWorkspace.shared.flushDrafts()`。

API 2 组件使用 `contextPreparation`、`textProcessing`、`aiUsage`、`collectionBasket` 权限。脚本仅读取标准化计数和状态，用户点击后由宿主执行原生操作。声明相应权限并以 `prepare`、`process` 或 `open` 作为卡片主操作的组件，在权限检查后即时切换原生任务区；上下文和文本任务按实例保存，收集篮是全局共享队列。单格任务与信息卡的宿主样式见灵剪 `WorkshopViews.swift`。

收集篮由 `PasteQueueService` 保存有序条目 ID。自动收集只处理本机新捕获且通过隐私过滤的内容；脚本获得条数、收集开关、展开和粘贴状态，不获得条目正文。用户在原生界面加入、排序、移除与粘贴，关闭任务区或自动收集后队列仍保留。

`ClipboardLibrary.widgetContextMaterial(id:includeImages:)` 在手动选材和发送时重新检查来源与隐私。上下文问答允许图片，文本处理使用文字。剪贴板卡片在上下文模式中单击选择，支持 Command 点选、空格预览和 Esc 先关闭弹层。问答按钮使用 Command Return。

## Codex 问答

用户在灵动岛中选择新建 Codex 对话，或搜索并续接真实的历史对话。文字与图片随问题发送，回答和后续追问在岛内展示。历史消息按需分页加载。已发送附件随消息保留，输入栏可继续准备下一轮材料。

图片经 ImageIO 处理为 PNG，长边最多 2560 像素，文件保存在私有媒体目录，权限为 0600。Codex 通过 `localImage` 接收图片。持久化图片路径供历史会话续问时使用。

灵剪 MCP 为每次调用的可选能力。开启时，宿主创建只读连接，并通过本次 App Server 会话配置提供 `search`、`read_item`、`list_pinboards`。用户手动选择的附件始终随问题发送。调用结束或取消后撤销该连接凭据。配置通过本次执行进程传递。

MCP 状态查询按 `cliperx_island` 服务名检查本次连接，初始化期间等待该连接就绪，授权和连接错误分别反馈。会话列表、历史阅读与输入草稿由各自的取消和恢复逻辑管理。

## 紧凑问答界面

官方上下文组件使用单格尺寸。附件、问题输入、会话选择、MCP 开关和发送操作集中在底部输入卡，默认显示两个附件，其余材料通过数量入口管理。回答区域随实际内容增长，最多 420 点，并受当前屏幕和窗口可用高度约束，长回答在区域内滚动。SwiftUI 高度测量合并更新，输入卡在屏幕可用高度内优先展示。错误与重试使用输入卡内的反馈行。

## 即时文本处理

文本处理默认翻译，点选一张文字卡片即开始执行。语言、来源和默认动作由原生宿主保存，翻译源包含灵剪后端、Codex、自定义 OpenAI 兼容接口，并保留可用的 Apple Intelligence。切换卡片或设置会取消旧任务，按原文、动作、语言、来源和接口配置复用最近 20 个成功结果。原文与结果可切换查看。

灵剪后端复用带设备鉴权的 `/api/ai/chat`，兼容接口读取 OpenAI SSE 或 JSON，Codex 使用临时 App Server 会话流式回传。结果区按内容自适应，最多 420 点，并服从屏幕和窗口高度限制。密钥按接口地址保存在系统钥匙串，脚本仅获得 `appleAvailable`、`actionTitle` 和 `busy` 元数据。


## API 3 组件宿主

当前 App 使用 WidgetPluginRegistry 统一注册卡片与工作区渲染器，并管理组件实例、脚本刷新、事件订阅和宿主服务。内置原生组件由独立声明包提供，主 App 继续提供音乐、指标、Agent、剪贴板与模型接口。

原生声明和开发方法见 `skills/cliperx-widget-development/references/base-components.md`。包协议与运行器使用上一级目录中的 WorkshopContract.swift，原生渲染器和生命周期集成以主 App 的 IslandWorkspace/WidgetPluginRegistry.swift 为准。

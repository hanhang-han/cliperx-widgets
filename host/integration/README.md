# API 2 宿主集成

这些 Swift 文件为灵剪 macOS 开发构建中的原生 AI 能力实现快照，使用仓库 MIT 许可。

- `WorkshopAICore.swift` 包含带预算与来源的上下文整理、本机文本变换、CodexBar JSON 标准化逻辑。
- `WorkshopAI.swift` 包含原生会话、模型请求、Keychain 凭据存储、用量读取与窗口入口。
- `WorkshopAIViews.swift` 提供选材与文本处理的 SwiftUI 界面。

它们与灵剪现有 `ClipboardLibrary`、`ClipboardAIPrivacy`、`ClipboardLocalModel`、`ClipboardOnDeviceWriter`、`ClipboardAIDeadline`、`IslandWidgetPreferences` 协作。可独立复用核心逻辑，原生集成文件需要对应的宿主服务。

## 宿主接线

1. 包验证接受 API 1、2，AI 权限仅允许 API 2。安装页显示 `WorkshopPermissions.summary`。
2. 运行前通过 `WorkshopAIHost.shared.context(instance:permissions:)` 合并已授权的标准化上下文。
3. 仅用户点击允许执行原生效果，按 effect.type 分别检查 contextPreparation、textProcessing、aiUsage 权限，value 必须为空字符串。
4. 通过 `WorkshopAIHost.shared.perform(_:instance:)` 打开原生界面或刷新用量。刷新用量后重新渲染卡片，同一实例的执行保持串行。
5. `ClipboardLibrary.widgetContextCandidates(query:)` 原生读取最近 100 条文字。`widgetContextMaterial(id:)` 在每次预览和复制前重新获取已选择条目，检查 `ClipboardAIPrivacy.permits`，排除图片与文件。返回 `WorkshopContextMaterial`。
6. 可在剪贴板文字卡片右键菜单接入 `WorkshopAIHost.shared.addContextItem(_:)`。

上下文整理仅读取用户选中的文字。模型处理使用用户在原生界面提供的文本与指令。用量读取通过固定的 CodexBar CLI 参数进行，并在数据进入组件脚本前去除身份与账务字段。

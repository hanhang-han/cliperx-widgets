# 用 CliperX 为 Codex 准备带来源的上下文

这个示例把用户在灵动岛中选择的文字和图片交给原生宿主，由宿主准备上下文并向 Codex 提问。它复用本目录已有的 `manifest.json` 和 `widget.js`，不是另一个 Agent 框架，也不是让脚本无限读取剪贴板的插件。

**适用范围：开发者示例 / 兼容的灵剪开发构建。本文不代表官网稳定版已经提供全部能力。**

## 版本与可复现范围

本文核对的源码基线是 [`24cc199268356479c5b3cd3c30bbc5fc117587e2`](https://github.com/hanhang-han/cliperx-widgets/tree/24cc199268356479c5b3cd3c30bbc5fc117587e2)，上下文组件版本为 **0.3.1，Widget API 2**。

| 层级 | 可以验证什么 | 不能由此证明什么 |
|---|---|---|
| Node.js CLI | 清单校验、卡片渲染、点击产生的原生操作请求、打包 | App 已安装、真实模型回答或 MCP 服务可用 |
| macOS 原生 smoke tests | 仓库中上下文整理及会话状态逻辑；部分依赖使用 stub | 完整 App 的端到端行为、真实 Codex/MCP 连接 |
| 兼容的灵剪开发构建 | 在 App 中选材、提问、查看来源以及可选 MCP 的实际验收 | 未验收的稳定版和其他版本具有同等能力 |

[PR #3](https://github.com/hanhang-han/cliperx-widgets/pull/3) 是 **0.1.0 的目录登记提案**，修改的是 `registry/index.json`，并非本目录 0.3.1 的实现来源。2026-11-19 核查时该 PR 仍未合并；不要把其旧 Release 包当成本示例当前版本。

## 一、无需账号的本地复现

要求 Node.js 20+ 和 Git。以下命令只验证现有示例，不上传组件、不创建账号、不调用模型。

```bash
git clone https://github.com/hanhang-han/cliperx-widgets.git
cd cliperx-widgets
git checkout --detach 24cc199268356479c5b3cd3c30bbc5fc117587e2

npm test
node bin/widget.mjs validate examples/context-preparation
node bin/widget.mjs preview examples/context-preparation
node bin/widget.mjs preview examples/context-preparation --action prepare
node bin/widget.mjs pack examples/context-preparation --out dist
```

在这个固定源码基线上，预期结果是：

- `npm test`：21 项测试通过。
- `validate`：`Valid API 2 widget: com.cliperx.context-preparation v0.3.1`。
- 不传宿主状态的 `preview`：卡片显示“问 Codex”和“等待宿主 API 2”；这不是连接失败，也不是模型回答。
- `preview --action prepare`：`effects` 中出现 `{"type":"context.prepare","value":""}`，表示向宿主请求打开原生上下文任务区。
- `pack`：生成 `dist/com.cliperx.context-preparation-0.3.1.cliperxwidget`。本基线实测 SHA256 为 `dbfb416190e9fb29b5a195dfaadce84b9a28ace8e3a200bd810d8cb6ef55817f`。修改源码后应重新计算，不能沿用该值。

2026-11-19 在 Linux、Node.js v24.22.3 上实跑了上述测试、校验、两种预览和打包。21 项测试通过；此次未在 macOS App 中做真实 Codex 或 MCP 端到端验收。

## 二、在开发构建中做一个真实问答案例

前提：macOS 14+、支持上述 Widget API 2 集成的灵剪开发构建，以及已安装并登录的本机 Codex CLI。**只克隆这个仓库不能构建完整灵剪 App**；宿主快照还依赖主应用的剪贴板库、隐私过滤、MCP 服务和窗口布局，详见 [宿主集成说明](../../host/integration/README.md)。目前本文没有可保证复现的稳定版 App 构建编号，请先向维护者核实兼容开发构建。

使用无敏感信息的测试材料：

1. 在编辑器里分别复制两段文字，让它们成为两条记录：
   - 资料 A：`演示项目：团队希望在发布前检查下载页的英文标题。当前负责人是 Alex。`
   - 资料 B：`演示项目：上线前先验证英文页面可访问，再检查语言切换。没有确认上线日期。`
2. 按仓库首页的安装流程导入上一步生成的包，并将组件加入灵动岛。点击“选择材料”，只选这两条记录。
3. 第一轮保持灵剪 MCP 关闭，使用**新建对话**，输入：
   > 仅依据所选资料，整理待办、负责人和未知事项。每项标注对应资料来源，不要推测上线日期。
4. 发送前检查附件与问题。模型会接收所选内容；本机启动 Codex 并不意味着模型在本地推理，数据处理取决于实际配置的模型服务。
5. 验收回答是否区分事实与推断，是否保留可核对的来源，并明确上线日期未知。模型输出不固定，不能把上面的要求当作保证正确的预期答案。
6. 可继续追问“哪些事项还需要确认？”。只有在已获得授权且确有需要时才选择已有对话，避免把测试材料加入无关工作会话。

完整验收应记录 App 构建标识、Codex 版本、测试时间、实际结果与失败项。本教程不附伪造的回答或成功截图。

## 三、数据流、权限与边界

`widget.js` 只读取 `context.contextPack` 的计数和状态，点击后返回 `context.prepare`。选材、来源重检、上下文整理、图片处理和模型调用属于原生宿主，不在脚本中执行。

- 清单声明 `contextPreparation: true`，并未申请脚本网络域名、打开 URL、写剪贴板或系统指标权限。**空的脚本网络权限不等于宿主模型调用不会联网。**
- 文本上下文整理会去掉空白和重复内容，保留来源编号，并按估算预算裁剪。该估算不是模型提供商的精确计费 Token；问题、系统提示及图片也不能由这个数字代表总输入成本。
- 宿主在选材与发送时重新检查来源和隐私规则。隐私过滤不是绝对保证，仍应避免选入密码、凭据、私人客户资料。
- 代码中的 Codex 问答请求使用只读沙箱；它不是通用的自动改代码或自动发布示例。
- 图片附件会经过处理并保存在宿主私有媒体目录，以供历史会话使用。不要把“本次凭据撤销”误解为图片或对话记录自动删除。

### 可选的灵剪 MCP

默认 `useMCP = false`。需要补充历史资料时，用户可以显式开启；这会扩大到本机灵剪 MCP 提供的搜索和读取范围，**不再仅限于已选附件**。

实现为本次调用创建只读连接，启用 `search`、`read_item`、`list_pinboards`，并在调用完成或取消时尝试撤销该连接凭据。应在自己的开发构建中验证连接、取消及撤销结果。不要把令牌写入示例、仓库、截图或聊天记录。

## 四、实现与验证入口

- [组件清单](manifest.json) / [卡片脚本](widget.js)
- [上下文整理与预算](../../host/integration/WorkshopAICore.swift)
- [图片与本次 MCP 访问](../../host/integration/WorkshopContextRuntime.swift)
- [Codex 会话请求](../../host/integration/WorkshopCodexConversation.swift)
- [原生集成与依赖](../../host/integration/README.md)
- [Node 协议测试](../../tests/protocol.test.mjs)
- [原生核心测试](../../tests/native-ai-smoke.swift) / [原生状态测试（含 stub）](../../tests/native-selection-smoke.swift)

在具备 Xcode Command Line Tools 的 macOS 上，还可以执行 `bash host/test-ai-core.sh`。它包含使用 stub 的测试，不是完整 App 或真实模型端到端测试；本次 Linux 验证没有运行此命令。

## 常见问题

**这是把所有剪贴板历史自动发给 Agent 吗？**  
不是这个示例的默认流程。用户先选材料再发送；可选 MCP 是额外的历史搜索读取能力，需要单独理解其访问范围。

**能用 CLI preview 证明 Codex 已经连通吗？**  
不能。`preview` 运行组件脚本并检查返回数据；真实问答依赖兼容的原生宿主和 Codex。

**是否可以直接推荐给稳定版用户安装？**  
不能仅凭本仓库和这份教程这样承诺。先确认 App 构建兼容性并完成真实验收。

**能否二次开发？**  
本仓库 SDK、示例和集成快照遵循 [MIT 许可](../../LICENSE)。创建自己的组件时使用独立 ID、真实作者和版本，不冒用官方包身份。


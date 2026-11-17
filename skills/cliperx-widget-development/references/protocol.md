# Widget API 1/2/3/4

组件工程包含 `manifest.json` 和 `widget.js`。`.cliperxwidget` 是 UTF-8 JSON 文件，根字段为 `formatVersion: 1`、`manifest` 和 `script`。打包工具生成该文件，大小上限 256 KB，脚本上限 128 KB。

## 清单

| 字段 | 约定 |
|---|---|
| id | 反向域名，英文小写、数字和短横线，例如 com.author.widget，最多 100 字节 |
| name / author / description | 名称最多 60 字，作者 80 字，描述 300 字 |
| version / apiVersion | x.y.z 版本号，API 版本为 1、2、3 或 4，原生 AI 能力要求至少 2，原生声明和事件订阅要求 3 |
| license / symbol | 许可证标识与 SF Symbol 名称，各最多 80 字 |
| sizes | small、wide 中的一种或两种，第一种为添加时的默认大小 |
| refreshSeconds | 10～86400 秒，App 仅在灵动岛展开且组件启用时定期刷新 |
| settings | 最多 12 个文本配置项，每项 key、title、default。key 为字母开头的英文标识，值最多 500 字 |
| sources | 最多四个命名的 HTTPS GET JSON 数据源，每项包含 url |
| permissions | network 域名数组，以及 openURL、clipboardWrite、systemMetrics 布尔值 |

`sources.repository.url` 可以写成 `https://api.github.com/repos/{{owner}}/{{repository}}`。宿主按配置键替换并进行 URL 编码，最终域名必须出现在 `permissions.network` 中。重定向也需要满足声明的域名。每个响应上限 64 KB，访问失败时填充对应的 `context.errors`。

## 脚本

```javascript
defineWidget({
  render(context) {
    return {
      title: '我的组件',
      value: context.settings.message || 'Hello',
      symbol: 'sparkle',
      actions: [{ id: 'copy', title: '复制' }]
    };
  },
  onAction(action, context) {
    if (action === 'copy') {
      return { effects: [{ type: 'clipboard.write', value: context.settings.message || 'Hello' }] };
    }
    return {};
  }
});
```

此示例需要在清单中声明 `clipboardWrite: true`。两个函数同步返回 JSON 可序列化的数据。TypeScript 应在开发阶段编译打包为单个、调用 `defineWidget` 的 `widget.js`，运行时入口使用普通脚本格式。

## 上下文

- `now` 是 ISO 8601 当前时间，时间计算以它为基准，便于注入测试时间。
- `settings` 是当前实例的配置文本，包含清单默认值。
- `state` 是实例私有的持久化对象，最多 16 KB。操作返回 `{ state: {...} }` 后保存，并用于下一次渲染。
- `data` 保存成功获取的命名 JSON 数据源。
- `errors` 保存对应数据源的错误描述。
- `metrics` 在声明 systemMetrics 后提供 cpuPercent、memoryUsedBytes、memoryTotalBytes、downloadMBps、uploadMBps。

标准 JavaScript 可用，HTTP 请求、系统读数和点击效果由宿主管理。API 1 的配置项面向普通文本和公开 JSON 数据源。账户密钥应通过后续专门的凭据 API 接入。

## 卡片

| 字段 | 约定 |
|---|---|
| title / value | 必填，最多 60 / 120 字 |
| subtitle / symbol | 可选，最多 180 / 80 字 |
| progress | 可选，0～1 的有限数值 |
| series | 可选，最多 60 个有限数值 |
| countdownTo | 可选，ISO 8601 UTC 时间，例如 2026-11-15T03:25:00Z，由宿主原生更新倒计时 |
| details | 可选，最多 20 行 label/value，标签唯一，每行最多 80 / 500 字 |
| primaryAction | 可选，引用 actions 中的 ID，点击卡片直接执行主操作；详情与配置可从右键菜单打开 |
| actions | 可选，最多四个 id/title，ID 唯一，标题最多 40 字 |

没有主操作的卡片点击后展示详情、操作和配置。单格信息卡提供 `subtitle` 时显示标题、主值和副标题；双格可显示副标题、进度或折线。声明原生任务权限的单格卡片使用紧凑任务样式。皮肤和文字颜色由宿主渲染，基础模板见 [基础组件](base-components.md)。

## 操作

`onAction` 收到用户点击的操作 ID 与上下文，可以返回 `state` 和 `effects`。效果上限四个，只在用户点击后执行。

- `{ type: 'openURL', value: 'https://example.com' }` 需要 openURL 权限。
- `{ type: 'clipboard.write', value: '文字' }` 需要 clipboardWrite 权限。

每个效果文本最多 8 KB，结果总大小最多 64 KB。运行器单次执行最多两秒。后台刷新输出用于更新卡片。

## 本地验证

```bash
node /path/to/cliperx-widgets/bin/widget.mjs validate /path/to/widget
node /path/to/cliperx-widgets/bin/widget.mjs preview /path/to/widget
node /path/to/cliperx-widgets/bin/widget.mjs preview /path/to/widget --action copy
node /path/to/cliperx-widgets/bin/widget.mjs preview /path/to/widget --live
node /path/to/cliperx-widgets/bin/widget.mjs pack /path/to/widget --out /path/to/dist
```

`--fixture context.json` 可覆盖 now、settings、state、data、errors 等上下文。点击预览输出的 state 可以保存进下一份 fixture，验证连续操作。普通预览使用开发机 Node VM，App 使用签名的 App Sandbox JavaScriptCore 辅助进程，可用 `--runner` 指定该可执行文件完成宿主验证。

## API 2 原生 AI 能力

原生任务权限默认为 false，须使用 API 2 或更高版本。旧 API 1 组件继续按原协议运行。新组件需安装支持 API 2 的灵剪开发构建，当前宿主集成源码见 `host/integration/`。

| 权限 | 脚本上下文 | 点击效果 |
|---|---|---|
| contextPreparation | contextPack.count、estimatedTokens、shortened、unavailable | `{ type: 'context.prepare', value: '' }` |
| textProcessing | textProcessing.appleAvailable、actionTitle、busy | `{ type: 'text.process', value: '' }` |
| aiUsage | aiUsage.status、provider、updatedAt、windows、error | `{ type: 'aiUsage.refresh', value: '' }` |
| collectionBasket | collectionBasket.count、autoCollect、isOpen、isPasting | `{ type: 'basket.open', value: '' }` |

原生效果的 value 固定为空字符串。后台刷新仅可更新卡片。三个官方组件位于 `examples/context-preparation`、`examples/text-processing`、`examples/ai-usage`，可参照其权限声明、离线状态和点击入口。

收集篮模板用 `create --template task-basket` 生成。它读取全局收集状态，点击打开剪贴板下方的原生任务区。自动收集、手动选卡、预览、移除、排序、依次粘贴和合并文字都由宿主执行；脚本不接收剪贴正文，也不能发起粘贴。关闭自动收集或任务区不会清空队列。包含图片或文件时只能依次粘贴。

上下文准备在灵动岛内选择文字和图片。用户可新建 Codex 对话，或搜索和续接真实的历史对话，问题、回答和连续追问都在岛内完成。最多选择 20 条材料，文字按预算整理并保留来源，图片作为真实图片附件提供给 Codex。手动选择的附件随本次问题发送，输入栏可继续准备下一轮材料。

灵剪 MCP 开关控制本次问答是否提供灵剪只读历史检索能力。开启时允许 `search`、`read_item`、`list_pinboards`，凭据在本次调用结束后撤销。运行配置通过 App Server 请求传入。宿主按当前服务名检查初始化状态与工具可用性。

`contextPack` 保留 count、estimatedTokens、shortened、unavailable，并增加 imageCount、hasConversation。Token 估算与裁剪计数针对文字。图片处理与对话内容由原生宿主管理，脚本仅读取标准化状态。

原生快捷交互包含 Command 点选卡片、空格预览、Command Return 提问和 Esc 返回。Esc 先关闭原生弹层，返回时保留草稿。

文本处理默认翻译，点击组件后点选一张文字卡片即开始执行。当前卡片高亮，下方以 Markdown 显示结果，可切换原文、复制和重试。语言、来源与默认动作在原生结果区设置，切换卡片或设置时取消旧请求。最近 20 个成功结果按内容和配置缓存，复用前重新检查原文与隐私状态。翻译支持中英互译和固定目标语言，另保留改写、总结、自定义处理和本机文字工具。

来源支持灵剪后端、本机 Codex、OpenAI 兼容接口，以及可用的 Apple Intelligence。灵剪复用带设备鉴权的 `/api/ai/chat`，Codex 使用临时 App Server 会话，模型结果流式回传。密钥按接口地址存储在 macOS Keychain，HTTP 仅允许本机回环地址，其余地址要求 HTTPS，拒绝重定向。Ollama 可使用 `http://localhost:11434/v1/chat/completions`。脚本只接收标准化状态，正文、模型配置和凭据由原生宿主管理。

AI 用量卡使用剩余额度和相对重置时间文字。存在多个窗口时显示剩余最紧张的窗口，点击可查看完整数据与准确时间。AI 用量依赖用户本机安装并已登录的 [CodexBar](https://github.com/steipete/CodexBar)。配置项 provider 支持 codex、claude。宿主调用固定的 CLI 参数，读取标准化的额度窗口，自动请求至少间隔 60 秒，手动刷新最短 10 秒。windows 包含 label、usedPercent、resetsAt、windowMinutes。status 为 ready、stale、unavailable，读取失败时可保留带时间标记的旧数据。脚本只接收窗口数值、状态、错误和更新时间。

开发预览可通过 `--fixture` 注入这些字段。预览命令展示能力请求，原生交互和本机 CLI 接入在 App 中验收。当前公共宿主协议、核心逻辑及原生集成代码均随仓库开源。


## API 3 注册与能力订阅

`apiVersion` 支持 1、2、3。API 1/2 包可沿用原格式。API 3 的原生声明包示例见基础组件文档，其包结构仍为 `formatVersion: 1`。

脚本组件可将 `presentation.card` 设为 `standard`，声明 `workspace`，并使用 `subscriptions` 接收宿主状态变化。支持的事件与权限对应为 `metrics` → `systemMetrics`、`music` → `musicControl`、`agent` → `agentConversations`、`context` → `contextPreparation`、`text` → `textProcessing`、`basket` → `collectionBasket`。宿主在状态变化时重新提供快照并执行 `render`，事件刷新有节流，`refreshSeconds` 作为定时补充。

音乐能力在 `context.music` 提供 title、artist 和 isPlaying。用户操作可返回空 value 的 `music.playPause`、`music.previous` 或 `music.next` 效果。Agent 能力在 `context.agent` 提供 count、running 和 unread，`agent.open` 打开原生工作区。效果需要用户操作和对应权限，后台刷新只更新卡片。

原生声明包采用宿主已有布局和能力，`script` 为空。标准卡片的 `script` 必须提供同步 render。新能力、渲染器与工作区类型通过宿主 API 版本扩展。

## 工坊目录与兼容声明

目录版本仍为 schemaVersion 1，条目保留 manifest、packageURL、sha256 和 sourceURL，并可提供 metadata 与 publishedAt。包来源支持 GitHub 和官方 api.cliperx.com HTTPS。开发时仅可显式指定本机回环服务作为附加来源。

metadata 的 category、tags、screenshots、readme、changelog、minAppVersion、feedbackURL 用于工坊展示与兼容提示，缺少时使用空值。截图与反馈地址使用 HTTPS，最低 App 版本采用 x.y.z。Widget API 版本由 manifest.apiVersion 声明，目录版本独立演进。

API 3 的 `presentation.card: 'ccswitch'` 要求 `providerConfiguration: true` 并省略 workspace。此声明调用宿主已有服务商配置界面。新建工程可以使用 `--template native-ccswitch`。

## API 4 自定义 AI 任务

API 4 在 `presentation.card: "standard"`、`presentation.workspace: "context"` 的脚本组件中增加 task，权限需要 contextPreparation。API 1/2/3 组件沿用既有声明。

```json
{
  "input": { "types": ["text", "image"], "minItems": 1, "maxItems": 12 },
  "parameters": [
    { "key": "product", "title": "产品名称", "default": "", "required": true }
  ],
  "prompt": "为 {{parameters.product}} 整理带证据来源的 Bug 单。补充要求 {{question}}",
  "output": { "format": "markdown" }
}
```

input.types 必须非空、去重，只接受 text、image。条数满足 0 ≤ minItems ≤ maxItems ≤ 20。参数至多八个，key 唯一且沿用 settings 的标识规则，title 为 1 至 60 字，default 最多 500 字，required 可选。

prompt 为 1 至 12000 字，只接受 question 与已声明 parameters.KEY 变量。替换时参数和用户问题按原文插入，原文中的变量样式保持原样。未引用 question 时，非空补充要求追加在指令末尾。必填参数为空时阻止执行，输入材料的类型与条数由宿主检查。第一版输出格式为 Markdown。

```bash
node bin/widget.mjs preview examples/bug-report --fixture examples/bug-report/preview.json
```

预览展示最终指令、输入要求和参数定义。真实材料、图片、引用、流式状态和重试在 App 中处理，组件脚本仍返回 context.prepare 效果。作者应在工坊详情写明支持的宿主 API 和本地 Codex 条件。

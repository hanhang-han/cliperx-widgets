# 灵剪基础组件

灵动岛顶部是一排小卡片。组件分为两类：信息组件只在顶部展示状态，点击后打开详情；任务组件点击后在剪贴板下方打开共用的原生任务区。卡片和任务区由宿主按点阵科技或卡证拟物皮肤渲染，`widget.js` 只返回数据和操作，不能注入 SwiftUI、HTML 或自定义任务区。

## 选择模板

| 模板 | 创建命令中的参数 | 主操作 | 适用情况 |
|---|---|---|---|
| 信息卡 | `--template info` | 点击查看详情 | 计数、状态、倒计时、用量等；单格显示标题、主值和副标题 |
| 上下文任务卡 | `--template task-context` | `prepare` | 选择文字或图片，向 Codex 新建或历史对话提问，可选灵剪 MCP |
| 自定义 AI 任务卡 | `--template task-ai` | `prepare` | 作者定义输入、表单参数及指令，宿主使用本地 Codex 执行并展示 Markdown |
| 文本任务卡 | `--template task-text` | `process` | 选择一张文字卡片，立即翻译或执行宿主提供的文本处理 |
| 收集篮任务卡 | `--template task-basket` | `open` | 自动或手动收集剪贴卡，预览、排序、依次粘贴或合并文字 |

例如：

```bash
node bin/widget.mjs create ../my-context --id com.yourname.my-context --name 我的上下文 --author yourname --template task-context
node bin/widget.mjs validate ../my-context
node bin/widget.mjs preview ../my-context --action prepare
```

收集篮基础组件可直接创建：

```bash
node bin/widget.mjs create ../my-basket --id com.yourname.my-basket --name 我的收集篮 --author yourname --template task-basket
node bin/widget.mjs validate ../my-basket
node bin/widget.mjs preview ../my-basket --action open
```

`info` 是 API 1。单格时返回 `subtitle` 会采用三行紧凑信息卡，双格可使用进度、折线等字段。数据来自清单声明的 HTTPS GET 源、系统指标或配置；点击详情无需编写动作。AI 用量使用 API 2 的 `aiUsage` 权限，可参考仓库中的 `examples/ai-usage`；额度只来自宿主提供的标准化窗口。

`task-context`、`task-text` 和 `task-basket` 是 API 2，默认单格。点击卡片在剪贴板下方打开对应的原生任务区；切换上下文和文本任务卡时，宿主按组件实例保留选材、草稿和结果。收集篮是全局共享的本地队列，不按组件实例复制内容。不要在脚本状态中保存选中的原文、图片、模型密钥、回答或队列条目；这些只由原生宿主管理。脚本的 `onAction` 分别返回 `context.prepare`、`text.process` 或 `basket.open` 效果，便于详情操作和本地预览。卡片主操作由支持此布局的宿主直接打开任务区。

`task-basket` 的 `context.collectionBasket` 只暴露数量、自动收集开关状态、是否展开和是否粘贴中。脚本不能读取篮中正文或代替用户触发粘贴；排序、合并和粘贴由原生界面完成。手动加入剪贴卡也是宿主交互。这个模板是可运行的基础卡片，开发者可改标题、图标和状态文字，再用自己的组件 ID 打包安装。

原生任务区由注册中心提供上下文、文本处理、收集篮和 Agent。API 3 开放音乐控制和 Agent 能力，并支持声明式原生卡片。新的原生控件或专属工作区布局需要扩展宿主渲染器。使用旧版宿主时，应先确认对应的 API 版本。


## API 3 原生声明包

音乐、六类系统指标、收集篮和 Agent 使用独立 `.cliperxwidget` 包声明，和脚本组件共用安装、更新、启停、卸载与实例管理。安装包选择宿主已注册的渲染器。原生声明包只提供 `manifest.json`，打包工具生成空 `script`；`standard` 卡片继续提供 `widget.js`。

| 模板 | 渲染器 | 宿主能力 |
|---|---|---|
| `native-music` | `music` | `musicControl`，Apple Music 状态与播放控制 |
| `native-metric` | `metric` | `systemMetrics`，可选 CPU、内存、网速、电量、磁盘；时钟独立计时 |
| `native-agent` | `agent` | `agentConversations`，共享 Agent 工作区 |
| `native-basket` | `basket` | `collectionBasket`，共享收集篮 |

```bash
node bin/widget.mjs create ../my-music --id com.yourname.music --name 我的音乐 --author yourname --template native-music
node bin/widget.mjs validate ../my-music
node bin/widget.mjs pack ../my-music --out ../dist
```

`presentation.card` 选择 `standard`、`metric`、`music`、`basket` 或 `agent`。`presentation.workspace` 可声明 `context`、`text`、`basket` 或 `agent`，并申请对应权限。指标卡用 `presentation.metric` 指定 `cpu`、`memory`、`network`、`battery`、`disk` 或 `clock`。`presentation.multipleInstances` 控制添加入口是否允许重复实例，原生模板默认为 false。

声明包的 CLI `preview` 返回 `previewKind: declaration` 和渲染器声明，实际外观及操作通过 App 查看。脚本组件继续使用沙箱运行器预览。官方原生声明示例在 `examples/native-*`，主 App 的兼容布局 ID 会映射到相应包 ID。

停用或卸载会撤销实例运行任务及对应订阅。安装状态、布局位置和用户数据分别保存，恢复安装后可以继续使用原有实例。多个组件共同使用音乐、指标、收集篮或 Agent 时，宿主在最后一个使用者卸载后释放对应服务。Agent 在已加载期间继续后台同步，顶部组件隐藏时展示型脚本暂停刷新。

## 服务商切换卡

`create --template native-ccswitch` 生成 API 3 的 CC Switch 原生声明，申请 `providerConfiguration` 权限。卡片使用宿主已提供的配置界面，服务商凭据保存在原生凭据存储，切换前保留本机工具配置备份。该能力需要支持 `ccswitch` 渲染器的灵剪版本，作者应在工坊元数据声明最低客户端版本。

## 自定义 AI 任务卡

`task-ai` 生成 API 4 的标准脚本卡片，声明 context 工作区和 contextPreparation 权限。点击卡片后选取文字或图片，填写作者定义的参数，检查任务指令后运行。宿主保存每个组件实例的草稿、任务与回答，继续提供取消、重试、来源预览和复制。

示例工程位于 `examples/bug-report`。修改 manifest.task 即可定义另一种任务，保留当前宿主支持的输入与输出约定。参数为纯文本，模型账号和凭据由宿主管理。原生实现使用用户本机已登录的 Codex。

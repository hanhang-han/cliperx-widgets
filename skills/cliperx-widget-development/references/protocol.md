# Widget API 1

组件工程包含 `manifest.json` 和 `widget.js`。`.cliperxwidget` 是 UTF-8 JSON 文件，根字段为 `formatVersion: 1`、`manifest` 和 `script`。打包工具生成该文件，大小上限 256 KB，脚本上限 128 KB。

## 清单

| 字段 | 约定 |
|---|---|
| id | 反向域名，英文小写、数字和短横线，例如 com.author.widget，最多 100 字节 |
| name / author / description | 名称最多 60 字，作者 80 字，描述 300 字 |
| version / apiVersion | x.y.z 版本号，API 版本为 1 |
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
| actions | 可选，最多四个 id/title，ID 唯一，标题最多 40 字 |

卡片点击后展示详情、操作和配置。小尺寸显示标题、读数和图标，宽尺寸可显示副标题、进度或折线。皮肤和文字颜色由宿主渲染。

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

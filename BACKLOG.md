# 官方 AI 组件候选

首批开发上下文准备、文本处理、AI 用量。以下功能保留到后续版本，状态均为待开发。

| 方向 | 用户操作和卡片内容 | 接入思路 | 研究来源 |
|---|---|---|---|
| Agent 任务 | 查看运行、等待输入、完成状态，点击回到会话 | Claude hooks、Codex 事件适配，按任务聚合并允许关闭通知 | [Agent-Notch](https://github.com/Forichok/Agent-Notch)、[Claude hooks](https://code.claude.com/docs/en/hooks) |
| Skill 快捷入口 | 固定常用 Skill，结合所选素材发起任务 | 声明输入、参数和执行结果，通过宿主统一执行 | 当前组件 Skill 与安装目录 |
| 记忆检索 | 以一句话查找过去复制的内容，显示来源 | 复用灵剪索引，提供显式查询和结果选择 | [qmd](https://github.com/tobi/qmd) |
| 本地模型 | 查看已加载模型、内存与运行状态，切换模型 | Ollama `/api/ps`，模型控制单独授权 | [Ollama](https://github.com/ollama/ollama) |
| 语音输入 | 按下录音，转文字后复制或加入上下文 | 先完成短语音，再考虑会议记录与流式转写 | [Argmax OSS / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)、[whisper.cpp](https://github.com/ggml-org/whisper.cpp) |
| MCP 活动 | 查看最近工具调用、结果与连接状态 | 接入灵剪 MCP 的真实请求事件，支持查看权限与撤销 | 灵剪 ClipboardMCPServer |

## 首批后续增强

- 上下文准备支持收藏夹、文件提取和语义候选推荐。
- 文本处理支持流式返回和保存常用指令。
- AI 用量扩展更多服务与多账户，研究 [CodexBar](https://github.com/steipete/CodexBar) 和 [OpenUsage](https://github.com/robinebers/openusage)。当前通过本机 CodexBar CLI 读取 codex / claude。

外部仓库作为实现参考。引入其代码时应核对当时的许可证并保留版权声明。

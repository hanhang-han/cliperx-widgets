defineWidget({
  render(context) {
    const local = context.textProcessing?.appleAvailable;
    return {
      title: '文本处理',
      value: '改写 · 总结 · 翻译',
      subtitle: local ? 'Apple Intelligence 已就绪' : '自选模型 · 支持本机清理',
      symbol: 'text.cursor',
      details: [
        { label: 'AI 处理', value: 'Apple Intelligence 或 OpenAI 兼容接口、Ollama' },
        { label: '本机工具', value: '清理空白、逐行去重、格式化 JSON' },
        { label: '输入', value: '在原生工作台粘贴并预览' }
      ],
      actions: [{ id: 'process', title: '打开文本处理' }]
    };
  },
  onAction(action) {
    return action === 'process' ? { effects: [{ type: 'text.process', value: '' }] } : {};
  }
});

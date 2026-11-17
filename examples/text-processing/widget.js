defineWidget({
  render(context) {
    const text = context.textProcessing || {};
    return {
      title: '文本处理',
      value: text.busy ? '处理中' : (text.actionTitle || '翻译'),
      symbol: 'character.bubble',
      details: [
        { label: '操作', value: '点选一张文字卡片立即处理' },
        { label: '来源', value: '灵剪、Codex、自定义模型' },
        { label: '设置', value: '岛内结果区可切换语言、来源和默认动作' }
      ],
      primaryAction: 'process',
      actions: [{ id: 'process', title: '翻译文字' }]
    };
  },
  onAction(action) {
    return action === 'process' ? { effects: [{ type: 'text.process', value: '' }] } : {};
  }
});

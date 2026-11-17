defineWidget({
  render(context) {
    const pack = context.contextPack;
    return {
      title: '上下文',
      value: pack && pack.count ? `已选 ${pack.count} 项` : pack && pack.hasConversation ? '继续提问' : '问 Codex',
      symbol: 'doc.on.doc',
      details: [
        { label: 'Token 估算', value: pack ? String(pack.estimatedTokens) : '等待宿主 API 2' },
        { label: '预算裁剪', value: pack ? `${pack.shortened} 条` : '—' },
        { label: '不可用素材', value: pack ? `${pack.unavailable} 条` : '—' }
      ],
      primaryAction: 'prepare',
      actions: [{ id: 'prepare', title: '选择材料' }]
    };
  },
  onAction(action) {
    return action === 'prepare' ? { effects: [{ type: 'context.prepare', value: '' }] } : {};
  }
});

defineWidget({
  render(context) {
    const pack = context.contextPack;
    return {
      title: '上下文准备',
      value: pack && pack.count ? `${pack.count} 条素材` : '选择素材',
      subtitle: pack && pack.count ? `约 ${pack.estimatedTokens} tokens · 保留来源` : '选材、去重与预算',
      symbol: 'doc.on.doc',
      details: [
        { label: 'Token 估算', value: pack ? String(pack.estimatedTokens) : '等待宿主 API 2' },
        { label: '预算裁剪', value: pack ? `${pack.shortened} 条` : '—' },
        { label: '不可用素材', value: pack ? `${pack.unavailable} 条` : '—' }
      ],
      actions: [{ id: 'prepare', title: '准备上下文' }]
    };
  },
  onAction(action) {
    return action === 'prepare' ? { effects: [{ type: 'context.prepare', value: '' }] } : {};
  }
});

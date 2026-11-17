defineWidget({
  render(context) {
    const pack = context.contextPack || {};
    return {
      title: 'Bug 单整理',
      value: pack.count ? '已选 ' + pack.count + ' 项' : '选择错误材料',
      subtitle: '报错、日志与截图',
      symbol: 'ladybug',
      primaryAction: 'prepare',
      actions: [{ id: 'prepare', title: '整理 Bug 单' }]
    };
  },
  onAction(action) {
    return action === 'prepare' ? { effects: [{ type: 'context.prepare', value: '' }] } : {};
  }
});

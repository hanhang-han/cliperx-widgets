defineWidget({
  render(context) {
    const minutes = Math.min(180, Math.max(1, Number(context.settings.minutes) || 25));
    const now = Date.parse(context.now);
    const end = Number(context.state.end) || 0;
    const running = end > now;
    const remaining = running ? end - now : (end ? 0 : (Number(context.state.remaining) || minutes * 60000));
    const seconds = Math.max(0, Math.ceil(remaining / 1000));
    return {
      title: '专注计时',
      value: `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`,
      subtitle: running ? '正在专注' : (end ? '本轮已完成' : '点击开始专注'),
      symbol: 'timer',
      countdownTo: running ? new Date(end).toISOString() : undefined,
      progress: running ? Math.min(1, Math.max(0, 1 - remaining / (minutes * 60000))) : (end ? 1 : 0),
      actions: [{ id: 'toggle', title: running ? '暂停' : '开始' }, { id: 'reset', title: '重置' }]
    };
  },
  onAction(action, context) {
    const now = Date.parse(context.now);
    const duration = Math.min(180, Math.max(1, Number(context.settings.minutes) || 25)) * 60000;
    if (action === 'reset') return { state: {} };
    const end = Number(context.state.end) || 0;
    if (end > now) return { state: { remaining: end - now } };
    return { state: { end: now + (Number(context.state.remaining) || duration) } };
  }
});

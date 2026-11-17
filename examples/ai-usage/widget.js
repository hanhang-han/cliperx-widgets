function resetLabel(now, target) {
  const milliseconds = Date.parse(target) - Date.parse(now);
  if (!Number.isFinite(milliseconds)) return '重置时间暂未提供';
  if (milliseconds <= 0) return '等待额度更新';
  const days = Math.floor(milliseconds / 86400000);
  if (days > 0) return `${days} 天后重置`;
  const hours = Math.floor(milliseconds / 3600000);
  if (hours > 0) return `${hours} 小时后重置`;
  return `${Math.max(1, Math.ceil(milliseconds / 60000))} 分钟后重置`;
}
function windowLabel(window) {
  if (window.windowMinutes === 10080 || window.label === 'Weekly') return '周额度';
  if (window.windowMinutes === 300) return '5 小时额度';
  return window.label;
}
defineWidget({
  render(context) {
    const usage = context.aiUsage;
    const provider = (context.settings.provider || 'codex').trim().toLowerCase();
    const name = provider === 'codex' ? 'Codex' : provider === 'claude' ? 'Claude' : provider.slice(0, 30);
    const windows = usage?.windows || [];
    const main = [...windows].sort((first, second) => second.usedPercent - first.usedPercent)[0];
    const details = windows.flatMap((window, index) => [
      { label: `${index + 1} · ${windowLabel(window)}`, value: `剩余 ${Math.round(100 - window.usedPercent)}%` },
      { label: `${index + 1} · 重置`, value: window.resetsAt || '暂未提供' }
    ]);
    if (usage?.updatedAt) details.push({ label: '数据更新', value: usage.updatedAt });
    if (usage?.error) details.push({ label: '读取状态', value: String(usage.error).slice(0, 500) });
    return {
      title: main ? `${name} · ${windowLabel(main)}` : `${name} 用量`,
      value: main ? `剩余 ${Math.round(100 - main.usedPercent)}%` : '暂不可用',
      subtitle: main ? `${resetLabel(context.now, main.resetsAt)}${usage.status === 'stale' ? ' · 缓存' : ''}` : '检查 CodexBar 账户连接',
      symbol: 'chart.bar',
      details,
      actions: [{ id: 'refresh', title: '刷新用量' }]
    };
  },
  onAction(action) {
    return action === 'refresh' ? { effects: [{ type: 'aiUsage.refresh', value: '' }] } : {};
  }
});

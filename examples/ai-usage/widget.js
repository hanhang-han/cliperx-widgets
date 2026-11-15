defineWidget({
  render(context) {
    const usage = context.aiUsage;
    const provider = (context.settings.provider || 'codex').trim().toLowerCase();
    const name = provider === 'codex' ? 'Codex' : provider === 'claude' ? 'Claude' : provider.slice(0, 30);
    const windows = usage?.windows || [];
    const main = windows[0];
    const details = windows.flatMap((window, index) => [
      { label: `${index + 1} · ${window.label}`, value: `已用 ${Math.round(window.usedPercent)}% · 剩余 ${Math.round(100 - window.usedPercent)}%` },
      { label: `${index + 1} · 重置`, value: window.resetsAt || '暂未提供' }
    ]);
    if (usage?.updatedAt) details.push({ label: '数据更新', value: usage.updatedAt });
    if (usage?.error) details.push({ label: '读取状态', value: String(usage.error).slice(0, 500) });
    return {
      title: `${name} 用量`,
      value: main ? `${Math.round(100 - main.usedPercent)}% 剩余` : '待连接',
      subtitle: main ? `${main.label}${usage.status === 'stale' ? ' · 缓存数据' : ''}` : '安装 CodexBar 并登录账户',
      symbol: 'chart.bar',
      ...(main ? { progress: main.usedPercent / 100 } : {}),
      details,
      actions: [{ id: 'refresh', title: '刷新用量' }]
    };
  },
  onAction(action) {
    return action === 'refresh' ? { effects: [{ type: 'aiUsage.refresh', value: '' }] } : {};
  }
});

defineWidget({
  render(context) {
    const repository = context.data.repository;
    const available = repository && typeof repository.stargazers_count === 'number';
    return {
      title: 'GitHub Stars',
      value: available ? String(repository.stargazers_count) : '—',
      subtitle: available ? context.settings.repository : '数据暂不可用',
      symbol: 'star',
      details: available ? [
        { label: '仓库', value: repository.full_name },
        { label: 'Fork', value: String(repository.forks_count) },
        { label: 'Issue', value: String(repository.open_issues_count) }
      ] : [{ label: '状态', value: context.errors.repository || '等待数据' }],
      actions: [{ id: 'open', title: '打开仓库' }]
    };
  },
  onAction(action, context) {
    if (action !== 'open') return {};
    const owner = encodeURIComponent(context.settings.owner);
    const repository = encodeURIComponent(context.settings.repository);
    return { effects: [{ type: 'openURL', value: `https://github.com/${owner}/${repository}` }] };
  }
});

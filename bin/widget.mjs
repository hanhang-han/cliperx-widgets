#!/usr/bin/env node
import { readFile, writeFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { parseArgs } from 'node:util';
import os from 'node:os';
import path from 'node:path';
import { runWorkshopCommand } from '../lib/workshop-client.mjs';
import { assert, digest, loadProject, pack, preview, sourceURL, validateEntry, validateManifest, validateResult, renderTask } from '../lib/protocol.mjs';

const command = process.argv[2] ?? 'help';
const { values: flags, positionals } = parseArgs({ args: process.argv.slice(3), allowPositionals: true, options: {
  id: { type: 'string' }, name: { type: 'string' }, author: { type: 'string' }, out: { type: 'string' },
  repo: { type: 'string' }, tag: { type: 'string' }, entry: { type: 'string' }, catalog: { type: 'string' },
  fixture: { type: 'string' }, action: { type: 'string' }, runner: { type: 'string' }, template: { type: 'string' },
  live: { type: 'boolean', default: false },
  api: { type: 'string' }, metadata: { type: 'string' }, source: { type: 'string' }, submission: { type: 'string' },
  draft: { type: 'boolean', default: false }, 'no-open': { type: 'boolean', default: false },
} });
const directory = path.resolve(positionals[0] ?? '.');
const print = value => process.stdout.write(`${typeof value === 'string' ? value : JSON.stringify(value, null, 2)}\n`);

function run(program, args, options = {}) {
  return execFileSync(program, args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], ...options }).trim();
}
function github(endpoint, body, method = body ? 'POST' : 'GET') {
  const args = ['api', endpoint, '--method', method];
  if (body) args.push('--input', '-');
  const result = run('gh', args, body ? { input: JSON.stringify(body) } : {});
  return result ? JSON.parse(result) : null;
}
async function liveSources(pkg, context) {
  for (const [key, source] of Object.entries(pkg.manifest.sources ?? {})) {
    try {
      let url = sourceURL(pkg.manifest, source, context.settings);
      let response;
      for (let redirect = 0; redirect <= 4; redirect++) {
        response = await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(15000), headers: { 'User-Agent': 'CliperX-Widgets-Developer/0.1' } });
        if (response.status < 300 || response.status >= 400) break;
        await response.body?.cancel();
        const next = new URL(response.headers.get('location'), url);
        assert(next.protocol === 'https:' && pkg.manifest.permissions.network.includes(next.hostname), 'Redirect exceeds network permissions');
        url = next;
      }
      assert(response.ok, `HTTP ${response.status}`);
      const chunks = [];
      let length = 0;
      for await (const chunk of response.body) {
        length += chunk.length;
        assert(length <= 65536, 'Source exceeds 64 KB');
        chunks.push(chunk);
      }
      context.data[key] = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch (error) { context.errors[key] = error.message.slice(0, 200); }
  }
}

async function create() {
  const slug = path.basename(directory).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const template = flags.template ?? 'basic';
  assert(['basic', 'info', 'task-context', 'task-ai', 'task-text', 'task-basket', 'native-music', 'native-agent', 'native-metric', 'native-basket', 'native-ccswitch'].includes(template), 'Unknown widget template');
  const manifest = { id: flags.id ?? `com.example.${slug}`, name: flags.name ?? slug, version: '0.1.0', apiVersion: 1,
    author: flags.author ?? 'Your Name', description: '显示一条可配置的文字', license: 'MIT', symbol: 'sparkle',
    sizes: ['small', 'wide'], refreshSeconds: 60, permissions: { network: [], openURL: false, clipboardWrite: false, systemMetrics: false },
    settings: [{ key: 'message', title: '显示文字', default: 'Hello, 灵剪' }] };
  let script = `defineWidget({\n  render(context) {\n    return { title: ${JSON.stringify(manifest.name)}, value: context.settings.message, symbol: 'sparkle' };\n  }\n});\n`;
  if (template === 'info') {
    manifest.description = '在灵动岛显示主值和补充信息，点击查看详情。';
    manifest.symbol = 'text.alignleft';
    manifest.settings = [
      { key: 'value', title: '主值', default: '今天已整理 12 条' },
      { key: 'subtitle', title: '补充信息', default: '点击查看详情' }
    ];
    script = `defineWidget({\n  render(context) {\n    return {\n      title: ${JSON.stringify(manifest.name)},\n      value: context.settings.value || '—',\n      subtitle: context.settings.subtitle || '',\n      symbol: 'text.alignleft',\n      details: [{ label: '当前信息', value: context.settings.value || '暂无数据' }]\n    };\n  }\n});\n`;
  } else if (template === 'task-context' || template === 'task-ai') {
    manifest.apiVersion = 2;
    manifest.description = '点选剪贴板中的文字和图片，在原生任务区使用 Codex 问答。';
    manifest.symbol = 'doc.on.doc';
    manifest.sizes = ['small'];
    manifest.refreshSeconds = 30;
    manifest.permissions.contextPreparation = true;
    manifest.settings = [];
    script = `defineWidget({\n  render(context) {\n    const pack = context.contextPack;\n    return {\n      title: ${JSON.stringify(manifest.name)},\n      value: pack && pack.count ? '已选 ' + pack.count + ' 项' : pack && pack.hasConversation ? '继续提问' : '问 Codex',\n      symbol: 'doc.on.doc',\n      primaryAction: 'prepare',\n      actions: [{ id: 'prepare', title: '选择材料' }]\n    };\n  },\n  onAction(action) {\n    return action === 'prepare' ? { effects: [{ type: 'context.prepare', value: '' }] } : {};\n  }\n});\n`;
  } else if (template === 'task-text') {
    manifest.apiVersion = 2;
    manifest.description = '点选文字卡片，在原生任务区翻译或处理文本。';
    manifest.symbol = 'character.bubble';
    manifest.sizes = ['small'];
    manifest.refreshSeconds = 30;
    manifest.permissions.textProcessing = true;
    manifest.settings = [];
    script = `defineWidget({\n  render(context) {\n    const task = context.textProcessing || {};\n    return {\n      title: ${JSON.stringify(manifest.name)},\n      value: task.busy ? '处理中' : task.actionTitle || '翻译',\n      symbol: 'character.bubble',\n      primaryAction: 'process',\n      actions: [{ id: 'process', title: '选择文字' }]\n    };\n  },\n  onAction(action) {\n    return action === 'process' ? { effects: [{ type: 'text.process', value: '' }] } : {};\n  }\n});\n`;
  } else if (template === 'task-basket') {
    manifest.apiVersion = 2;
    manifest.description = '按复制顺序收集内容，在原生任务区整理并粘贴。';
    manifest.symbol = 'tray.full';
    manifest.sizes = ['small'];
    manifest.refreshSeconds = 30;
    manifest.permissions.collectionBasket = true;
    manifest.settings = [];
    script = `defineWidget({\n  render(context) {\n    const basket = context.collectionBasket || {};\n    return {\n      title: ${JSON.stringify(manifest.name)},\n      value: (basket.count || 0) + ' 条 · ' + (basket.autoCollect ? '收集中' : '已暂停'),\n      symbol: 'tray.full',\n      primaryAction: 'open',\n      actions: [{ id: 'open', title: '打开收集篮' }]\n    };\n  },\n  onAction(action) {\n    return action === 'open' ? { effects: [{ type: 'basket.open', value: '' }] } : {};\n  }\n});\n`;
  }
  if (template === 'task-ai') {
    manifest.apiVersion = 4;
    manifest.description = '根据选中的报错、日志和截图，使用自己的 Codex 生成 Bug 单。';
    manifest.presentation = { card: 'standard', workspace: 'context' };
    manifest.task = {
      input: { types: ['text', 'image'], minItems: 1, maxItems: 12 },
      parameters: [{ key: 'product', title: '产品名称', default: '', required: true }],
      prompt: '根据选中的材料，为 {{parameters.product}} 生成 Bug 单。使用 Markdown，包含标题、现象、复现步骤、预期结果、实际结果、已有证据和待确认信息。引用材料时保留来源编号，区分事实与推断。用户补充要求 {{question}}',
      output: { format: 'markdown' },
    };
  }
  if (template.startsWith('native-')) {
    const card = template.slice(7);
    manifest.apiVersion = 3;
    manifest.presentation = { card, multipleInstances: false };
    manifest.settings = [];
    manifest.refreshSeconds = 30;
    script = '';
    if (card === 'music') {
      manifest.permissions.musicControl = true;
      manifest.symbol = 'music.note';
      manifest.sizes = ['wide'];
      manifest.description = '使用宿主的 Apple Music 状态和原生播放控制。';
    } else if (card === 'agent') {
      manifest.permissions.agentConversations = true;
      manifest.presentation.workspace = 'agent';
      manifest.symbol = 'terminal';
      manifest.sizes = ['small'];
      manifest.description = '在宿主 Agent 工作区关注和继续 Codex 对话。';
    } else if (card === 'basket') {
      manifest.permissions.collectionBasket = true;
      manifest.presentation.workspace = 'basket';
      manifest.symbol = 'tray.full';
      manifest.sizes = ['small'];
      manifest.description = '打开宿主的共享收集篮。';
    } else if (card === 'ccswitch') {
      manifest.permissions.providerConfiguration = true;
      manifest.symbol = 'arrow.triangle.swap';
      manifest.sizes = ['small'];
      manifest.description = '通过原生界面管理并切换编程工具的服务商配置。';
    } else if (card === 'metric') {
      manifest.permissions.systemMetrics = true;
      manifest.presentation.metric = 'cpu';
      manifest.symbol = 'cpu';
      manifest.description = '使用宿主的实时 CPU 指标与趋势图。';
    }
  }
  validateManifest(manifest);
  await mkdir(directory);
  await writeFile(path.join(directory, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  if (script) await writeFile(path.join(directory, 'widget.js'), script);
  print(`Created ${directory}`);
}

async function publish() {
  assert(flags.repo && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(flags.repo), 'Pass --repo owner/public-repository');
  const root = run('git', ['rev-parse', '--show-toplevel'], { cwd: directory });
  const sha = run('git', ['rev-parse', 'HEAD'], { cwd: directory });
  const remote = run('git', ['remote', 'get-url', 'origin'], { cwd: directory });
  assert(remote.replace(/\.git$/, '').endsWith(`github.com/${flags.repo}`) || remote.replace(/\.git$/, '').endsWith(`github.com:${flags.repo}`), '--repo must match this project origin');
  assert(!github(`repos/${flags.repo}`).private, 'Workshop releases need a public repository');
  github(`repos/${flags.repo}/commits/${sha}`);
  const relative = path.relative(root, directory).split(path.sep).join('/');
  const changes = run('git', ['status', '--porcelain', '--', path.join(directory, 'manifest.json'), path.join(directory, 'widget.js')], { cwd: directory });
  assert(!changes, 'Commit and push manifest.json and widget.js before publishing');
  const built = await pack(directory, path.resolve(flags.out ?? path.join(root, 'dist')));
  const tag = flags.tag ?? `${built.pkg.manifest.id}-v${built.pkg.manifest.version}`;
  assert(/^[A-Za-z0-9][A-Za-z0-9._-]{0,150}$/.test(tag), 'Invalid release tag');
  let existing;
  try { existing = github(`repos/${flags.repo}/releases/tags/${tag}`); }
  catch (error) { if (!String(error.stderr ?? error.message).includes('404')) throw error; }
  if (!existing) {
    const temp = await mkdtemp(path.join(os.tmpdir(), 'cliperx-widget-release-'));
    try {
      const notes = path.join(temp, 'notes.md');
      await writeFile(notes, `${built.pkg.manifest.name} ${built.pkg.manifest.version}\n\nWidget API ${built.pkg.manifest.apiVersion}. Source commit ${sha}.\nSHA256 ${built.sha256}\n`);
      run('gh', ['release', 'create', tag, built.file, '--repo', flags.repo, '--target', sha, '--title', `${built.pkg.manifest.name} v${built.pkg.manifest.version}`, '--notes-file', notes]);
    } finally { await rm(temp, { recursive: true, force: true }); }
  } else if (!existing.assets.some(asset => asset.name === built.filename)) {
    run('gh', ['release', 'upload', tag, built.file, '--repo', flags.repo]);
  } else {
    const temp = await mkdtemp(path.join(os.tmpdir(), 'cliperx-widget-verify-'));
    try {
      run('gh', ['release', 'download', tag, '--repo', flags.repo, '--pattern', built.filename, '--dir', temp]);
      assert(digest(await readFile(path.join(temp, built.filename))) === built.sha256, 'Released package differs. Bump the widget version');
    } finally { await rm(temp, { recursive: true, force: true }); }
  }
  const entry = validateEntry({ manifest: built.pkg.manifest,
    packageURL: `https://github.com/${flags.repo}/releases/download/${tag}/${built.filename}`,
    sha256: built.sha256, sourceURL: `https://github.com/${flags.repo}/tree/${sha}${relative ? `/${relative}` : ''}` });
  const entryFile = path.join(path.dirname(built.file), `${built.pkg.manifest.id}.entry.json`);
  await writeFile(entryFile, `${JSON.stringify(entry, null, 2)}\n`);
  print({ entry: entryFile, ...entry });
}

function addEntry(index, entry) {
  assert(index.schemaVersion === 1 && Array.isArray(index.widgets), 'Invalid catalog');
  const previous = index.widgets.find(item => item.manifest.id === entry.manifest.id);
  if (previous?.manifest.version === entry.manifest.version) assert(previous.sha256 === entry.sha256, 'Same version has a different package hash');
  index.widgets = [...index.widgets.filter(item => item.manifest.id !== entry.manifest.id), entry]
    .sort((a, b) => a.manifest.id.localeCompare(b.manifest.id));
  return index;
}

async function submit() {
  assert(flags.entry, 'Pass --entry dist/component.entry.json');
  const entry = validateEntry(JSON.parse(await readFile(flags.entry, 'utf8')));
  const catalog = flags.catalog ?? 'hanhang-han/cliperx-widgets';
  assert(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(catalog), 'Invalid catalog repository');
  const user = github('user').login;
  const canonical = github(`repos/${catalog}`);
  const current = github(`repos/${catalog}/contents/registry/index.json?ref=${canonical.default_branch}`);
  const index = JSON.parse(Buffer.from(current.content, 'base64').toString('utf8'));
  const previous = index.widgets.find(item => item.manifest.id === entry.manifest.id);
  if (previous?.manifest.version === entry.manifest.version && previous.sha256 === entry.sha256) { print('Already in the workshop catalog'); return; }
  addEntry(index, entry);
  const own = canonical.owner.login.toLowerCase() === user.toLowerCase();
  const target = own ? catalog : `${user}/${canonical.name}`;
  if (!own) run('gh', ['repo', 'fork', catalog, '--clone=false']);
  const branch = `widgets/${entry.manifest.id}-${entry.manifest.version}`;
  const base = github(`repos/${catalog}/git/ref/heads/${canonical.default_branch}`).object.sha;
  try { github(`repos/${target}/git/refs`, { ref: `refs/heads/${branch}`, sha: base }); }
  catch (error) { if (!String(error.stderr ?? error.message).includes('Reference already exists')) throw error; }
  const branchFile = github(`repos/${target}/contents/registry/index.json?ref=${encodeURIComponent(branch)}`);
  github(`repos/${target}/contents/registry/index.json`, { message: `widget: ${entry.manifest.id} v${entry.manifest.version}`,
    branch, sha: branchFile.sha, content: Buffer.from(`${JSON.stringify(index, null, 2)}\n`).toString('base64') }, 'PUT');
  const head = `${user}:${branch}`;
  const prs = JSON.parse(run('gh', ['pr', 'list', '--repo', catalog, '--head', head, '--state', 'open', '--json', 'url']));
  if (prs.length) { print(prs[0].url); return; }
  const temp = await mkdtemp(path.join(os.tmpdir(), 'cliperx-widget-submit-'));
  try {
    const body = path.join(temp, 'body.md');
    await writeFile(body, `Add ${entry.manifest.name} v${entry.manifest.version}.\n\nSource ${entry.sourceURL}\n\nPackage ${entry.packageURL}\n\nSHA256 ${entry.sha256}\n\nRequested permissions\n\n\u0060\u0060\u0060json\n${JSON.stringify(entry.manifest.permissions, null, 2)}\n\u0060\u0060\u0060\n`);
    print(run('gh', ['pr', 'create', '--repo', catalog, '--head', head, '--base', canonical.default_branch,
      '--title', `widget: ${entry.manifest.name} v${entry.manifest.version}`, '--body-file', body]));
  } finally { await rm(temp, { recursive: true, force: true }); }
}

try {
  if (['login', 'logout', 'whoami', 'upload', 'status', 'import', 'withdraw'].includes(command) || command === 'submit' && flags.submission) {
    await runWorkshopCommand(command, directory, flags, print, positionals[0]);
  } else if (command === 'create') await create();
  else if (command === 'validate') { const pkg = await loadProject(directory); print(`Valid API ${pkg.manifest.apiVersion} widget: ${pkg.manifest.id} v${pkg.manifest.version}`); }
  else if (command === 'pack') { const result = await pack(directory, path.resolve(flags.out ?? 'dist')); print({ file: result.file, sha256: result.sha256 }); }
  else if (command === 'preview') {
    const pkg = await loadProject(directory);
    const fixture = flags.fixture ? JSON.parse(await readFile(flags.fixture, 'utf8')) : {};
    const context = { now: new Date().toISOString(), settings: Object.fromEntries((pkg.manifest.settings ?? []).map(field => [field.key, field.default])),
      state: {}, data: {}, errors: {}, ...fixture };
    if (flags.live) await liveSources(pkg, context);
    const result = flags.runner && pkg.script ? JSON.parse(run(flags.runner, [], { input: JSON.stringify({ script: pkg.script, context, action: flags.action ?? null }), timeout: 3000 }))
      : preview(pkg, context, flags.action ?? null);
    const output = validateResult(result, pkg.manifest, flags.action);
    if (pkg.manifest.task) {
      output.taskPreview = { input: pkg.manifest.task.input, parameters: pkg.manifest.task.parameters };
      try { output.taskPreview.instruction = renderTask(pkg.manifest.task, fixture.parameters, fixture.question); }
      catch (error) { output.taskPreview.error = error.message; }
    }
    print(output);
  } else if (command === 'publish') await publish();
  else if (command === 'submit') await submit();
  else if (command === 'catalog-add') {
    assert(flags.entry, 'Pass --entry');
    const entry = validateEntry(JSON.parse(await readFile(flags.entry, 'utf8')));
    const file = path.join(directory, 'registry/index.json');
    const index = addEntry(JSON.parse(await readFile(file, 'utf8')), entry);
    await writeFile(file, `${JSON.stringify(index, null, 2)}\n`);
    print(`Added ${entry.manifest.id}`);
  } else {
    print('CliperX Widget CLI 0.2\n\ncreate DIR --id com.author.name --name NAME --author NAME [--template basic|info|task-context|task-ai|task-text|task-basket|native-music|native-agent|native-metric|native-basket|native-ccswitch]\nvalidate DIR\npreview DIR [--fixture context.json] [--live] [--action ID] [--runner PATH]\npack DIR [--out dist]\npublish DIR --repo owner/repo [--tag TAG]\nlogin [--no-open] [--api URL]\nlogout\nwhoami\nupload DIR [--source HTTPS_URL] [--metadata workshop.json] [--draft] [--api URL]\nimport --entry dist/id.entry.json [--draft]\nstatus [SUBMISSION_ID]\nsubmit --submission ID\nwithdraw ID\nsubmit --entry dist/id.entry.json [--catalog owner/catalog]\ncatalog-add CATALOG_DIR --entry dist/id.entry.json');
  }
} catch (error) {
  let message = error.message;
  if (error.stdout) {
    try { message = JSON.parse(String(error.stdout)).error ?? message; } catch {}
  }
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
}

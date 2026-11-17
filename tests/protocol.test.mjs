import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { digest, loadProject, pack, preview, sourceURL, validateEntry, validateManifest, validateMetadata, validateResult } from '../lib/protocol.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const focus = await loadProject(path.join(root, 'examples/focus-timer'));
const github = await loadProject(path.join(root, 'examples/github-stars'));
const context = { now: '2026-11-15T02:00:00Z', settings: { minutes: '25' }, state: {}, data: {}, errors: {} };

test('focus start, pause, resume, completion and reset preserve the remaining duration', () => {
  const start = preview(focus, context, 'toggle');
  assert.equal(start.view.countdownTo, '2026-11-15T02:25:00.000Z');
  const pauseContext = { ...context, now: '2026-11-15T02:05:00Z', state: start.state };
  const pause = preview(focus, pauseContext, 'toggle');
  assert.equal(pause.view.value, '20:00');
  assert.equal(pause.view.countdownTo, undefined);
  const resume = preview(focus, { ...context, now: '2026-11-15T02:10:00Z', state: pause.state }, 'toggle');
  assert.equal(resume.view.countdownTo, '2026-11-15T02:30:00.000Z');
  const completed = preview(focus, { ...context, now: '2026-11-15T03:00:00Z', state: resume.state });
  assert.equal(completed.view.value, '0:00');
  assert.equal(completed.view.progress, 1);
  assert.deepEqual(preview(focus, { ...context, state: resume.state }, 'reset').state, {});
});

test('GitHub widget handles source failure, actual data and an explicit open action', () => {
  const input = { ...context, settings: { owner: 'hanhang-han', repository: 'cliperx-widgets' } };
  assert.equal(preview(github, input).view.value, '—');
  const loaded = { ...input, data: { repository: { stargazers_count: 12, forks_count: 2, open_issues_count: 3, full_name: 'hanhang-han/cliperx-widgets' } } };
  assert.equal(preview(github, loaded).view.value, '12');
  assert.equal(preview(github, loaded, 'open').effects[0].value, 'https://github.com/hanhang-han/cliperx-widgets');
});

test('URL settings are encoded inside the declared domain and reject extra network access', () => {
  const url = sourceURL(github.manifest, github.manifest.sources.repository, { owner: 'a/b?x=1', repository: 'r' });
  assert.equal(url.hostname, 'api.github.com');
  assert.equal(url.pathname, '/repos/a%2Fb%3Fx%3D1/r');
  for (const address of ['http://api.github.com/x', 'https://localhost/x', 'https://127.0.0.1/x', 'https://user:pass@api.github.com/x', 'https://example.com/x']) {
    assert.throws(() => sourceURL(github.manifest, { url: address }, {}));
  }
});

test('background effects and undeclared permissions are rejected before execution', () => {
  const result = preview(focus, context);
  const copying = { ...result, effects: [{ type: 'clipboard.write', value: 'sample' }] };
  assert.throws(() => validateResult(copying, focus.manifest, null));
  assert.throws(() => validateResult(copying, focus.manifest, 'copy'));
  const permitted = { ...focus.manifest, permissions: { ...focus.manifest.permissions, clipboardWrite: true } };
  assert.equal(validateResult(copying, permitted, 'copy').effects.length, 1);
});

test('invalid identifiers, sizes, intervals and duplicate settings cannot be packaged', () => {
  for (const patch of [{ id: '../unsafe' }, { apiVersion: 5 }, { version: 'latest' }, { sizes: ['large'] }, { refreshSeconds: 0 },
    { settings: [{ key: 'x', title: 'X', default: '' }, { key: 'x', title: 'X', default: '' }] }]) {
    assert.throws(() => validateManifest({ ...focus.manifest, ...patch }));
  }
});

test('card and state limits prevent oversized or invalid native output', () => {
  const result = preview(focus, context);
  for (const patch of [{ progress: -1 }, { progress: Infinity }, { series: Array(61).fill(0) },
    { value: 'x'.repeat(121) }, { details: [{ label: 'same', value: '1' }, { label: 'same', value: '2' }] }]) {
    assert.throws(() => validateResult({ ...result, view: { ...result.view, ...patch } }, focus.manifest, null));
  }
  assert.throws(() => validateResult({ ...result, state: { payload: 'x'.repeat(16384) } }, focus.manifest, null));
});

test('packaging is deterministic and the package includes the complete original script', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'cliperx-pack-test-'));
  try {
    const first = await pack(path.join(root, 'examples/focus-timer'), temp);
    const second = await pack(path.join(root, 'examples/focus-timer'), temp);
    assert.equal(first.sha256, second.sha256);
    const data = await readFile(first.file);
    assert.equal(digest(data), first.sha256);
    assert.equal(JSON.parse(data).script, focus.script);
  } finally { await rm(temp, { recursive: true, force: true }); }
});

test('a newly created component can be validated, previewed and packaged through the CLI', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'cliperx-cli-test-'));
  const cli = path.join(root, 'bin/widget.mjs');
  const project = path.join(temp, 'sample');
  try {
    const run = args => execFileSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    run(['create', project, '--id', 'com.example.sample', '--author', 'Example']);
    assert.match(run(['validate', project]), /Valid API 1/);
    assert.equal(JSON.parse(run(['preview', project])).view.value, 'Hello, 灵剪');
    const output = JSON.parse(run(['pack', project, '--out', path.join(temp, 'dist')]));
    assert.equal(JSON.parse(await readFile(output.file, 'utf8')).manifest.id, 'com.example.sample');
  } finally { await rm(temp, { recursive: true, force: true }); }
});

test('base templates generate independent data and native task widgets', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'cliperx-base-test-'));
  const cli = path.join(root, 'bin/widget.mjs');
  try {
    for (const [template, apiVersion, action, effect] of [
      ['info', 1, null, null],
      ['task-context', 2, 'prepare', 'context.prepare'],
      ['task-text', 2, 'process', 'text.process'],
      ['task-basket', 2, 'open', 'basket.open']
    ]) {
      const project = path.join(temp, template);
      const id = `com.example.${template}`;
      execFileSync(process.execPath, [cli, 'create', project, '--id', id, '--name', template,
        '--author', 'Example', '--template', template]);
      const pkg = await loadProject(project);
      assert.equal(pkg.manifest.id, id);
      assert.equal(pkg.manifest.apiVersion, apiVersion);
      const previewContext = { ...context, settings: Object.fromEntries((pkg.manifest.settings ?? []).map(field => [field.key, field.default])) };
      const baseline = preview(pkg, previewContext);
      assert.ok(baseline.view.value);
      if (effect) {
        assert.deepEqual(preview(pkg, previewContext, action).effects, [{ type: effect, value: '' }]);
        assert.deepEqual(pkg.manifest.sizes, ['small']);
      } else {
        assert.ok(baseline.view.subtitle);
      }
    }
  } finally { await rm(temp, { recursive: true, force: true }); }
});

test('basket base exposes only shared status and requires explicit native permission', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'cliperx-basket-base-'));
  try {
    const project = path.join(temp, 'basket');
    execFileSync(process.execPath, [path.join(root, 'bin/widget.mjs'), 'create', project,
      '--id', 'com.example.basket', '--author', 'Example', '--template', 'task-basket']);
    const pkg = await loadProject(project);
    const input = { ...context, collectionBasket: { count: 3, autoCollect: true, isOpen: false, isPasting: false } };
    assert.equal(preview(pkg, input).view.value, '3 条 · 收集中');
    assert.deepEqual(preview(pkg, input, 'open').effects, [{ type: 'basket.open', value: '' }]);
    assert.throws(() => validateResult(preview(pkg, input, 'open'),
      { ...pkg.manifest, permissions: { ...pkg.manifest.permissions, collectionBasket: false } }, 'open'));
  } finally { await rm(temp, { recursive: true, force: true }); }
});

test('developer preview interrupts an infinite loop', () => {
  assert.throws(() => preview({ ...focus, script: 'while (true) {}' }, context), /timed out/);
});

const nativeProjects = ['context-preparation', 'text-processing', 'ai-usage'];
for (const slug of nativeProjects) {
  test(`API 2 ${slug} renders offline, requests its declared native capability and rejects background effects`, async () => {
    const pkg = await loadProject(path.join(root, 'examples', slug));
    const actions = { 'context-preparation': 'prepare', 'text-processing': 'process', 'ai-usage': 'refresh' };
    const baseline = preview(pkg, context);
    const result = preview(pkg, context, actions[slug]);
    assert.equal(result.effects.length, 1);
    assert.throws(() => validateResult(result, pkg.manifest, null));
    assert.throws(() => validateResult(result, { ...pkg.manifest, permissions: {} }, actions[slug]));
    assert.throws(() => validateManifest({ ...pkg.manifest, apiVersion: 1 }));
    assert.ok(baseline.view.value);
    assert.throws(() => validateResult({ ...result, effects: [{ ...result.effects[0], value: 'injected text' }] }, pkg.manifest, actions[slug]));
  });
}

test('AI cards show genuine context counts and quota windows, including stale and unavailable states', async () => {
  const contextWidget = await loadProject(path.join(root, 'examples/context-preparation'));
  const pack = preview(contextWidget, { ...context, contextPack: { count: 3, estimatedTokens: 2000, shortened: 1, unavailable: 0 } });
  assert.equal(pack.view.value, '已选 3 项');
  const quota = await loadProject(path.join(root, 'examples/ai-usage'));
  const input = { ...context, settings: { provider: 'codex' }, aiUsage: { status: 'ready', windows: [{ label: 'Weekly', usedPercent: 6, resetsAt: '2026-11-21T03:00:00Z' }] } };
  assert.equal(preview(quota, input).view.value, '剩余 94%');
  assert.equal(preview(quota, input).view.progress, undefined);
  assert.match(preview(quota, { ...input, aiUsage: { ...input.aiUsage, status: 'stale' } }).view.subtitle, /缓存/);
  assert.equal(preview(quota, { ...context, aiUsage: { status: 'unavailable' } }).view.value, '暂不可用');
});


test('primary actions directly enter selection and require a declared action', async () => {
  const pkg = await loadProject(path.join(root, 'examples/context-preparation'));
  const result = preview(pkg, context);
  assert.equal(result.view.primaryAction, 'prepare');
  assert.throws(() => validateResult({ ...result, view: { ...result.view, primaryAction: 'missing' } }, pkg.manifest, null));
});

test('usage shows text-only remaining quota and a relative reset for the tightest window', async () => {
  const pkg = await loadProject(path.join(root, 'examples/ai-usage'));
  const input = { ...context, aiUsage: { status: 'ready', windows: [
    { label: 'Weekly', usedPercent: 30, resetsAt: '2026-11-20T02:00:00Z', windowMinutes: 10080 },
    { label: 'Session', usedPercent: 80, resetsAt: '2026-11-15T05:00:00Z', windowMinutes: 300 }
  ] } };
  const view = preview(pkg, input).view;
  assert.equal(view.value, '剩余 20%');
  assert.equal(view.subtitle, '3 小时后重置');
  assert.equal(view.progress, undefined);
  assert.match(view.title, /5 小时/);
  const weekly = preview(pkg, { ...input, aiUsage: { ...input.aiUsage, windows: [input.aiUsage.windows[0]] } }).view;
  assert.equal(weekly.subtitle, '5 天后重置');
});

test('API 3 native templates validate and pack without a JavaScript file', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'cliperx-native-template-'));
  try {
    for (const name of ['music', 'agent', 'metric', 'basket']) {
      const project = path.join(temp, name);
      execFileSync(process.execPath, [path.join(root, 'bin/widget.mjs'), 'create', project,
        '--id', `com.example.native-${name}`, '--name', name, '--author', 'Test', '--template', `native-${name}`]);
      const pkg = await loadProject(project);
      assert.equal(pkg.manifest.apiVersion, 3);
      assert.equal(pkg.manifest.presentation.card, name);
      assert.equal(pkg.script, '');
      assert.equal(preview(pkg, {}).previewKind, 'declaration');
      assert.throws(() => preview(pkg, {}, 'play'));
      const built = await pack(project, path.join(temp, 'dist'));
      assert.equal(JSON.parse(await readFile(built.file, 'utf8')).manifest.presentation.card, name);
    }
  } finally { await rm(temp, { recursive: true, force: true }); }
});

test('native presentation, events and actions enforce matching capability permissions', () => {
  const music = { ...focus.manifest, apiVersion: 3,
    permissions: { ...focus.manifest.permissions, musicControl: true },
    presentation: { card: 'music', multipleInstances: false }, subscriptions: ['music'] };
  assert.equal(validateManifest(music).presentation.card, 'music');
  for (const patch of [{ apiVersion: 2 }, { permissions: focus.manifest.permissions },
    { subscriptions: ['music', 'music'] }, { subscriptions: ['agent'] }, { presentation: { card: 'custom' } },
    { presentation: { card: 'music', workspace: 'agent' } }]) {
    assert.throws(() => validateManifest({ ...music, ...patch }));
  }
  const action = { view: { title: 'Music', value: 'Playing' }, state: {}, effects: [{ type: 'music.playPause', value: '' }] };
  assert.equal(validateResult(action, validateManifest(music), 'toggle').effects.length, 1);
  assert.throws(() => validateResult(action, validateManifest(music), null));
  assert.throws(() => validateResult(action, focus.manifest, 'toggle'));
  assert.throws(() => validateResult({ ...action, effects: [{ type: 'music.next', value: 'arbitrary' }] }, validateManifest(music), 'next'));
});


test('catalog origins and CC Switch declarations stay aligned with the host', () => {
  const manifest = validateManifest({ ...focus.manifest, apiVersion: 3,
    permissions: { ...focus.manifest.permissions, providerConfiguration: true },
    presentation: { card: 'ccswitch' } });
  assert.equal(manifest.permissions.providerConfiguration, true);
  assert.throws(() => validateManifest({ ...manifest, permissions: focus.manifest.permissions }));
  const entry = { manifest, packageURL: 'https://api.cliperx.com/api/workshop/package',
    sourceURL: 'https://cliperx.com/workshop/example', sha256: 'a'.repeat(64),
    metadata: { category: 'system', minAppVersion: '4.0.15' } };
  assert.equal(validateEntry(structuredClone(entry)).metadata.category, 'system');
  const local = { ...entry, packageURL: 'http://127.0.0.1:3001/package' };
  assert.throws(() => validateEntry(structuredClone(local)));
  assert.equal(validateEntry(local, { packageOrigin: 'http://127.0.0.1:3001' }).packageURL, local.packageURL);
  assert.throws(() => validateMetadata({ screenshots: ['http://example.com/image.png'] }));
});

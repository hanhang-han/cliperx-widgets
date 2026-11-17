import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

export const bootstrap = 'var __widgetDefinition; function defineWidget(definition) { __widgetDefinition = definition; }';
export const evaluate = `(function () {
  if (!__widgetDefinition || typeof __widgetDefinition.render !== 'function') throw new Error('Missing defineWidget/render');
  var effects = [];
  if (__action !== null) {
    if (typeof __widgetDefinition.onAction !== 'function') throw new Error('Missing onAction');
    var update = __widgetDefinition.onAction(__action, __context) || {};
    if (update.state !== undefined) __context.state = update.state;
    effects = update.effects || [];
  }
  return JSON.stringify({ view: __widgetDefinition.render(__context), state: __context.state, effects: effects });
})()`;

export function assert(condition, message) {
  if (!condition) throw new Error(message);
}
const validKey = value => typeof value === 'string' && /^[a-zA-Z][a-zA-Z0-9_]{0,39}$/.test(value);
const bounded = (value, maximum, minimum = 0) => typeof value === 'string' && [...value].length >= minimum && [...value].length <= maximum;
export const validHost = value => typeof value === 'string' && value.length <= 253 && !value.endsWith('.local')
  && /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$/.test(value);
export const digest = data => createHash('sha256').update(data).digest('hex');

export function sourceURL(manifest, source, settings) {
  let value = source.url;
  for (const field of manifest.settings ?? []) {
    const setting = settings[field.key] ?? field.default;
    assert(bounded(setting, 500), `Invalid setting ${field.key}`);
    const encoded = encodeURIComponent(setting).replace(/[!'()*]/g, char => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
    value = value.replaceAll(`{{${field.key}}}`, encoded);
  }
  assert(!value.includes('{{'), 'Unresolved source setting');
  const url = new URL(value);
  assert(url.protocol === 'https:' && !url.username && !url.password && (!url.port || url.port === '443')
    && validHost(url.hostname) && manifest.permissions.network.includes(url.hostname), 'Source exceeds network permissions');
  return url;
}

export function validateTask(task) {
  assert(task && typeof task === 'object' && !Array.isArray(task), 'Invalid AI task');
  const input = task.input;
  assert(input && Array.isArray(input.types) && input.types.length >= 1 && input.types.length <= 2
    && new Set(input.types).size === input.types.length && input.types.every(type => ['text', 'image'].includes(type)), 'Invalid AI task input types');
  assert(Number.isInteger(input.minItems) && Number.isInteger(input.maxItems) && input.minItems >= 0
    && input.maxItems >= input.minItems && input.maxItems <= 20, 'Invalid AI task input count');
  assert(Array.isArray(task.parameters) && task.parameters.length <= 8, 'Invalid AI task parameters');
  const names = new Set(['question']);
  for (const parameter of task.parameters) {
    assert(parameter && validKey(parameter.key) && !names.has(`parameters.${parameter.key}`)
      && bounded(parameter.title, 60, 1) && bounded(parameter.default, 500)
      && (parameter.required == null || typeof parameter.required === 'boolean'), 'Invalid or duplicate AI task parameter');
    names.add(`parameters.${parameter.key}`);
  }
  assert(bounded(task.prompt, 12000, 1) && task.output?.format === 'markdown', 'Invalid AI prompt or output format');
  assert([...task.prompt.matchAll(/\{\{([^{}]+)\}\}/g)].every(match => names.has(match[1]))
    && !task.prompt.replace(/\{\{([^{}]+)\}\}/g, '').includes('{{'), 'Unknown AI task template variable');
  return task;
}

export function renderTask(task, parameters = {}, question = '') {
  validateTask(task);
  assert(typeof question === 'string', 'Question must be text');
  assert(parameters && typeof parameters === 'object' && !Array.isArray(parameters), 'Task parameters must be an object');
  const values = new Map([['question', question]]);
  for (const parameter of task.parameters) {
    const value = parameters[parameter.key] ?? parameter.default;
    assert(bounded(value, 500), `${parameter.title} exceeds 500 characters`);
    assert(!parameter.required || value.trim().length > 0, `Please fill ${parameter.title}`);
    values.set(`parameters.${parameter.key}`, value);
  }
  let rendered = task.prompt.replace(/\{\{([^{}]+)\}\}/g, (_, name) => values.get(name));
  if (!task.prompt.includes('{{question}}') && question.trim()) rendered += `\n\n用户补充\n${question}`;
  return rendered;
}

export function validateManifest(input) {
  const manifest = structuredClone(input);
  assert([1, 2, 3, 4].includes(manifest.apiVersion), 'apiVersion must be 1, 2, 3 or 4');
  assert(typeof manifest.id === 'string' && manifest.id.length <= 100 && /^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$/.test(manifest.id), 'Use a reverse-domain component id');
  assert(typeof manifest.version === 'string' && /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(manifest.version), 'version must be x.y.z');
  for (const [field, limit] of Object.entries({ name: 60, author: 80, description: 300, license: 80, symbol: 80 })) {
    assert(bounded(manifest[field], limit, 1), `Invalid ${field}`);
  }
  assert(Array.isArray(manifest.sizes) && manifest.sizes.length >= 1 && manifest.sizes.length <= 2
    && new Set(manifest.sizes).size === manifest.sizes.length && manifest.sizes.every(size => ['small', 'wide'].includes(size)), 'Invalid sizes');
  assert(Number.isInteger(manifest.refreshSeconds) && manifest.refreshSeconds >= 10 && manifest.refreshSeconds <= 86400, 'refreshSeconds must be 10...86400');
  const permission = manifest.permissions ?? {};
  manifest.permissions = { network: permission.network ?? [], openURL: permission.openURL ?? false,
    clipboardWrite: permission.clipboardWrite ?? false, systemMetrics: permission.systemMetrics ?? false };
  if (manifest.apiVersion >= 2) {
    for (const flag of ['contextPreparation', 'textProcessing', 'aiUsage', 'collectionBasket']) manifest.permissions[flag] = permission[flag] ?? false;
  } else {
    assert(!permission.contextPreparation && !permission.textProcessing && !permission.aiUsage && !permission.collectionBasket, 'Native capabilities require API 2');
  }
  for (const flag of ['contextPreparation', 'textProcessing', 'aiUsage', 'collectionBasket']) {
    if (manifest.permissions[flag] !== undefined) assert(typeof manifest.permissions[flag] === 'boolean', `Invalid permission ${flag}`);
  }
  const nativeFlags = ['musicControl', 'agentConversations', 'providerConfiguration', 'powerManagement'];
  if (manifest.apiVersion >= 3) {
    for (const flag of nativeFlags) {
      manifest.permissions[flag] = permission[flag] ?? false;
      assert(typeof manifest.permissions[flag] === 'boolean', `Invalid permission ${flag}`);
    }
  } else {
    assert(manifest.presentation == null && manifest.subscriptions == null && nativeFlags.every(flag => !permission[flag]), 'Native presentation and subscriptions require API 3');
  }
  if (manifest.presentation != null) {
    const p = manifest.presentation;
    assert(p && typeof p === 'object' && !Array.isArray(p), 'Invalid presentation');
    assert(['standard', 'metric', 'music', 'basket', 'agent', 'ccswitch'].includes(p.card), 'Unsupported card renderer');
    assert(p.multipleInstances == null || typeof p.multipleInstances === 'boolean', 'Invalid multipleInstances');
    if (p.card === 'metric') {
      assert(['cpu', 'memory', 'network', 'battery', 'disk', 'clock'].includes(p.metric)
        && (p.metric === 'clock' || manifest.permissions.systemMetrics), 'Metric card requires a valid metric and permission');
    }
    if (p.card === 'ccswitch') assert(manifest.permissions.providerConfiguration && p.workspace == null, 'CC Switch requires providerConfiguration and no workspace');
    if (p.card === 'music') assert(manifest.permissions.musicControl, 'Music card requires musicControl');
    if (p.card === 'agent') assert(manifest.permissions.agentConversations && p.workspace === 'agent', 'Agent card requires its workspace and permission');
    if (p.card === 'basket') assert(manifest.permissions.collectionBasket && p.workspace === 'basket', 'Basket card requires its workspace and permission');
    if (p.workspace != null) {
      const permissions = { context: 'contextPreparation', text: 'textProcessing', basket: 'collectionBasket', agent: 'agentConversations' };
      assert(Object.hasOwn(permissions, p.workspace) && manifest.permissions[permissions[p.workspace]], 'Workspace requires its capability permission');
    }
  }
  if (manifest.task != null) {
    assert(manifest.apiVersion === 4 && manifest.permissions.contextPreparation
      && manifest.presentation?.card === 'standard' && manifest.presentation?.workspace === 'context',
    'Custom AI tasks require API 4, a standard card and the context workspace');
    validateTask(manifest.task);
  }
  const eventPermissions = { metrics: 'systemMetrics', music: 'musicControl', agent: 'agentConversations',
    context: 'contextPreparation', text: 'textProcessing', basket: 'collectionBasket', power: 'powerManagement' };
  const subscriptions = manifest.subscriptions ?? [];
  assert(Array.isArray(subscriptions) && subscriptions.length <= 7 && new Set(subscriptions).size === subscriptions.length
    && subscriptions.every(event => Object.hasOwn(eventPermissions, event) && manifest.permissions[eventPermissions[event]]), 'Subscriptions require capability permissions');
  assert(Array.isArray(manifest.permissions.network) && manifest.permissions.network.length <= 8
    && manifest.permissions.network.every(validHost), 'Invalid network domains');
  for (const flag of ['openURL', 'clipboardWrite', 'systemMetrics']) assert(typeof manifest.permissions[flag] === 'boolean', `Invalid permission ${flag}`);
  assert(Array.isArray(manifest.settings ?? []) && (manifest.settings ?? []).length <= 12, 'Invalid settings');
  const keys = new Set();
  for (const setting of manifest.settings ?? []) {
    assert(validKey(setting.key) && !keys.has(setting.key) && bounded(setting.title, 60, 1) && bounded(setting.default, 500), 'Invalid or duplicate setting');
    keys.add(setting.key);
  }
  const sources = Object.entries(manifest.sources ?? {});
  assert(sources.length <= 4, 'At most four HTTP sources');
  const defaults = Object.fromEntries((manifest.settings ?? []).map(field => [field.key, field.default]));
  for (const [key, source] of sources) {
    assert(validKey(key) && bounded(source.url, 2048), 'Invalid source');
    sourceURL(manifest, source, defaults);
  }
  return manifest;
}

export async function loadProject(directory) {
  const manifest = validateManifest(JSON.parse(await readFile(path.join(directory, 'manifest.json'), 'utf8')));
  const native = manifest.presentation != null && manifest.presentation.card !== 'standard';
  let script = '';
  try { script = await readFile(path.join(directory, 'widget.js'), 'utf8'); }
  catch (error) { if (!native || error.code !== 'ENOENT') throw error; }
  assert(native ? script.length === 0 : Buffer.byteLength(script) > 0, 'Native cards use a manifest, standard cards require widget.js');
  assert(Buffer.byteLength(script) <= 131072, 'Script must fit in 128 KB');
  if (!native) new vm.Script(`${bootstrap}\n${script}\n${evaluate}`, { filename: 'widget.js' });
  return { formatVersion: 1, manifest, script };
}

export function validateResult(result, manifest, action) {
  const view = result.view;
  assert(view && bounded(view.title, 60) && bounded(view.value, 120), 'render must return title and value');
  if (view.subtitle != null) assert(bounded(view.subtitle, 180), 'Subtitle too long');
  if (view.symbol != null) assert(bounded(view.symbol, 80), 'Symbol too long');
  if (view.progress != null) assert(Number.isFinite(view.progress) && view.progress >= 0 && view.progress <= 1, 'Invalid progress');
  if (view.series != null) assert(Array.isArray(view.series) && view.series.length <= 60 && view.series.every(Number.isFinite), 'Invalid series');
  if (view.countdownTo != null) assert(typeof view.countdownTo === 'string' && /T.*Z$/.test(view.countdownTo) && Number.isFinite(Date.parse(view.countdownTo)), 'Invalid countdownTo');
  const rows = view.details ?? [], actions = view.actions ?? [];
  assert(Array.isArray(rows) && rows.length <= 20 && new Set(rows.map(row => row.label)).size === rows.length
    && rows.every(row => bounded(row.label, 80) && bounded(row.value, 500)), 'Invalid detail rows');
  assert(Array.isArray(actions) && actions.length <= 4 && new Set(actions.map(item => item.id)).size === actions.length
    && actions.every(item => validKey(item.id) && bounded(item.title, 40, 1)), 'Invalid actions');
  if (view.primaryAction != null) assert(actions.some(item => item.id === view.primaryAction), 'primaryAction must reference an action');
  assert(result.state && typeof result.state === 'object' && !Array.isArray(result.state)
    && Buffer.byteLength(JSON.stringify(result.state)) <= 16384, 'State must be an object under 16 KB');
  assert(Array.isArray(result.effects) && result.effects.length <= 4 && (action || result.effects.length === 0), 'Effects require a user action');
  for (const effect of result.effects) {
    assert(typeof effect.value === 'string' && Buffer.byteLength(effect.value) <= 8192, 'Invalid effect value');
    if (effect.type === 'clipboard.write') assert(manifest.permissions.clipboardWrite, 'clipboardWrite permission required');
    else if (effect.type === 'openURL') {
      const url = new URL(effect.value);
      assert(manifest.permissions.openURL && url.protocol === 'https:' && !url.username && !url.password && validHost(url.hostname), 'Invalid openURL effect');
    } else if (['context.prepare', 'text.process', 'aiUsage.refresh', 'basket.open'].includes(effect.type)) {
      const permission = { 'context.prepare': 'contextPreparation', 'text.process': 'textProcessing', 'aiUsage.refresh': 'aiUsage', 'basket.open': 'collectionBasket' }[effect.type];
      assert(manifest.apiVersion >= 2 && manifest.permissions[permission], `${permission} permission required`);
      assert(effect.value === '', 'Native capability effects use an empty value');
      const workspace = { 'context.prepare': 'context', 'text.process': 'text', 'basket.open': 'basket' }[effect.type];
      if (workspace && manifest.presentation?.workspace) assert(manifest.presentation.workspace === workspace, 'Effect exceeds the declared workspace');
    } else if (['music.playPause', 'music.previous', 'music.next', 'agent.open'].includes(effect.type)) {
      const permission = effect.type === 'agent.open' ? 'agentConversations' : 'musicControl';
      assert(manifest.apiVersion >= 3 && manifest.permissions[permission] && effect.value === '', `${permission} permission required`);
      if (effect.type === 'agent.open' && manifest.presentation?.workspace) assert(manifest.presentation.workspace === 'agent', 'Effect exceeds the declared workspace');
    } else if (['power.setMode', 'power.toggleLid'].includes(effect.type)) {
      assert(manifest.apiVersion >= 3 && manifest.permissions.powerManagement, 'powerManagement permission required');
      assert(effect.type === 'power.setMode' ? ['automatic', 'manual', 'off'].includes(effect.value) : effect.value === '', 'Invalid power effect value');
    } else throw new Error(`Unsupported effect ${effect.type}`);
  }
  assert(Buffer.byteLength(JSON.stringify(result)) <= 65536, 'Result exceeds 64 KB');
  return result;
}

export function preview(pkg, context, action = null) {
  if (pkg.manifest.presentation != null && pkg.manifest.presentation.card !== 'standard') {
    assert(action == null, 'Native controls are exercised in the App');
    return { view: { title: pkg.manifest.name, value: '由原生宿主渲染' }, state: {}, effects: [],
      presentation: pkg.manifest.presentation, previewKind: 'declaration' };
  }
  const sandbox = Object.create(null);
  // Local developer preview. The application uses its signed, sandboxed JavaScriptCore helper.
  sandbox.__context = structuredClone(context);
  sandbox.__action = action;
  const script = new vm.Script(`${bootstrap}\n${pkg.script}\n${evaluate}`, { filename: 'widget.js' });
  const output = script.runInNewContext(sandbox, { timeout: 500 });
  return validateResult(JSON.parse(output), pkg.manifest, action);
}

export async function pack(directory, outputDirectory) {
  const pkg = await loadProject(directory);
  const data = Buffer.from(`${JSON.stringify(pkg, null, 2)}\n`);
  assert(data.length <= 262144, 'Package exceeds 256 KB');
  await mkdir(outputDirectory, { recursive: true });
  const filename = `${pkg.manifest.id}-${pkg.manifest.version}.cliperxwidget`;
  const file = path.resolve(outputDirectory, filename);
  await writeFile(file, data);
  return { pkg, file, filename, sha256: digest(data) };
}

export function validateMetadata(metadata, { assetOrigin } = {}) {
  assert(metadata && typeof metadata === 'object' && !Array.isArray(metadata), 'Invalid catalog metadata');
  const result = { category: 'other', tags: [], screenshots: [], readme: '', changelog: '', ...structuredClone(metadata) };
  assert(['clipboard', 'ai', 'productivity', 'system', 'other'].includes(result.category), 'Invalid category');
  assert(Array.isArray(result.tags) && result.tags.length <= 8 && result.tags.every(tag => bounded(tag, 40, 1)), 'Invalid tags');
  const safeHTTPS = value => {
    try {
      const url = new URL(value);
      const local = assetOrigin && ['localhost', '127.0.0.1', '[::1]'].includes(new URL(assetOrigin).hostname)
        && url.origin === new URL(assetOrigin).origin;
      return (url.protocol === 'https:' || local) && !url.username && !url.password;
    }
    catch { return false; }
  };
  assert(Array.isArray(result.screenshots) && result.screenshots.length <= 4 && result.screenshots.every(safeHTTPS), 'Invalid screenshots');
  assert(bounded(result.readme, 20000) && bounded(result.changelog, 4000), 'Catalog description too long');
  assert(result.feedbackURL == null || safeHTTPS(result.feedbackURL) && new URL(result.feedbackURL).protocol === 'https:', 'Feedback URL must use HTTPS');
  assert(result.minAppVersion == null || /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(result.minAppVersion), 'Invalid minimum app version');
  return result;
}

export function validateEntry(entry, { packageOrigin } = {}) {
  entry.manifest = validateManifest(entry.manifest);
  const url = new URL(entry.packageURL);
  let localOrigin = false;
  if (packageOrigin) {
    const allowed = new URL(packageOrigin);
    localOrigin = ['localhost', '127.0.0.1', '[::1]'].includes(allowed.hostname)
      && ['http:', 'https:'].includes(allowed.protocol) && url.origin === allowed.origin;
  }
  assert((url.protocol === 'https:' && ['github.com', 'raw.githubusercontent.com', 'api.cliperx.com'].includes(url.hostname) && (!url.port || url.port === '443') || localOrigin)
    && !url.username && !url.password, 'Package must use an approved HTTPS origin');
  assert(/^[0-9a-f]{64}$/.test(entry.sha256), 'Invalid SHA256');
  const source = new URL(entry.sourceURL);
  const localSource = packageOrigin && ['localhost', '127.0.0.1', '[::1]'].includes(new URL(packageOrigin).hostname)
    && source.origin === new URL(packageOrigin).origin;
  assert((source.protocol === 'https:' || localSource) && !source.username && !source.password, 'Source URL must use HTTPS');
  if (entry.metadata != null) entry.metadata = validateMetadata(entry.metadata, { assetOrigin: packageOrigin });
  return entry;
}

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

export function validateManifest(input) {
  const manifest = structuredClone(input);
  assert([1, 2].includes(manifest.apiVersion), 'apiVersion must be 1 or 2');
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
  if (manifest.apiVersion === 2) {
    for (const flag of ['contextPreparation', 'textProcessing', 'aiUsage']) manifest.permissions[flag] = permission[flag] ?? false;
  } else {
    assert(!permission.contextPreparation && !permission.textProcessing && !permission.aiUsage, 'AI capabilities require API 2');
  }
  for (const flag of ['contextPreparation', 'textProcessing', 'aiUsage']) {
    if (manifest.permissions[flag] !== undefined) assert(typeof manifest.permissions[flag] === 'boolean', `Invalid permission ${flag}`);
  }
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
  const script = await readFile(path.join(directory, 'widget.js'), 'utf8');
  assert(Buffer.byteLength(script) > 0 && Buffer.byteLength(script) <= 131072, 'Script must fit in 128 KB');
  new vm.Script(`${bootstrap}\n${script}\n${evaluate}`, { filename: 'widget.js' });
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
  assert(result.state && typeof result.state === 'object' && !Array.isArray(result.state)
    && Buffer.byteLength(JSON.stringify(result.state)) <= 16384, 'State must be an object under 16 KB');
  assert(Array.isArray(result.effects) && result.effects.length <= 4 && (action || result.effects.length === 0), 'Effects require a user action');
  for (const effect of result.effects) {
    assert(typeof effect.value === 'string' && Buffer.byteLength(effect.value) <= 8192, 'Invalid effect value');
    if (effect.type === 'clipboard.write') assert(manifest.permissions.clipboardWrite, 'clipboardWrite permission required');
    else if (effect.type === 'openURL') {
      const url = new URL(effect.value);
      assert(manifest.permissions.openURL && url.protocol === 'https:' && !url.username && !url.password && validHost(url.hostname), 'Invalid openURL effect');
    } else if (['context.prepare', 'text.process', 'aiUsage.refresh'].includes(effect.type)) {
      const permission = { 'context.prepare': 'contextPreparation', 'text.process': 'textProcessing', 'aiUsage.refresh': 'aiUsage' }[effect.type];
      assert(manifest.apiVersion === 2 && manifest.permissions[permission], `${permission} permission required`);
      assert(effect.value === '', 'Native capability effects use an empty value');
    } else throw new Error(`Unsupported effect ${effect.type}`);
  }
  assert(Buffer.byteLength(JSON.stringify(result)) <= 65536, 'Result exceeds 64 KB');
  return result;
}

export function preview(pkg, context, action = null) {
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

export function validateEntry(entry) {
  entry.manifest = validateManifest(entry.manifest);
  const url = new URL(entry.packageURL);
  assert(url.protocol === 'https:' && !url.username && !url.password && ['github.com', 'raw.githubusercontent.com'].includes(url.hostname), 'Package must be hosted on GitHub HTTPS');
  assert(/^[0-9a-f]{64}$/.test(entry.sha256), 'Invalid SHA256');
  assert(new URL(entry.sourceURL).protocol === 'https:', 'Source URL must use HTTPS');
  return entry;
}

import { chmod, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { execFileSync, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { homedir } from 'node:os';
import path from 'node:path';
import { assert, pack, validateEntry, validateMetadata } from './protocol.mjs';

export const defaultWorkshopAPI = 'https://api.cliperx.com/api/workshop';

export function workshopAPI(value = defaultWorkshopAPI) {
  const url = new URL(value);
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  assert(url.protocol === 'https:' || url.protocol === 'http:' && loopback, 'Workshop API requires HTTPS or an explicit local development origin');
  assert(!url.username && !url.password && !url.search && !url.hash, 'Invalid workshop API URL');
  return url.href.replace(/\/$/, '');
}

function credentialLocation(api) {
  const key = createHash('sha256').update(api).digest('hex');
  return {
    service: `com.cliperx.widget-workshop.${key}`,
    file: path.join(homedir(), '.config', 'cliperx-widgets', `${key}.json`),
  };
}

function security(args, input) {
  return execFileSync('/usr/bin/security', args, { input, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
}

export async function loadWorkshopCredential(api) {
  const location = credentialLocation(api);
  try {
    if (process.platform === 'darwin') {
      return { token: security(['find-generic-password', '-s', location.service, '-a', 'cli', '-w']) };
    }
    return JSON.parse(await readFile(location.file, 'utf8'));
  } catch { return null; }
}

async function saveCredential(api, credential) {
  assert(/^cxworkshop\.[A-Za-z0-9_-]+$/.test(credential.token), 'Unexpected workshop token format');
  const location = credentialLocation(api);
  if (process.platform === 'darwin') {
    // The token is sent to security's interactive stdin, so it never enters process arguments.
    security(['-i'], `add-generic-password -U -s ${location.service} -a cli -w ${credential.token}\n`);
    return;
  }
  await mkdir(path.dirname(location.file), { recursive: true, mode: 0o700 });
  await chmod(path.dirname(location.file), 0o700);
  await writeFile(location.file, JSON.stringify(credential), { mode: 0o600 });
  await chmod(location.file, 0o600);
}

async function removeCredential(api) {
  const location = credentialLocation(api);
  if (process.platform === 'darwin') {
    try { security(['delete-generic-password', '-s', location.service, '-a', 'cli']); } catch { /* Already removed. */ }
  } else await rm(location.file, { force: true });
}

export async function workshopRequest(api, route, { method = 'GET', json, bytes, token, pending = false } = {}) {
  const response = await fetch(`${api}${route}`, {
    method,
    redirect: 'error',
    signal: AbortSignal.timeout(30000),
    headers: {
      Accept: 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(json !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(bytes ? { 'Content-Type': 'application/octet-stream' } : {}),
    },
    body: json !== undefined ? JSON.stringify(json) : bytes,
  });
  const body = await response.json();
  if (!response.ok || response.status === 202 && !pending) {
    throw new Error(body.message || body.error || `Workshop request failed (HTTP ${response.status})`);
  }
  return body;
}

function openBrowser(url) {
  const [program, args] = process.platform === 'darwin' ? ['open', [url]]
    : process.platform === 'win32' ? ['rundll32', ['url.dll,FileProtocolHandler', url]] : ['xdg-open', [url]];
  const child = spawn(program, args, { detached: true, stdio: 'ignore' });
  child.on('error', () => {});
  child.unref();
}

async function login(api, flags, print) {
  const pending = await workshopRequest(api, '/cli/sessions', { method: 'POST', json: {} });
  const verification = new URL(pending.verificationURL);
  const apiURL = new URL(api);
  assert(verification.protocol === 'https:' || verification.origin === apiURL.origin && apiURL.protocol === 'http:', 'Invalid verification URL');
  assert(typeof pending.deviceCode === 'string' && typeof pending.userCode === 'string', 'Invalid authorization response');
  print(`在浏览器确认工坊登录，验证码 ${pending.userCode}\n${verification.href}`);
  if (!flags['no-open']) openBrowser(verification.href);
  const expires = Date.now() + Math.min(Number(pending.expiresIn) || 600, 600) * 1000;
  const interval = Math.max(1, Math.min(Number(pending.interval) || 3, 15)) * 1000;
  while (Date.now() < expires) {
    await new Promise(resolve => setTimeout(resolve, interval));
    const result = await workshopRequest(api, '/cli/token', { method: 'POST', json: { deviceCode: pending.deviceCode }, pending: true });
    if (result.status === 'pending') continue;
    assert(typeof result.token === 'string', 'Authorization response did not include a token');
    await saveCredential(api, result);
    print(`已登录 ${result.user?.name || result.user?.userId || '灵剪工坊账号'}`);
    return;
  }
  throw new Error('浏览器授权已过期，请重新执行 login');
}

export async function runWorkshopCommand(command, directory, flags, print, identifier) {
  const api = workshopAPI(flags.api);
  if (command === 'login') return login(api, flags, print);
  const credential = await loadWorkshopCredential(api);
  const token = credential?.token;
  assert(token, '先执行 login 登录灵剪工坊');
  const request = (route, options = {}) => workshopRequest(api, route, { ...options, token });
  if (command === 'logout') {
    await request('/cli/logout', { method: 'POST', json: {} });
    await removeCredential(api);
    print('已退出灵剪工坊');
    return;
  }
  if (command === 'whoami') { print(await request('/me')); return; }
  if (command === 'status') {
    print(await request(identifier ? `/submissions/${encodeURIComponent(identifier)}` : '/submissions/mine'));
    return;
  }
  if (command === 'import') {
    assert(flags.entry, 'Pass --entry dist/component.entry.json');
    const entry = validateEntry(JSON.parse(await readFile(flags.entry, 'utf8')));
    let { submission } = await request('/import', { method: 'POST', json: { entry } });
    if (!flags.draft && submission.status !== 'published' && submission.status !== 'submitted') {
      ({ submission } = await request(`/submissions/${submission.id}/submit`, { method: 'POST', json: { expectedRevision: submission.revision } }));
    }
    print({ submission });
    return;
  }
  if (command === 'submit' || command === 'withdraw') {
    const id = flags.submission || identifier;
    assert(id, 'Pass --submission ID');
    const { submission } = await request(`/submissions/${encodeURIComponent(id)}`);
    print(await request(`/submissions/${encodeURIComponent(id)}/${command}`, { method: 'POST', json: { expectedRevision: submission.revision } }));
    return;
  }
  assert(command === 'upload', 'Unknown workshop command');
  const built = await pack(directory, path.resolve(flags.out ?? path.join(directory, 'dist')));
  let metadata = {};
  const metadataFile = flags.metadata || path.join(directory, 'workshop.json');
  try { metadata = validateMetadata(JSON.parse(await readFile(metadataFile, 'utf8'))); }
  catch (error) { if (flags.metadata || error.code !== 'ENOENT') throw error; }
  const sourceURL = flags.source || `https://cliperx.com/workshop/${built.pkg.manifest.id}`;
  const source = new URL(sourceURL);
  assert(source.protocol === 'https:' && !source.username && !source.password, 'Source URL must use HTTPS');
  let { submission } = await request('/submissions', { method: 'POST', json: {
    widgetId: built.pkg.manifest.id, version: built.pkg.manifest.version, sourceURL, metadata,
  } });
  if (submission.status === 'published' || submission.status === 'submitted') {
    assert(submission.sha256 === built.sha256, '该版本已有不同内容，请撤回待审投稿或递增版本');
    print({ submission });
    return;
  }
  ({ submission } = await request(`/submissions/${submission.id}`, { method: 'PATCH', json: {
    expectedRevision: submission.revision, sourceURL, metadata,
  } }));
  ({ submission } = await request(`/submissions/${submission.id}/package?revision=${submission.revision}`, {
    method: 'PUT', bytes: await readFile(built.file),
  }));
  if (!flags.draft) {
    ({ submission } = await request(`/submissions/${submission.id}/submit`, { method: 'POST', json: { expectedRevision: submission.revision } }));
  }
  print({ file: built.file, sha256: built.sha256, submission });
}

#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { isDeepStrictEqual } from 'node:util';
import { assert, digest, validateEntry } from '../lib/protocol.mjs';

const catalog = JSON.parse(await readFile(new URL('../registry/index.json', import.meta.url), 'utf8'));
assert(catalog.schemaVersion === 1 && Array.isArray(catalog.widgets), 'Invalid catalog schema');
assert(new Set(catalog.widgets.map(entry => entry.manifest.id)).size === catalog.widgets.length, 'Duplicate component IDs');
for (const entry of catalog.widgets) {
  validateEntry(entry);
  if (process.argv.includes('--download')) {
    const response = await fetch(entry.packageURL, { signal: AbortSignal.timeout(30000) });
    assert(response.ok, `Download failed: ${entry.manifest.id} HTTP ${response.status}`);
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      assert(size <= 262144, 'Package exceeds 256 KB');
      chunks.push(chunk);
    }
    const data = Buffer.concat(chunks);
    assert(digest(data) === entry.sha256, `Checksum mismatch: ${entry.manifest.id}`);
    const pkg = JSON.parse(data.toString('utf8'));
    assert(pkg.formatVersion === 1 && typeof pkg.script === 'string', 'Invalid package');
    assert(isDeepStrictEqual(validateEntry({ ...entry, manifest: pkg.manifest }).manifest, entry.manifest), 'Manifest mismatch');
  }
  process.stdout.write(`Verified ${entry.manifest.id} v${entry.manifest.version}\n`);
}

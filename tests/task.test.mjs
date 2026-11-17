import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { loadProject, preview, renderTask, validateManifest, validateTask } from '../lib/protocol.mjs';

const project = await loadProject(fileURLToPath(new URL('../examples/bug-report/', import.meta.url)));

test('API 4 task variables, required values and literal substitutions follow the native contract', () => {
  const task = project.manifest.task;
  assert.throws(() => renderTask(task), /Please fill/);
  assert.throws(() => renderTask(task, { product: '  ' }), /Please fill/);
  assert.match(renderTask(task, { product: '灵剪' }, '补充要求'), /灵剪.*补充要求/);
  const literal = renderTask(task, { product: '{{question}}', severity: '{{parameters.product}}' }, '$& {{parameters.product}}');
  assert.match(literal, /你负责整理 \{\{question\}\} 的 Bug 单/);
  assert.match(literal, /影响程度要求 \{\{parameters.product\}\}/);
  assert.ok(literal.endsWith('$& {{parameters.product}}'));
  for (const prompt of ['{{unknown}}', '{{parameters.missing}}', '{{question', '{{}}']) {
    assert.throws(() => validateTask({ ...task, prompt }), /Unknown/);
  }
  assert.equal(renderTask({ ...task, prompt: '整理 {{parameters.product}}' }, { product: '灵剪' }, '附加内容'), '整理 灵剪\n\n用户补充\n附加内容');
  assert.throws(() => validateManifest({ ...project.manifest, apiVersion: 3 }));
  assert.throws(() => validateManifest({ ...project.manifest, presentation: { card: 'music', workspace: 'context' } }));
  const result = preview(project, { state: {}, contextPack: { count: 2 } }, 'prepare');
  assert.deepEqual(result.effects, [{ type: 'context.prepare', value: '' }]);
});

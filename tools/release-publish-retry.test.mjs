import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const workflow = readFileSync(new URL('../.github/workflows/release.yml', import.meta.url), 'utf8');

test('release publication retries transient GitHub API failures without duplicating a draft', () => {
  assert.match(workflow, /function retry_github_release_command\(\)/);
  assert.match(workflow, /function create_draft_release\(\)/);
  assert.match(workflow, /if gh release view "\$TAG" >\/dev\/null 2>&1; then\s+return 0/);
  assert.match(workflow, /create_draft_release/);
  assert.match(workflow, /retry_github_release_command gh release upload/);
  assert.match(workflow, /gh release view "\$TAG" >\/dev\/null 2>&1/);
});

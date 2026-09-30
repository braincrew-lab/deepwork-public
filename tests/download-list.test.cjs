const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

// Execute the shipped inline renderer; only DOM storage and network are fakes.
async function render(releases) {
  class Element {
    constructor() { this.children = []; this.textContent = ''; }
    set innerHTML(value) { this.children = []; }
    appendChild(child) { this.children.push(child); }
  }
  const bodies = { 'version-rows-mac': new Element(), 'version-rows-win': new Element() };
  const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)];
  const renderer = scripts.find((match) => match[1].includes('version-rows-mac'));
  assert.ok(renderer, 'shipped download renderer exists');
  vm.runInNewContext(renderer[1], {
    document: { getElementById: (id) => bodies[id], createElement: () => new Element() },
    fetch: async () => ({ ok: true, json: async () => releases }),
  });
  await new Promise(setImmediate);
  const text = (node) => node.textContent + node.children.map(text).join(' ');
  return Object.fromEntries(Object.entries(bodies).map(([id, body]) => [id, body.children.map(text)]));
}

function release(tag, names = [], extra = {}) {
  return { tag_name: tag, html_url: `https://github.com/braincrew-lab/deepwork-public/releases/tag/${tag}`,
    assets: names.map((name) => ({ name, browser_download_url: `https://example.test/${name}` })), ...extra };
}

test('CLI releases never enter either desktop table or consume its row limit/count', async () => {
  const input = [
    release('deepcode-cli-v0.3.0'),
    release('deepcode-cli-v0.2.4', ['deepcode-darwin-arm64.tar.gz']),
    release('deepcode-cli-v0.2.3', ['deepcode-windows.zip']),
    release('deepcode-cli-v0.2.2', ['future.dmg', 'future.msix']),
    ...Array.from({ length: 7 }, (_, i) => release(`v0.7.${13 - i}`, ['DeepWork.dmg', 'DeepWork.appx'])),
  ];
  const before = JSON.stringify(input);
  const rows = await render(input);
  for (const platform of Object.values(rows)) {
    assert.doesNotMatch(platform.join(' '), /deepcode-cli-/);
    assert.equal(platform.length, 7);
    assert.match(platform[0], /v0\.7\.13/);
    assert.match(platform[5], /v0\.7\.8/);
    assert.match(platform[6], /이전 1개 더 보기/);
  }
  assert.equal(JSON.stringify(input), before, 'release metadata remains unchanged');
});

test('desktop assets, preview badges, note-only fallback and existing exclusions survive', async () => {
  const rows = await render([
    release('v0.7.13', ['DeepWork.dmg', 'DeepWork.appx']),
    release('v0.7.2-preview.4', ['Preview.dmg'], { prerelease: true }),
    release('v0.6.9'), release('v0.6.8-win-proof.1'),
    release('deep-work-vm-test', ['VM.dmg']),
    release('v0.5.7', ['Withheld.dmg']),
    release('v0.8.0', ['Draft.dmg'], { draft: true }),
  ]);
  assert.equal(rows['version-rows-mac'].length, 3);
  assert.equal(rows['version-rows-win'].length, 2);
  assert.match(rows['version-rows-mac'][0], /DeepWork\.dmg/);
  assert.match(rows['version-rows-win'][0], /DeepWork\.appx/);
  assert.match(rows['version-rows-mac'][1], /preview/);
  assert.match(rows['version-rows-mac'][2], /릴리스 노트/);
  assert.match(rows['version-rows-win'][1], /릴리스 노트/);
});

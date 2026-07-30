'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');

test('PowerShell TUN wrapper can be parsed', { skip: process.platform !== 'win32' }, () => {
  const wrapper = path.join(__dirname, '..', 'resources', 'tun-wrapper.ps1');
  const command = `[scriptblock]::Create((Get-Content -Raw -LiteralPath '${wrapper.replace(/'/g, "''")}')) | Out-Null`;
  const result = spawnSync('powershell.exe', ['-NoProfile', '-Command', command], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
});

test('PowerShell wrapper uses fixed signal actions and a secured core copy', () => {
  const script = fs.readFileSync(path.join(__dirname, '..', 'resources', 'tun-wrapper.ps1'), 'utf8');
  assert.match(script, /Start-Core/);
  assert.match(script, /icacls\.exe/);
  assert.match(script, /Test-Path -LiteralPath \$ReloadPath/);
  assert.match(script, /Test-Path -LiteralPath \$StopPath/);
  const service = fs.readFileSync(path.join(__dirname, '..', 'src', 'core', 'service.js'), 'utf8');
  assert.match(service, /-Verb RunAs/);
});

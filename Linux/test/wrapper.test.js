'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { spawn } = require('node:child_process');

test('TUN wrapper has valid POSIX shell syntax', () => {
  const wrapper = path.join(__dirname, '..', 'resources', 'tun-wrapper.sh');
  const result = spawnSync('/bin/sh', ['-n', wrapper], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
});

test('reload replaces the child and stop ends the wrapper', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'realitylink-linux-test-'));
  const fakeCore = path.join(directory, 'fake-core');
  fs.writeFileSync(fakeCore, '#!/bin/sh\nsleep 10\n', { mode: 0o700 });
  const paths = ['config.json', 'tun.log', 'tun.pid', 'tun.stop', 'tun.reload'].map((name) => path.join(directory, name));
  fs.writeFileSync(paths[0], '{}');
  const wrapper = path.join(__dirname, '..', 'resources', 'tun-wrapper.sh');
  const process = spawn('/bin/sh', [wrapper, fakeCore, ...paths], { stdio: 'ignore' });
  try {
    const first = await waitForPID(paths[2]);
    fs.writeFileSync(paths[4], 'reload\n');
    const second = await waitForPID(paths[2], first);
    assert.notEqual(first, second);
    assert.equal(process.exitCode, null);
    fs.writeFileSync(paths[3], 'stop\n');
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('wrapper did not stop')), 3000);
      process.once('exit', () => { clearTimeout(timeout); resolve(); });
    });
    assert.equal(process.exitCode, 0);
  } finally {
    if (process.exitCode === null) process.kill('SIGTERM');
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

async function waitForPID(file, previous = null) {
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    try {
      const value = fs.readFileSync(file, 'utf8').trim();
      if (value && value !== previous) return value;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error('timed out waiting for PID');
}

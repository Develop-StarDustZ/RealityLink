'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const version = '1.13.14';
const requested = process.env.TARGET_ARCH || process.arch;
const assets = {
  x64: { arch: 'amd64', hash: 'f580782c6dd10f7691c66cea1d7c421813c5fbf7e305d1ee7ce0c3a40d196341' },
  amd64: { arch: 'amd64', hash: 'f580782c6dd10f7691c66cea1d7c421813c5fbf7e305d1ee7ce0c3a40d196341' },
  arm64: { arch: 'arm64', hash: 'b22b597063ccb0e2e4fff53f677fe896e882ec5560d74d8db4fca5a0fed0a7b6' }
};
const asset = assets[requested];
if (!asset) throw new Error(`Unsupported Windows architecture: ${requested}`);

const project = path.join(__dirname, '..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'realitylink-windows-'));
const archive = `sing-box-${version}-windows-${asset.arch}.zip`;
const url = `https://github.com/SagerNet/sing-box/releases/download/v${version}/${archive}`;

(async () => {
  try {
    let data;
    let lastError;
    for (let attempt = 1; attempt <= 5; attempt += 1) {
      try {
        const response = await fetch(url, {
          redirect: 'follow',
          signal: AbortSignal.timeout(300000)
        });
        if (!response.ok) throw new Error(`Download failed: HTTP ${response.status}`);
        data = Buffer.from(await response.arrayBuffer());
        break;
      } catch (error) {
        lastError = error;
        if (attempt < 5) await new Promise((resolve) => setTimeout(resolve, 2000));
      }
    }
    if (!data) {
      const archivePath = path.join(temporary, archive);
      const fallback = spawnSync('curl.exe', ['--fail', '--location', '--retry', '5', '--connect-timeout', '20', '--max-time', '300', url, '--output', archivePath], { encoding: 'utf8' });
      if (fallback.status !== 0 || !fs.existsSync(archivePath)) throw lastError || new Error(fallback.stderr || 'Download failed');
      data = fs.readFileSync(archivePath);
    }
    const actual = crypto.createHash('sha256').update(data).digest('hex');
    if (actual !== asset.hash) throw new Error(`Checksum mismatch for ${archive}`);
    const archivePath = path.join(temporary, archive);
    fs.writeFileSync(archivePath, data);
    const extraction = spawnSync('tar', ['-xf', archivePath, '-C', temporary], { encoding: 'utf8' });
    if (extraction.status !== 0) throw new Error(extraction.stderr || 'Cannot extract sing-box archive');
    const source = path.join(temporary, `sing-box-${version}-windows-${asset.arch}`, 'sing-box.exe');
    fs.mkdirSync(path.join(project, 'vendor'), { recursive: true });
    fs.copyFileSync(source, path.join(project, 'vendor', 'sing-box.exe'));
    console.log(`Installed verified sing-box ${version} (${asset.arch})`);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
})().catch((error) => { console.error(error.message); process.exitCode = 1; });

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const directory = path.join(__dirname, '..', 'dist');
for (const name of fs.readdirSync(directory)) {
  if (!/^RealityLink-.*\.(?:exe|msi)$/.test(name)) continue;
  const hash = crypto.createHash('sha256').update(fs.readFileSync(path.join(directory, name))).digest('hex');
  fs.writeFileSync(path.join(directory, `${name}.sha256`), `${hash}  ${name}\n`);
}

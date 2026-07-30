'use strict';

const fs = require('node:fs');
const path = require('node:path');

class Store {
  constructor(directory) {
    this.directory = directory;
    fs.mkdirSync(this.directory, { recursive: true, mode: 0o700 });
    fs.chmodSync(this.directory, 0o700);
    this.file = path.join(directory, 'profiles.json');
    this.data = { profiles: [], subscriptions: [], selectedProfileID: null, corePath: '' };
    this.load();
  }

  load() {
    try {
      this.data = { ...this.data, ...JSON.parse(fs.readFileSync(this.file, 'utf8')) };
    } catch (error) {
      if (error.code !== 'ENOENT') console.error('Cannot read profile store:', error);
    }
  }

  save() {
    const temporary = `${this.file}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(this.data, null, 2), { mode: 0o600 });
    fs.renameSync(temporary, this.file);
    fs.chmodSync(this.file, 0o600);
  }
}

module.exports = { Store };

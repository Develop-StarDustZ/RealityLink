'use strict';
const fs = require('node:fs');
const path = require('node:path');
const development = path.join(__dirname, '..', '..', '..', 'Shared', 'electron', 'profile.js');
const packaged = path.join(process.resourcesPath || '', 'profile.js');
module.exports = require(fs.existsSync(development) ? development : packaged);

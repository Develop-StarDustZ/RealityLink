'use strict';
const fs=require('node:fs'),path=require('node:path');
const development=path.join(__dirname,'..','..','..','Shared','electron','config.js');
module.exports=require(fs.existsSync(development)?development:path.join(process.resourcesPath||'','config.js'));

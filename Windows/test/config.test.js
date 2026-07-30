'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { makeConfiguration } = require('../src/core/config');

const profile = {
  id: 'test', name: 'Test', server: 'vpn.example.com', port: 443,
  uuid: '123e4567-e89b-12d3-a456-426614174000', serverName: 'www.example.com',
  publicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', shortID: '0123456789abcdef',
  fingerprint: 'chrome', flow: 'xtls-rprx-vision'
};

test('creates a Windows TUN Reality configuration', () => {
  const config = makeConfiguration(profile);
  assert.equal(config.inbounds[0].type, 'tun');
  assert.equal(config.inbounds[0].auto_route, true);
  assert.equal(config.outbounds[0].tls.reality.public_key, profile.publicKey);
  assert.equal(config.route.final, 'proxy');
});

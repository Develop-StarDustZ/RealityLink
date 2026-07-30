'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { parseVLESS, validateProfile } = require('../src/core/profile');

test('parses a standard Reality URL', () => {
  const profile = parseVLESS('vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:8443?security=reality&sni=www.example.com&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0123456789abcdef&type=tcp#Tokyo%20Node');
  assert.equal(profile.name, 'Tokyo Node');
  assert.equal(profile.server, 'vpn.example.com');
  assert.equal(profile.port, 8443);
  assert.equal(profile.serverName, 'www.example.com');
});

test('parses the legacy Base64 URL without lowercasing its payload', () => {
  const endpoint = Buffer.from('none:123e4567-e89b-12d3-a456-426614174000@203.0.113.10:48143').toString('base64url');
  const profile = parseVLESS(`vless://${endpoint}?remarks=Legacy-Test&tls=1&peer=legacy.example.com&xtls=2&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=6f71`);
  assert.equal(profile.server, '203.0.113.10');
  assert.equal(profile.port, 48143);
  assert.equal(profile.flow, 'xtls-rprx-vision');
});

test('rejects unsupported transports', () => {
  assert.throws(() => parseVLESS('vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=reality&sni=x.example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&type=grpc'), /暂不支持/);
});

test('validates short IDs', () => {
  const profile = parseVLESS('vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=reality&sni=x.example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
  profile.shortID = 'xyz';
  assert.match(validateProfile(profile), /Short ID/);
});

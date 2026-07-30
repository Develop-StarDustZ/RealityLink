'use strict';

const crypto = require('node:crypto');
const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const first = (...values) => values.find(v => typeof v === 'string' && v.trim())?.trim() || '';
const truthy = value => ['1', 'true', 'yes'].includes(String(value || '').toLowerCase());
const b64 = value => Buffer.from(String(value).replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
const transport = value => ({ raw:'tcp', tcp:'tcp', ws:'ws', websocket:'ws', grpc:'grpc', h2:'http', http2:'http', http:'http' }[String(value || 'tcp').toLowerCase()]);

function baseProfile(protocol, values = {}) {
  return { id: crypto.randomUUID(), name:'New node', server:'', port:443, uuid:'', serverName:'', publicKey:'', shortID:'', fingerprint:'chrome', flow:'',
    proxyProtocol:protocol, password:'', encryption:'auto', alterID:0, obfuscation:'', obfuscationPassword:'', congestionControl:'cubic', udpRelayMode:'native',
    security:'none', transport:'tcp', transportPath:'', transportHost:'', serviceName:'', allowInsecure:false, alpn:'', subscriptionID:null, ...values };
}

function query(url) { return Object.fromEntries([...url.searchParams].map(([k,v]) => [k.toLowerCase(), v])); }
function endpoint(url, protocol) {
  if (!url.hostname) throw new Error(`${protocol} 链接缺少服务器地址`);
  return { server:url.hostname.replace(/^\[|\]$/g,''), port:Number(url.port || 443) };
}
function nameOf(url, fallback) { try { return first(decodeURIComponent(url.hash.slice(1)), fallback); } catch { return fallback; } }

function parseVLESS(raw) {
  const url = new URL(raw); const q=query(url); let ep; let uuid=decodeURIComponent(url.username || '');
  if (UUID.test(uuid)) ep=endpoint(url,'VLESS'); else {
    const authority=raw.slice(8).split(/[/?#]/)[0]; const match=b64(authority).match(/^(?:none:)?([0-9a-f-]{36})@(.+):(\d+)$/i);
    if(!match) throw new Error('旧格式 VLESS 地址无效'); uuid=match[1]; ep={server:match[2],port:Number(match[3])};
  }
  const reality=q.security==='reality'||(q.xtls==='2'&&q.pbk); const tls=q.security==='tls'||(!reality&&q.tls==='1');
  if(!reality&&!tls) throw new Error('VLESS 仅支持 Reality 或 TLS'); const net=transport(q.type); if(!net) throw new Error(`不支持 VLESS ${q.type} 传输`); if(reality&&net!=='tcp') throw new Error('暂不支持 Reality 使用非 TCP/raw 传输');
  return checked(baseProfile('vless',{name:nameOf(url,first(q.remarks,ep.server)),server:ep.server,port:ep.port,uuid,serverName:first(q.sni,q.peer,tls?ep.server:''),publicKey:q.pbk||'',shortID:q.sid||'',fingerprint:q.fp||'chrome',flow:net==='tcp'?(q.flow||(q.xtls==='2'?'xtls-rprx-vision':'')):'',security:reality?'reality':'tls',transport:net,transportPath:net==='grpc'?'':q.path||'',transportHost:first(q.host,q.authority),serviceName:net==='grpc'?first(q.servicename,q.path):'',allowInsecure:truthy(first(q.allowinsecure,q.insecure)),alpn:q.alpn||''}));
}
function parseVMess(raw) {
  let data; try { data=JSON.parse(b64(raw.slice(8).split('#')[0])); } catch { throw new Error('VMess Base64 JSON 无效'); }
  const net=transport(data.net); if(!net) throw new Error(`不支持 VMess ${data.net} 传输`); const tls=['tls','1','true'].includes(String(data.tls||'').toLowerCase());
  return checked(baseProfile('vmess',{name:first(data.ps,data.add),server:String(data.add||''),port:Number(data.port||443),uuid:String(data.id||''),serverName:first(data.sni,tls?data.add:''),fingerprint:data.fp||'chrome',encryption:data.scy||'auto',alterID:Number(data.aid||0),security:tls?'tls':'none',transport:net,transportPath:net==='grpc'?'':String(data.path||''),transportHost:String(data.host||''),serviceName:net==='grpc'?first(data.path,data.serviceName):'',allowInsecure:truthy(data.allowInsecure),alpn:String(data.alpn||'')}));
}
function parseTrojan(raw) {
  const url=new URL(raw),q=query(url),ep=endpoint(url,'Trojan'); if(q.security&&q.security!=='tls') throw new Error(`不支持 Trojan security=${q.security}`); const net=transport(q.type); if(!net) throw new Error(`不支持 Trojan ${q.type} 传输`);
  return checked(baseProfile('trojan',{name:nameOf(url,ep.server),...ep,password:decodeURIComponent(url.username)+(url.password?`:${decodeURIComponent(url.password)}`:''),serverName:first(q.sni,q.peer,ep.server),fingerprint:q.fp||'chrome',security:'tls',transport:net,transportPath:net==='grpc'?'':q.path||'',transportHost:first(q.host,q.authority),serviceName:net==='grpc'?first(q.servicename,q.path):'',allowInsecure:truthy(first(q.allowinsecure,q.insecure)),alpn:q.alpn||''}));
}
function parseSS(raw) {
  const source=raw.slice(5), fragment=source.includes('#')?decodeURIComponent(source.split('#').slice(1).join('#')):''; let body=source.split('#')[0];
  if(body.includes('?plugin=')) throw new Error('暂不支持 Shadowsocks SIP003 插件'); body=body.split('?')[0]; if(!body.includes('@')) body=b64(body);
  let [credentials,address]=[body.slice(0,body.lastIndexOf('@')),body.slice(body.lastIndexOf('@')+1)]; if(!address) throw new Error('Shadowsocks 链接无效');
  try { const decoded=b64(credentials); if(decoded.includes(':')) credentials=decoded; } catch {}
  const split=credentials.indexOf(':'); if(split<1) throw new Error('Shadowsocks 认证信息无效'); const url=new URL(`ss://user@${address}`); const ep=endpoint(url,'Shadowsocks');
  return checked(baseProfile('shadowsocks',{name:first(fragment,ep.server),...ep,encryption:credentials.slice(0,split),password:decodeURIComponent(credentials.slice(split+1)),security:'none'}));
}
function parseHY2(raw) {
  const url=new URL(raw),q=query(url),ep=endpoint(url,'Hysteria2'),obfs=q.obfs||''; if(obfs&&obfs!=='salamander') throw new Error(`不支持 Hysteria2 obfs=${obfs}`);
  return checked(baseProfile('hysteria2',{name:nameOf(url,ep.server),...ep,password:decodeURIComponent(url.username)+(url.password?`:${decodeURIComponent(url.password)}`:''),serverName:first(q.sni,ep.server),fingerprint:q.fp||'chrome',security:'tls',obfuscation:obfs,obfuscationPassword:first(q['obfs-password'],q.obfspassword),allowInsecure:truthy(first(q.insecure,q.allowinsecure)),alpn:q.alpn||'h3'}));
}
function parseTUIC(raw) {
  const url=new URL(raw),q=query(url),ep=endpoint(url,'TUIC'); const cc=first(q.congestion_control,q['congestion-control'],'cubic'),relay=first(q.udp_relay_mode,q['udp-relay-mode'],'native'); if(!['cubic','new_reno','bbr'].includes(cc)||!['native','quic'].includes(relay)) throw new Error('TUIC 拥塞控制或 UDP 模式无效');
  return checked(baseProfile('tuic',{name:nameOf(url,ep.server),...ep,uuid:decodeURIComponent(url.username),password:decodeURIComponent(url.password),serverName:first(q.sni,ep.server),fingerprint:q.fp||'chrome',security:'tls',congestionControl:cc,udpRelayMode:relay,allowInsecure:truthy(first(q.allow_insecure,q.allowinsecure,q.insecure)),alpn:q.alpn||'h3'}));
}
function parseProxy(raw) { const value=String(raw||'').trim(),scheme=value.split(':')[0].toLowerCase(); if(scheme==='vless')return parseVLESS(value);if(scheme==='vmess')return parseVMess(value);if(scheme==='trojan')return parseTrojan(value);if(scheme==='ss')return parseSS(value);if(['hysteria2','hy2'].includes(scheme))return parseHY2(value);if(scheme==='tuic')return parseTUIC(value);throw new Error('不支持这个节点协议'); }
function validateProfile(p) { if(!p.name?.trim())return'请填写节点名称';if(!p.server?.trim())return'请填写服务器地址';if(!Number.isInteger(Number(p.port))||p.port<1||p.port>65535)return'端口必须在 1 到 65535 之间';if(['vless','vmess','tuic'].includes(p.proxyProtocol)&&!UUID.test(p.uuid||''))return'UUID 格式不正确';if(['vless','vmess','trojan','hysteria2','tuic'].includes(p.proxyProtocol)&&p.security!=='none'&&!p.serverName?.trim())return'请填写 TLS SNI';if(p.proxyProtocol==='vless'&&p.security==='reality'&&!/^[A-Za-z0-9_-]{40,}$/.test(p.publicKey||''))return'Reality 公钥格式不正确';if(p.proxyProtocol==='vless'&&p.security==='reality'&&!/^(?:[0-9a-fA-F]{2}){0,8}$/.test(p.shortID||''))return'Reality Short ID 必须是最多 16 位十六进制字符';if(['trojan','shadowsocks','hysteria2','tuic'].includes(p.proxyProtocol)&&!p.password)return'请填写密码';if(p.proxyProtocol==='shadowsocks'&&!p.encryption)return'请选择 Shadowsocks 加密方式';return null; }
function checked(profile){const error=validateProfile(profile);if(error)throw new Error(error);return profile;}
function normalizeProfile(input){return baseProfile(input.proxyProtocol||'vless',{...input,port:Number(input.port),alterID:Number(input.alterID||0),allowInsecure:Boolean(input.allowInsecure)});}
module.exports={parseProxy,parseVLESS,validateProfile,normalizeProfile,baseProfile};

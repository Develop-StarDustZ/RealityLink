'use strict';

const path = require('node:path');
const { app, BrowserWindow, ipcMain, shell } = require('electron');
const net = require('node:net');
const crypto = require('node:crypto');
const { Store } = require('./core/store');
const { TunnelService } = require('./core/service');
const { parseProxy, validateProfile, normalizeProfile } = require('./core/profile');
const { fetchSubscription, groupName } = require('./core/subscription');

let window;
let store;
let tunnel;
let quitting = false;

function send(channel, value) {
  if (window && !window.isDestroyed()) window.webContents.send(channel, value);
}

function createWindow() {
  window = new BrowserWindow({
    width: 1060, height: 720, minWidth: 840, minHeight: 580,
    title: 'RealityLink', backgroundColor: '#0b1020',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true, nodeIntegration: false, sandbox: true
    }
  });
  window.setMenuBarVisibility(false);
  window.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
}

app.whenReady().then(() => {
  const userData = app.getPath('userData');
  store = new Store(userData);
  tunnel = new TunnelService({
    runtimeDirectory: path.join(userData, 'runtime'),
    resourcesPath: process.resourcesPath,
    developmentRoot: path.join(__dirname, '..', '..'),
    customCorePath: store.data.corePath
  });
  tunnel.on('status', (value) => send('connection:status', value));
  tunnel.on('logs', (value) => send('connection:logs', value));
  tunnel.recover();
  createWindow();
});

ipcMain.handle('app:initial-state', () => ({ ...store.data, connection: tunnel.snapshot() }));
function syncSubscription(subscription, incoming, adoptLocal=false) {
  const key=p=>[p.proxyProtocol,p.server.toLowerCase(),p.port,p.uuid||p.password].join('|');
  const old=new Map(store.data.profiles.filter(p=>p.subscriptionID===subscription.id).map(p=>[key(p),p]));
  const local=new Map(store.data.profiles.filter(p=>!p.subscriptionID).map(p=>[key(p),p]));
  const replacements=incoming.map(p=>({...p,id:old.get(key(p))?.id||(adoptLocal?local.get(key(p))?.id:null)||p.id,subscriptionID:subscription.id}));
  const ids=new Set(replacements.map(p=>p.id));
  store.data.profiles=store.data.profiles.filter(p=>p.subscriptionID!==subscription.id&&!(adoptLocal&&!p.subscriptionID&&ids.has(p.id))).concat(replacements);
  if(!store.data.profiles.some(p=>p.id===store.data.selectedProfileID))store.data.selectedProfileID=replacements[0]?.id||store.data.profiles[0]?.id||null;
}
ipcMain.handle('profiles:import', async (_event, input) => {
  const raw=String(input||'').trim();
  if(/^(sub|https?):\/\//i.test(raw)){
    const incoming=await fetchSubscription(raw);let subscription=store.data.subscriptions.find(s=>s.sourceURL===raw);
    if(!subscription){subscription={id:crypto.randomUUID(),name:groupName(raw),sourceURL:raw,lastUpdated:new Date().toISOString()};store.data.subscriptions.push(subscription);syncSubscription(subscription,incoming,true);}else{subscription.lastUpdated=new Date().toISOString();syncSubscription(subscription,incoming);}
  }else{const profile=parseProxy(raw);store.data.profiles.push(profile);store.data.selectedProfileID=profile.id;}
  store.save();
  return { ...store.data };
});
ipcMain.handle('profiles:save', (_event, input) => {
  const profile = normalizeProfile({ ...input, id: input.id || crypto.randomUUID() });
  const validation = validateProfile(profile);
  if (validation) throw new Error(validation);
  const index = store.data.profiles.findIndex((item) => item.id === profile.id);
  if (index >= 0) store.data.profiles[index] = profile;
  else store.data.profiles.push(profile);
  store.data.selectedProfileID = profile.id;
  store.save();
  return { ...store.data };
});
ipcMain.handle('subscriptions:renew', async (_event,id)=>{const subscription=store.data.subscriptions.find(s=>s.id===id);if(!subscription)throw new Error('找不到订阅');syncSubscription(subscription,await fetchSubscription(subscription.sourceURL));subscription.lastUpdated=new Date().toISOString();store.save();return{...store.data};});
ipcMain.handle('subscriptions:delete',(_event,id)=>{const ids=new Set(store.data.profiles.filter(p=>p.subscriptionID===id).map(p=>p.id));store.data.profiles=store.data.profiles.filter(p=>p.subscriptionID!==id);store.data.subscriptions=store.data.subscriptions.filter(s=>s.id!==id);if(ids.has(store.data.selectedProfileID))store.data.selectedProfileID=store.data.profiles[0]?.id||null;store.save();return{...store.data};});
ipcMain.handle('profiles:latency',(_event,ids)=>Promise.all((ids||store.data.profiles.map(p=>p.id)).map(id=>new Promise(resolve=>{const p=store.data.profiles.find(x=>x.id===id);if(!p)return resolve([id,null]);const started=Date.now(),socket=net.createConnection({host:p.server,port:Number(p.port)});const done=value=>{socket.destroy();resolve([id,value]);};socket.setTimeout(5000,()=>done(null));socket.once('connect',()=>done(Math.max(1,Date.now()-started)));socket.once('error',()=>done(null));}))).then(Object.fromEntries));
ipcMain.handle('app:open-store',()=>shell.openExternal('https://node.stardustz.com'));
ipcMain.handle('profiles:delete', (_event, id) => {
  if (['connecting', 'connected', 'switching'].includes(tunnel.state)) throw new Error('请先断开连接');
  store.data.profiles = store.data.profiles.filter((item) => item.id !== id);
  if (store.data.selectedProfileID === id) store.data.selectedProfileID = store.data.profiles[0]?.id || null;
  store.save();
  return { ...store.data };
});
ipcMain.handle('profiles:select', (_event, id) => {
  store.data.selectedProfileID = id;
  store.save();
  return true;
});
ipcMain.handle('settings:core-path', (_event, value) => {
  store.data.corePath = String(value || '').trim();
  store.save();
  tunnel.setCorePath(store.data.corePath);
  return true;
});
ipcMain.handle('connection:start', (_event, id) => {
  const profile = store.data.profiles.find((item) => item.id === id);
  if (!profile) throw new Error('找不到所选节点');
  tunnel.start(profile);
  return true;
});
ipcMain.handle('connection:switch', (_event, id) => {
  const profile = store.data.profiles.find((item) => item.id === id);
  if (!profile) throw new Error('找不到所选节点');
  tunnel.switchProfile(profile);
  return true;
});
ipcMain.handle('connection:stop', () => { tunnel.stop(); return true; });

app.on('before-quit', (event) => {
  if (!quitting && tunnel && ['connecting', 'connected', 'switching'].includes(tunnel.state)) {
    event.preventDefault();
    quitting = true;
    tunnel.stop();
    const finish = () => { tunnel.off('status', watcher); app.quit(); };
    const watcher = ({ state }) => { if (state === 'disconnected' || state === 'failed') finish(); };
    tunnel.on('status', watcher);
    setTimeout(finish, 5000);
  }
});

app.on('window-all-closed', () => app.quit());

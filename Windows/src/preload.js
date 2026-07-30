'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('realityLink', {
  getInitialState: () => ipcRenderer.invoke('app:initial-state'),
  importProfile: (url) => ipcRenderer.invoke('profiles:import', url),
  renewSubscription: (id) => ipcRenderer.invoke('subscriptions:renew', id),
  deleteSubscription: (id) => ipcRenderer.invoke('subscriptions:delete', id),
  testLatency: (ids) => ipcRenderer.invoke('profiles:latency', ids),
  openStore: () => ipcRenderer.invoke('app:open-store'),
  saveProfile: (profile) => ipcRenderer.invoke('profiles:save', profile),
  deleteProfile: (id) => ipcRenderer.invoke('profiles:delete', id),
  selectProfile: (id) => ipcRenderer.invoke('profiles:select', id),
  saveCorePath: (value) => ipcRenderer.invoke('settings:core-path', value),
  start: (id) => ipcRenderer.invoke('connection:start', id),
  switchProfile: (id) => ipcRenderer.invoke('connection:switch', id),
  stop: () => ipcRenderer.invoke('connection:stop'),
  onStatus: (callback) => ipcRenderer.on('connection:status', (_event, value) => callback(value)),
  onLogs: (callback) => ipcRenderer.on('connection:logs', (_event, value) => callback(value))
});

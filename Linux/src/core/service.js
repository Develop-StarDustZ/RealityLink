'use strict';

const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { makeConfiguration } = require('./config');

class TunnelService extends EventEmitter {
  constructor({ runtimeDirectory, resourcesPath, developmentRoot, customCorePath = '' }) {
    super();
    this.runtimeDirectory = runtimeDirectory;
    this.resourcesPath = resourcesPath;
    this.developmentRoot = developmentRoot;
    this.customCorePath = customCorePath;
    this.state = 'disconnected';
    this.profile = null;
    this.child = null;
    this.managedPID = null;
    this.switchFromPID = null;
    this.pendingProfile = null;
    this.timer = null;
    this.logOffset = 0;
    this.paths = {
      config: path.join(runtimeDirectory, 'runtime.json'),
      nextConfig: path.join(runtimeDirectory, 'runtime-next.json'),
      log: path.join(runtimeDirectory, 'tun.log'),
      pid: path.join(runtimeDirectory, 'tun.pid'),
      stop: path.join(runtimeDirectory, 'tun.stop'),
      reload: path.join(runtimeDirectory, 'tun.reload')
    };
  }

  snapshot() {
    return { state: this.state, profile: this.profile, logs: this.readAllLogs() };
  }

  setCorePath(value) { this.customCorePath = value || ''; }

  locateCore() {
    const candidates = [
      this.customCorePath,
      process.env.REALITYLINK_SING_BOX,
      path.join(this.resourcesPath, 'sing-box'),
      path.join(this.developmentRoot, 'vendor', 'sing-box'),
      '/usr/bin/sing-box',
      '/usr/local/bin/sing-box'
    ].filter(Boolean);
    const found = candidates.find((candidate) => {
      try { fs.accessSync(candidate, fs.constants.X_OK); return true; } catch { return false; }
    });
    if (!found) throw new Error('找不到 sing-box，请运行 npm run prepare-core 或在设置中指定路径');
    return found;
  }

  wrapperPath() {
    const packaged = path.join(this.resourcesPath, 'tun-wrapper.sh');
    const development = path.join(this.developmentRoot, 'resources', 'tun-wrapper.sh');
    return fs.existsSync(packaged) ? packaged : development;
  }

  writeConfiguration(profile, destination) {
    fs.mkdirSync(this.runtimeDirectory, { recursive: true, mode: 0o700 });
    const temporary = `${destination}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(makeConfiguration(profile), null, 2)}\n`, { mode: 0o600 });
    fs.renameSync(temporary, destination);
    fs.chmodSync(destination, 0o600);
  }

  validate(core, configuration) {
    const result = spawnSync(core, ['check', '-c', configuration], { encoding: 'utf8' });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error((result.stderr || result.stdout || 'sing-box 拒绝了配置').trim());
  }

  start(profile) {
    if (!['disconnected', 'failed'].includes(this.state)) return;
    try {
      const core = this.locateCore();
      this.state = 'connecting';
      this.profile = profile;
      this.emitStatus();
      this.writeConfiguration(profile, this.paths.config);
      this.validate(core, this.paths.config);
      fs.writeFileSync(this.paths.log, '', { mode: 0o600 });
      fs.writeFileSync(this.paths.pid, '', { mode: 0o600 });
      for (const signal of [this.paths.stop, this.paths.reload]) fs.rmSync(signal, { force: true });
      this.logOffset = 0;

      this.child = spawn('pkexec', ['/bin/sh', this.wrapperPath(), core, this.paths.config,
        this.paths.log, this.paths.pid, this.paths.stop, this.paths.reload], { stdio: ['ignore', 'pipe', 'pipe'] });
      let authorizationOutput = '';
      this.child.stdout.on('data', (data) => { authorizationOutput += data.toString(); });
      this.child.stderr.on('data', (data) => { authorizationOutput += data.toString(); });
      this.child.on('error', (error) => this.fail(error.message));
      this.child.on('exit', (code) => {
        this.child = null;
        this.readNewLogs();
        if (this.state === 'disconnecting') this.finishStop();
        else if (!['disconnected', 'failed'].includes(this.state)) {
          this.fail(this.lastLog() || authorizationOutput.trim() || `TUN 控制进程已退出（${code}）`);
        }
      });
      this.startMonitor();
    } catch (error) {
      this.fail(error.message);
    }
  }

  switchProfile(profile) {
    if (this.state !== 'connected' || profile.id === this.profile?.id) return;
    try {
      const core = this.locateCore();
      this.writeConfiguration(profile, this.paths.nextConfig);
      this.validate(core, this.paths.nextConfig);
      fs.renameSync(this.paths.nextConfig, this.paths.config);
      this.pendingProfile = profile;
      this.switchFromPID = this.managedPID;
      this.state = 'switching';
      fs.writeFileSync(this.paths.reload, 'reload\n', { mode: 0o600 });
      this.emitStatus();
    } catch (error) {
      fs.rmSync(this.paths.nextConfig, { force: true });
      this.appendLog(`切换失败：${error.message}`);
    }
  }

  stop() {
    if (!['connecting', 'connected', 'switching'].includes(this.state)) return;
    this.state = 'disconnecting';
    this.emitStatus();
    try { fs.writeFileSync(this.paths.stop, 'stop\n', { mode: 0o600 }); }
    catch (error) { this.fail(`无法发送停止信号：${error.message}`); }
  }

  recover() {
    const pid = this.readPID();
    if (pid && this.isAlive(pid) && this.isManagedProcess(pid)) {
      this.managedPID = pid;
      this.profile = { id: null, name: '上次 TUN 会话' };
      this.state = 'connected';
      this.startMonitor();
      this.emitStatus();
    }
  }

  startMonitor() {
    clearInterval(this.timer);
    this.timer = setInterval(() => this.poll(), 500);
  }

  poll() {
    this.readNewLogs();
    const pid = this.readPID();
    if (this.state === 'connecting' && pid && this.isAlive(pid)) {
      this.managedPID = pid;
      this.state = 'connected';
      this.appendLog('全局 TUN 已启用');
      this.emitStatus();
    } else if (this.state === 'switching' && pid && pid !== this.switchFromPID && this.isAlive(pid)) {
      this.managedPID = pid;
      this.profile = this.pendingProfile;
      this.pendingProfile = null;
      this.switchFromPID = null;
      this.state = 'connected';
      this.appendLog(`已切换到 ${this.profile.name}`);
      this.emitStatus();
    } else if (this.state === 'connected' && this.managedPID && !this.isAlive(this.managedPID)) {
      this.fail(this.lastLog() || 'sing-box 意外退出');
    } else if (this.state === 'disconnecting' && this.managedPID && !this.isAlive(this.managedPID)) {
      this.finishStop();
    }
  }

  readPID() {
    try {
      const value = Number(fs.readFileSync(this.paths.pid, 'utf8').trim());
      return Number.isInteger(value) && value > 1 ? value : null;
    } catch { return null; }
  }

  isAlive(pid) {
    try { process.kill(pid, 0); return true; }
    catch (error) { return error.code === 'EPERM'; }
  }

  isManagedProcess(pid) {
    try {
      const command = fs.readFileSync(`/proc/${pid}/cmdline`, 'utf8');
      return command.includes(this.paths.config)
        && (command.includes('realitylink-core.') || command.includes('sing-box'));
    } catch { return false; }
  }

  readAllLogs() {
    try {
      const data = fs.readFileSync(this.paths.log);
      const tail = data.subarray(Math.max(0, data.length - 200000)).toString('utf8');
      return tail.split(/\r?\n/).filter(Boolean).slice(-1000);
    } catch { return []; }
  }

  readNewLogs() {
    let data;
    try { data = fs.readFileSync(this.paths.log); } catch { return; }
    if (data.length < this.logOffset) this.logOffset = 0;
    const text = data.subarray(this.logOffset).toString('utf8');
    this.logOffset = data.length;
    if (text) this.emit('logs', text.split(/\r?\n/).filter(Boolean));
  }

  appendLog(line) {
    fs.mkdirSync(this.runtimeDirectory, { recursive: true, mode: 0o700 });
    fs.appendFileSync(this.paths.log, `${line}\n`, { mode: 0o600 });
    this.emit('logs', [line]);
  }

  lastLog() { return this.readAllLogs().at(-1); }
  emitStatus() { this.emit('status', { state: this.state, profile: this.profile }); }

  finishStop() {
    clearInterval(this.timer);
    this.timer = null;
    this.managedPID = null;
    this.pendingProfile = null;
    this.profile = null;
    this.state = 'disconnected';
    for (const signal of [this.paths.stop, this.paths.reload, this.paths.pid]) fs.rmSync(signal, { force: true });
    this.emitStatus();
  }

  fail(message) {
    clearInterval(this.timer);
    this.timer = null;
    this.state = 'failed';
    this.appendLog(`错误：${message}`);
    this.emitStatus();
  }
}

module.exports = { TunnelService };

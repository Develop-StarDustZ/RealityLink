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
    this.offsets = { stdout: 0, stderr: 0 };
    this.localLogs = [];
    this.paths = {
      config: path.join(runtimeDirectory, 'runtime.json'),
      nextConfig: path.join(runtimeDirectory, 'runtime-next.json'),
      stdout: path.join(runtimeDirectory, 'tun.log'),
      stderr: path.join(runtimeDirectory, 'tun-error.log'),
      pid: path.join(runtimeDirectory, 'tun.pid'),
      stop: path.join(runtimeDirectory, 'tun.stop'),
      reload: path.join(runtimeDirectory, 'tun.reload')
    };
  }

  snapshot() { return { state: this.state, profile: this.profile, logs: this.readAllLogs() }; }
  setCorePath(value) { this.customCorePath = value || ''; }

  locateCore() {
    const candidates = [
      this.customCorePath,
      process.env.REALITYLINK_SING_BOX,
      path.join(this.resourcesPath, 'sing-box.exe'),
      path.join(this.developmentRoot, 'vendor', 'sing-box.exe'),
      'C:\\Program Files\\sing-box\\sing-box.exe'
    ].filter(Boolean);
    const found = candidates.find((candidate) => {
      try { fs.accessSync(candidate, fs.constants.X_OK); return true; } catch { return false; }
    });
    if (!found) throw new Error('找不到 sing-box.exe，请运行 npm run prepare-core 或在设置中指定路径');
    return found;
  }

  wrapperPath() {
    const packaged = path.join(this.resourcesPath, 'tun-wrapper.ps1');
    const development = path.join(this.developmentRoot, 'resources', 'tun-wrapper.ps1');
    return fs.existsSync(packaged) ? packaged : development;
  }

  writeConfiguration(profile, destination) {
    fs.mkdirSync(this.runtimeDirectory, { recursive: true, mode: 0o700 });
    const temporary = `${destination}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(makeConfiguration(profile), null, 2)}\n`, { mode: 0o600 });
    fs.rmSync(destination, { force: true });
    fs.renameSync(temporary, destination);
  }

  validate(core, configuration) {
    const result = spawnSync(core, ['check', '-c', configuration], { encoding: 'utf8', windowsHide: true });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error((result.stderr || result.stdout || 'sing-box 拒绝了配置').trim());
  }

  elevatedCommand(core) {
    const quote = (value) => `'${String(value).replace(/'/g, "''")}'`;
    const script = `& ${quote(this.wrapperPath())} -CorePath ${quote(core)} -ConfigPath ${quote(this.paths.config)} -StdoutPath ${quote(this.paths.stdout)} -StderrPath ${quote(this.paths.stderr)} -PIDPath ${quote(this.paths.pid)} -StopPath ${quote(this.paths.stop)} -ReloadPath ${quote(this.paths.reload)}; exit $LASTEXITCODE`;
    const encoded = Buffer.from(script, 'utf16le').toString('base64');
    return `$p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand','${encoded}') -PassThru -Wait; exit $p.ExitCode`;
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
      fs.mkdirSync(this.runtimeDirectory, { recursive: true, mode: 0o700 });
      for (const file of [this.paths.stdout, this.paths.stderr, this.paths.pid]) fs.writeFileSync(file, '', { mode: 0o600 });
      for (const signal of [this.paths.stop, this.paths.reload]) fs.rmSync(signal, { force: true });
      this.offsets = { stdout: 0, stderr: 0 };

      this.child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', this.elevatedCommand(core)],
        { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
      let authorizationOutput = '';
      this.child.stdout.on('data', (data) => { authorizationOutput += data.toString(); });
      this.child.stderr.on('data', (data) => { authorizationOutput += data.toString(); });
      this.child.on('error', (error) => this.fail(error.message));
      this.child.on('exit', (code) => {
        this.child = null;
        this.readNewLogs();
        if (this.state === 'disconnecting') this.finishStop();
        else if (!['disconnected', 'failed'].includes(this.state)) {
          this.fail(this.lastLog() || authorizationOutput.trim() || `管理员控制进程已退出（${code}）`);
        }
      });
      this.startMonitor();
    } catch (error) { this.fail(error.message); }
  }

  switchProfile(profile) {
    if (this.state !== 'connected' || profile.id === this.profile?.id) return;
    try {
      const core = this.locateCore();
      this.writeConfiguration(profile, this.paths.nextConfig);
      this.validate(core, this.paths.nextConfig);
      fs.rmSync(this.paths.config, { force: true });
      fs.renameSync(this.paths.nextConfig, this.paths.config);
      this.pendingProfile = profile;
      this.switchFromPID = this.managedPID;
      this.state = 'switching';
      fs.writeFileSync(this.paths.reload, 'reload\r\n', { mode: 0o600 });
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
    try { fs.writeFileSync(this.paths.stop, 'stop\r\n', { mode: 0o600 }); }
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
    } else if (this.state === 'connected' && pid && pid !== this.managedPID && this.isAlive(pid)) {
      this.managedPID = pid;
      this.offsets = { stdout: 0, stderr: 0 };
      this.appendLog('日志已轮转，TUN 内核已继续运行');
    } else if (this.state === 'switching' && pid && pid !== this.switchFromPID && this.isAlive(pid)) {
      this.managedPID = pid;
      this.profile = this.pendingProfile;
      this.pendingProfile = null;
      this.switchFromPID = null;
      this.offsets = { stdout: 0, stderr: 0 };
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
      return Number.isInteger(value) && value > 4 ? value : null;
    } catch { return null; }
  }

  isAlive(pid) {
    const result = spawnSync('tasklist.exe', ['/FI', `PID eq ${pid}`, '/FO', 'CSV', '/NH'], { encoding: 'utf8', windowsHide: true });
    return result.status === 0 && result.stdout.includes(`"${pid}"`);
  }

  isManagedProcess(pid) {
    const command = `(Get-CimInstance Win32_Process -Filter \"ProcessId = ${pid}\").CommandLine`;
    const result = spawnSync('powershell.exe', ['-NoProfile', '-Command', command], { encoding: 'utf8', windowsHide: true });
    return result.status === 0 && result.stdout.includes(this.paths.config);
  }

  readAllLogs() {
    const fileLogs = [this.paths.stdout, this.paths.stderr].flatMap((file) => {
      try {
        const data = fs.readFileSync(file);
        return data.subarray(Math.max(0, data.length - 100000)).toString('utf8').split(/\r?\n/).filter(Boolean);
      } catch { return []; }
    });
    return [...fileLogs, ...this.localLogs].slice(-1000);
  }

  readNewLogs() {
    for (const [kind, file] of [['stdout', this.paths.stdout], ['stderr', this.paths.stderr]]) {
      let data;
      try { data = fs.readFileSync(file); } catch { continue; }
      if (data.length < this.offsets[kind]) this.offsets[kind] = 0;
      const text = data.subarray(this.offsets[kind]).toString('utf8');
      this.offsets[kind] = data.length;
      if (text) this.emit('logs', text.split(/\r?\n/).filter(Boolean));
    }
  }

  appendLog(line) {
    this.localLogs.push(line);
    this.localLogs = this.localLogs.slice(-200);
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

// An owned fresh browser loads the SDK's real DevTools frontend. A correlated
// getVM exchange on that frontend's socket proves attachment to the original app.
// No profile, URL, PID, page text or network payload is a public result.
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import * as fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

export class Refused extends Error {
  constructor(code) { super(code); this.code = code; }
}
function need(value, code) { if (!value) throw new Refused(code); }
function plainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function serviceKey(raw) {
  need(typeof raw === 'string' && raw.length <= 4096 && /^[\x21-\x7e]+$/.test(raw), 'ENDPOINT_REFUSED');
  let value;
  try { value = new URL(raw); } catch { throw new Refused('ENDPOINT_REFUSED'); }
  need(value.protocol === 'ws:' && value.hostname === '127.0.0.1' &&
    value.port !== '' && +value.port >= 1024 && +value.port <= 65535 &&
    value.username === '' && value.password === '' && value.search === '' && value.hash === '', 'ENDPOINT_REFUSED');
  let decoded;
  try { decoded = decodeURIComponent(value.pathname); } catch { throw new Refused('ENDPOINT_REFUSED'); }
  need(/^\/[A-Za-z0-9_=-]{1,256}\/ws$/.test(decoded), 'ENDPOINT_REFUSED');
  return `${value.port}${decoded}`;
}

export function frontendAddress(raw, service) {
  const key = serviceKey(service);
  need(typeof raw === 'string' && raw.length <= 4096 && /^[\x21-\x7e]+$/.test(raw), 'ENDPOINT_REFUSED');
  let value;
  try { value = new URL(raw); } catch { throw new Refused('ENDPOINT_REFUSED'); }
  need(value.protocol === 'http:' && value.hostname === '127.0.0.1' &&
    +value.port >= 1024 && +value.port <= 65535 && !value.username && !value.password, 'ENDPOINT_REFUSED');
  const targets = [...value.searchParams.getAll('uri'),
    ...new URLSearchParams(value.hash.split('?').slice(1).join('?')).getAll('uri')];
  need(targets.length === 1, 'ENDPOINT_REFUSED');
  let target;
  try { target = new URL(targets[0]); } catch { throw new Refused('ENDPOINT_REFUSED'); }
  if (target.protocol === 'http:') {
    target.protocol = 'ws:';
    target.pathname = `${target.pathname.replace(/\/$/, '')}/ws`;
  }
  need(serviceKey(target.toString()) === key, 'ENDPOINT_REFUSED');
  return raw;
}

export function frontendPageExpression(raw) {
  let address;
  try { address = new URL(raw); } catch { throw new Refused('ENDPOINT_REFUSED'); }
  need(address.protocol === 'http:' && address.hostname === '127.0.0.1' &&
    +address.port >= 1024 && +address.port <= 65535 && !address.username && !address.password,
  'ENDPOINT_REFUSED');
  // DevTools can change its document title to describe the connected app.
  // Identity comes from the SDK server origin and the actual frontend VM reply.
  return "({ready: document.readyState === 'complete', devtools: document.title.toLowerCase().includes('devtools'), sourceMatched: location.origin === " +
    JSON.stringify(address.origin) + '})';
}

export class FrontendExchange {
  constructor(service, pid) {
    need(Number.isSafeInteger(pid) && pid > 0 && pid < 0x100000000, 'PID_REFUSED');
    this.service = serviceKey(service);
    this.pid = pid;
    this.socket = null;
    this.requests = new Set();
    this.attached = false;
    this.closed = false;
    this.held = false;
    this.getVmRequests = 0;
    this.getVmReplies = 0;
    this.otherSockets = 0;
  }
  event(method, params) {
    need(!this.held, 'REQUEST_REFUSED');
    try { this._event(method, params); } catch (error) {
      this.held = true;
      this.attached = false;
      throw error;
    }
  }
  _event(method, params) {
    if (!plainObject(params)) return;
    if (method === 'Network.webSocketCreated') {
      let matches = false;
      try { matches = serviceKey(params.url) === this.service; } catch { /* another socket */ }
      if (matches) {
        need(this.socket === null && typeof params.requestId === 'string', 'SOCKET_REPLACED');
        this.socket = params.requestId;
      } else {
        need(this.otherSockets < 64, 'FRAME_REFUSED');
        this.otherSockets++;
      }
      return;
    }
    if (this.socket === null || params.requestId !== this.socket) return;
    if (method === 'Network.webSocketClosed') { this.closed = true; return; }
    if (!['Network.webSocketFrameSent', 'Network.webSocketFrameReceived'].includes(method)) return;
    const response = params.response;
    if (plainObject(response) && [8, 9, 10].includes(response.opcode)) {
      if (response.opcode === 8) this.closed = true;
      return;
    }
    need(plainObject(response) && response.opcode === 1 &&
      typeof response.payloadData === 'string' && Buffer.byteLength(response.payloadData) <= 2 * 1024**2,
    'FRAME_REFUSED');
    let message;
    try { message = JSON.parse(response.payloadData); } catch { throw new Refused('FRAME_REFUSED'); }
    need(plainObject(message), 'FRAME_REFUSED');
    const id = message.id;
    const identifier = typeof id === 'string' && id.length > 0 && id.length <= 128 || Number.isSafeInteger(id);
    if (method.endsWith('Sent') && message.method === 'getVM') {
      need(identifier && !this.requests.has(id) && this.requests.size < 32 &&
        this.getVmRequests < 1000 && !this.closed, 'REQUEST_REFUSED');
      this.requests.add(id);
      this.getVmRequests++;
    } else if (method.endsWith('Received') && this.requests.has(id)) {
      need(!this.closed && message.error === undefined && plainObject(message.result) &&
        message.result.type === 'VM' && message.result.pid === this.pid, 'VM_REFUSED');
      this.requests.delete(id);
      this.getVmReplies++;
      this.attached = true;
    }
  }
  public() { return {frontendGetVmMatched: this.attached && !this.held,
    frontendSocketClosed: this.closed, held: this.held,
    serviceSocketSeen: this.socket !== null, getVmRequests: this.getVmRequests,
    getVmReplies: this.getVmReplies, otherSockets: this.otherSockets}; }
}

class Cdp {
  constructor(socket, observations) {
    this.socket = socket;
    this.next = 1;
    this.pending = new Map();
    this.bytes = 0;
    this.failed = null;
    this.session = null;
    this.exchange = null;
    this.observations = observations;
    socket.addEventListener('message', event => {
      try {
        need(typeof event.data === 'string', 'CDP_OUTPUT_REFUSED');
        this.bytes += Buffer.byteLength(event.data);
        need(Buffer.byteLength(event.data) <= 3 * 1024**2 && this.bytes <= 16 * 1024**2, 'CDP_OUTPUT_REFUSED');
        const message = JSON.parse(event.data);
        need(plainObject(message), 'CDP_OUTPUT_REFUSED');
        if (message.id !== undefined) {
          const request = this.pending.get(message.id);
          need(request && !message.error && plainObject(message.result) &&
            message.sessionId === request.session, 'CDP_RESPONSE_REFUSED');
          clearTimeout(request.timer);
          this.pending.delete(message.id);
          request.resolve(message.result);
        } else {
          if (message.method === 'Target.targetCreated' &&
              ['worker', 'shared_worker', 'service_worker'].includes(message.params?.targetInfo?.type)) {
            this.observations.workerTargets = Math.min(64, this.observations.workerTargets + 1);
          }
          if (this.exchange && message.sessionId === this.session) {
            this.exchange.event(message.method, message.params);
            this.observe(message.method, message.params);
          }
        }
      } catch (error) { this.fail(error instanceof Refused ? error : new Refused('CDP_OUTPUT_REFUSED')); }
    });
    socket.addEventListener('error', () => this.fail(new Refused('CDP_IO_REFUSED')));
    socket.addEventListener('close', () => {
      if (this.pending.size) this.fail(new Refused('CDP_COMMAND_UNCERTAIN'));
    });
  }
  observe(method, params) {
    if (method === 'Page.loadEventFired') this.observations.pageLoaded = true;
    if (method === 'Network.loadingFailed') {
      this.observations.networkFailures = Math.min(1000, this.observations.networkFailures + 1);
    }
    let text = '';
    if (method === 'Runtime.exceptionThrown') {
      this.observations.runtimeExceptions = Math.min(1000, this.observations.runtimeExceptions + 1);
      const detail = params?.exceptionDetails;
      text = [detail?.text, detail?.exception?.description].filter(value => typeof value === 'string').join(' ');
    } else if (method === 'Runtime.consoleAPICalled') {
      text = (params?.args ?? []).slice(0, 8).map(value => value?.value)
        .filter(value => typeof value === 'string' && value.length <= 16384).join(' ');
    }
    this.observations.webglIssue ||= /webgl|canvaskit|swiftshader/i.test(text);
    this.observations.wasmIssue ||= /webassembly|wasm.*(?:fail|error|unsupported)/i.test(text);
  }
  fail(error) {
    this.failed ??= error;
    for (const request of this.pending.values()) { clearTimeout(request.timer); request.reject(error); }
    this.pending.clear();
  }
  async send(method, params = {}, session) {
    need(this.failed === null && this.next <= 64, 'CDP_COMMAND_UNCERTAIN');
    const id = this.next++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => this.fail(new Refused('CDP_COMMAND_UNCERTAIN')), 10000);
      this.pending.set(id, {resolve, reject, timer, session});
      this.socket.send(JSON.stringify({id, method, params, ...(session ? {sessionId: session} : {})}));
    });
  }
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function gate() {
  let bytes = 0;
  let input = '';
  const timer = setTimeout(() => process.stdin.destroy(new Refused('INPUT_REFUSED')), 15000);
  try {
    for await (const data of process.stdin) {
      bytes += data.length;
      need(bytes <= 16384, 'INPUT_REFUSED');
      input += data.toString('utf8');
      const lines = input.split('\n');
      if (lines.length >= 3) {
        need(lines.length === 3 && lines[0] === 'START' && lines[2] === '', 'INPUT_REFUSED');
        return JSON.parse(lines[1]);
      }
    }
    throw new Refused('INPUT_REFUSED');
  } finally { clearTimeout(timer); }
}

export async function main() {
  const result = {schema: 1, ok: false, scope: 'owned_devtools_frontend', attached: false,
    headless: true, browserExit: null, outputComplete: false, forced: false, code: null,
    phase: 'new'};
  const observations = {pageLoaded: false, documentReady: false, devtoolsTitle: false,
    frontendSourceMatched: false,
    runtimeExceptions: 0, webglIssue: false, wasmIssue: false, networkFailures: 0, workerTargets: 0};
  let original, cdp, exchange;
  let exited = false, completed = 0, outputBytes = 0, overflow = false;
  const digest = createHash('sha256');
  try {
    need(process.platform === 'win32' && process.env.GITHUB_ACTIONS === 'true' &&
      process.env.RUNNER_ENVIRONMENT === 'github-hosted' && process.env.GITHUB_WORKSPACE === process.cwd(),
    'ENVIRONMENT_REFUSED');
    const profile = process.env.SYRIUS_WINDOWS_DEBUG_PROFILE;
    const prefix = path.join(process.cwd(), '.harness', 'ci-windows-debug-');
    need(typeof profile === 'string' && profile.startsWith(prefix) &&
      /^[0-9a-f]{24}$/.test(profile.slice(prefix.length)) && process.env.USERPROFILE === profile,
    'PROFILE_REFUSED');
    const command = await gate();
    need(plainObject(command), 'INPUT_REFUSED');
    const address = frontendAddress(command.devtools, command.service);
    exchange = new FrontendExchange(command.service, command.pid);
    result.phase = 'admitted';
    const candidates = [];
    for (const name of ['PROGRAMFILES', 'PROGRAMFILES(X86)', 'PROGRAMW6432']) {
      if (process.env[name]) {
        candidates.push(path.join(process.env[name], 'Google', 'Chrome', 'Application', 'chrome.exe'));
        candidates.push(path.join(process.env[name], 'Microsoft', 'Edge', 'Application', 'msedge.exe'));
      }
    }
    let binary;
    for (const candidate of candidates) {
      try {
        const info = await fs.lstat(candidate);
        if (info.isFile() && !info.isSymbolicLink()) { binary = candidate; break; }
      } catch (error) { if (error.code !== 'ENOENT') throw new Refused('BROWSER_REFUSED'); }
    }
    need(binary, 'BROWSER_REFUSED');
    const data = path.join(profile, 'DevTools');
    await fs.mkdir(data);
    original = spawn(binary, ['--headless=new', '--no-first-run', '--no-default-browser-check',
      '--disable-background-networking', '--disable-component-update', '--disable-sync',
      '--metrics-recording-only', '--disk-cache-size=16777216', '--disable-gpu-shader-disk-cache',
      '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0',
      `--user-data-dir=${data}`, 'about:blank'], {shell: false, windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']});
    const ended = new Promise((resolve, reject) => {
      original.once('error', () => reject(new Refused('BROWSER_REFUSED')));
      original.once('exit', (code, signal) => { exited = true; result.browserExit = code; resolve({code, signal}); });
    });
    ended.catch(() => {});
    result.phase = 'browser_started';
    for (const stream of [original.stdout, original.stderr]) {
      stream.on('data', bytes => { outputBytes += bytes.length; digest.update(bytes); overflow ||= outputBytes > 1024**2; });
      stream.on('end', () => { completed++; });
    }
    const deadline = Date.now() + 90000;
    let connection;
    while (Date.now() < deadline) {
      need(!exited && !overflow, 'BROWSER_REFUSED');
      try {
        const file = path.join(data, 'DevToolsActivePort');
        const info = await fs.lstat(file);
        need(info.isFile() && !info.isSymbolicLink() && info.size <= 1024, 'BROWSER_REFUSED');
        const lines = (await fs.readFile(file, 'utf8')).trim().split(/\r?\n/);
        need(lines.length === 2 && /^[0-9]{4,5}$/.test(lines[0]) &&
          +lines[0] >= 1024 && +lines[0] <= 65535 &&
          /^\/devtools\/browser\/[0-9a-f-]{36}$/.test(lines[1]), 'BROWSER_REFUSED');
        connection = new WebSocket(`ws://127.0.0.1:${lines[0]}${lines[1]}`);
        break;
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
      await sleep(100);
    }
    need(connection, 'BROWSER_TIMEOUT');
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Refused('BROWSER_TIMEOUT')), 10000);
      connection.addEventListener('open', () => { clearTimeout(timer); resolve(); }, {once: true});
      connection.addEventListener('error', () => { clearTimeout(timer); reject(new Refused('CDP_IO_REFUSED')); }, {once: true});
    });
    cdp = new Cdp(connection, observations);
    result.phase = 'browser_socket_bound';
    await cdp.send('Target.setDiscoverTargets', {discover: true});
    const target = await cdp.send('Target.createTarget', {url: 'about:blank'});
    const attached = await cdp.send('Target.attachToTarget', {targetId: target.targetId, flatten: true});
    cdp.session = attached.sessionId;
    cdp.exchange = exchange;
    await cdp.send('Network.enable', {maxTotalBufferSize: 2 * 1024**2}, cdp.session);
    await cdp.send('Page.enable', {}, cdp.session);
    await cdp.send('Runtime.enable', {}, cdp.session);
    const navigation = await cdp.send('Page.navigate', {url: address}, cdp.session);
    need(!navigation.errorText, 'FRONTEND_REFUSED');
    result.phase = 'page_navigated';
    while (!exchange.attached && Date.now() < deadline) {
      if (cdp.failed) throw cdp.failed;
      need(!exited && !overflow, 'BROWSER_REFUSED');
      await sleep(100);
    }
    const initialPage = await cdp.send('Runtime.evaluate', {
      expression: frontendPageExpression(address),
      returnByValue: true,
    }, cdp.session);
    const initial = initialPage.result?.value;
    need(plainObject(initial) && !initialPage.exceptionDetails && typeof initial.ready === 'boolean' &&
      typeof initial.devtools === 'boolean' && typeof initial.sourceMatched === 'boolean', 'FRONTEND_UNCONFIRMED');
    observations.documentReady = initial.ready;
    observations.devtoolsTitle = initial.devtools;
    observations.frontendSourceMatched = initial.sourceMatched;
    need(exchange.attached && !exchange.closed, 'FRONTEND_UNCONFIRMED');
    result.phase = 'vm_matched';
    for (let attempt = 0; attempt < 20 && Date.now() < deadline; attempt++) {
      const visible = await cdp.send('Runtime.evaluate', {
        expression: frontendPageExpression(address),
        returnByValue: true,
      }, cdp.session);
      const value = visible.result?.value;
      need(plainObject(value) && !visible.exceptionDetails && typeof value.ready === 'boolean' &&
        typeof value.devtools === 'boolean' && typeof value.sourceMatched === 'boolean', 'FRONTEND_UNCONFIRMED');
      observations.documentReady = value.ready;
      observations.devtoolsTitle = value.devtools;
      observations.frontendSourceMatched = value.sourceMatched;
      if (value.ready && value.sourceMatched) break;
      await sleep(500);
    }
    need(observations.documentReady && observations.frontendSourceMatched && !exchange.closed, 'FRONTEND_UNCONFIRMED');
    result.attached = true;
    result.phase = 'ui_ready';
    result.phase = 'close_requested';
    await cdp.send('Browser.close');
    let exitTimer;
    let exit;
    try {
      exit = await Promise.race([ended, new Promise((_, reject) => {
        exitTimer = setTimeout(() => reject(new Refused('BROWSER_EXIT_UNCONFIRMED')), 10000);
      })]);
    } finally { clearTimeout(exitTimer); }
    need(exit.code === 0 && exit.signal === null, 'BROWSER_EXIT_UNCONFIRMED');
    result.phase = 'browser_exited';
    for (let index = 0; completed !== 2 && index < 100; index++) await sleep(20);
    result.outputComplete = completed === 2 && !overflow;
    result.ok = result.attached && result.outputComplete;
  } catch (error) {
    result.code = error instanceof Refused ? error.code : 'INTERNAL_ERROR';
  } finally {
    cdp?.socket.close();
    if (original && !exited) { result.forced = true; original.kill(); }
    result.outputBytes = outputBytes;
    result.outputSha256 = digest.digest('hex');
    result.observations = {...observations, ...(exchange?.public() ?? {
      frontendGetVmMatched: false, frontendSocketClosed: false, held: false,
      serviceSocketSeen: false, getVmRequests: 0, getVmReplies: 0, otherSockets: 0,
    })};
    result.ok &&= !result.forced && result.code === null;
  }
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exitCode = result.ok ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await main();
}

// Execute the real helper against an in-memory filesystem before SDK allocation.
const controlPhase = phase => process.stderr.write(`SYRIUS_LAB_ASSET_CONTROL_PHASE:${phase}\n`);
controlPhase('STARTED');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path').posix;
const vm = require('node:vm');
controlPhase('SOURCE_READ_STARTED');
const source = fs.readFileSync('tools/devnet/lab/make-assets.js', 'utf8');
controlPhase('SOURCE_READ_FINISHED');
const roles = ['pillar', 'pillar2', 'pillar3', 'observer', 'rpc'];
const phases = ['STARTED', 'GENESIS_READ_STARTED', 'GENESIS_WRITTEN',
  ...roles.flatMap(role => [`${role.toUpperCase()}_COPY_STARTED`, `${role.toUpperCase()}_CONFIG_WRITTEN`]),
  'COMPLETE'];
class Exit extends Error { constructor(code) { super('exit'); this.code = code; } }

function execute(args, options = {}) {
  const files = new Map();
  const dirs = new Set(['/fixture', '/fixture/source']);
  const put = (name, value) => {
    files.set(name, Buffer.from(value));
    for (let dir = path.dirname(name); dir !== '/'; dir = path.dirname(dir)) dirs.add(dir);
  };
  const genesis = { ChainIdentifier: 69, ExtraData: 'fixture', unchanged: { amount: '12345678901234567890' } };
  put('/fixture/source/genesis.json', JSON.stringify(genesis));
  for (const role of roles) {
    put(`/fixture/source/${role}/config.json`, '{"peer":"172.30.0.10","unchanged":true}\n');
    put(`/fixture/source/${role}/wallet/key`, Buffer.from([0, 1, 128, 255]));
  }
  const original = new Map([...files].map(([name, bytes]) => [name, Buffer.from(bytes)]));
  if (options.existing) put('/fixture/output/genesis.json', 'existing');
  const api = {
    existsSync: name => files.has(name) || dirs.has(name),
    mkdirSync: name => { dirs.add(name); },
    readFileSync: (name, encoding) => encoding ? files.get(name).toString(encoding) : Buffer.from(files.get(name)),
    writeFileSync: put,
    copyFileSync: (from, to) => {
      if (options.failCopy && from.includes('/pillar2/')) throw new Error('fixture copy refusal');
      put(to, files.get(from));
    },
    readdirSync: dir => {
      const names = new Set([...files.keys(), ...dirs].filter(name => path.dirname(name) === dir));
      return [...names].map(name => ({ name: path.basename(name), isDirectory: () => dirs.has(name) }));
    },
  };
  let stderr = '', stdout = '', exit = 0;
  try {
    vm.runInNewContext(source, {
      require: name => {
        if (name === 'node:fs') return api;
        if (name === 'node:path') return path;
        throw new Error('unexpected dependency');
      },
      process: { argv: ['node', 'make-assets.js', ...args],
        stderr: { write: text => { stderr += text; } }, exit: code => { throw new Exit(code); } },
      console: { log: text => { stdout += text + '\n'; }, error: text => { stderr += text + '\n'; } },
    }, { timeout: 1000 });
  } catch (error) {
    if (error instanceof Exit) exit = error.code;
    else if (options.failCopy && error.message === 'fixture copy refusal') exit = 1;
    else throw error;
  }
  for (const [name, bytes] of original) assert.deepEqual(files.get(name), bytes);
  return { files: [...files].filter(([name]) => name.startsWith('/fixture/output/')),
    stderr, stdout, exit, genesis };
}

const args = ['/fixture/source', '/fixture/output'];
controlPhase('LEGACY_STARTED');
const legacy = execute(args);
controlPhase('LEGACY_RETURNED');
controlPhase('OBSERVED_STARTED');
const observed = execute([...args, '--progress']);
controlPhase('OBSERVED_RETURNED');
assert.equal(legacy.exit, 0);
assert.equal(observed.exit, 0);
assert.deepEqual(observed.files, legacy.files);
assert.equal(legacy.stderr, '');
assert.equal(observed.stderr, phases.map(phase => `SYRIUS_LAB_ASSET_PHASE:${phase}\n`).join(''));
const generated = new Map(observed.files);
assert.equal(generated.get('/fixture/output/genesis.json').toString(),
  JSON.stringify({ ...observed.genesis, ChainIdentifier: 321, ExtraData: 'SYRIUS LAB' }, null, 4) + '\n');
for (const role of roles) {
  assert.equal(generated.get(`/fixture/output/${role}/config.json`).toString(),
    '{"peer":"172.37.0.10","unchanged":true}\n');
  assert.deepEqual(generated.get(`/fixture/output/${role}/wallet/key`), Buffer.from([0, 1, 128, 255]));
}
controlPhase('INVALID_OPTION_STARTED');
const bad = execute([...args, '--unknown']);
controlPhase('INVALID_OPTION_RETURNED');
assert.equal(bad.exit, 2);
assert.equal(bad.files.length, 0);
controlPhase('EXISTING_STARTED');
const existing = execute([...args, '--progress'], { existing: true });
controlPhase('EXISTING_RETURNED');
assert.equal(existing.exit, 1);
assert.equal(existing.files.length, 1);
assert.equal(existing.files[0][1].toString(), 'existing');
controlPhase('INTERRUPTED_STARTED');
const interrupted = execute([...args, '--progress'], { failCopy: true });
controlPhase('INTERRUPTED_RETURNED');
assert.equal(interrupted.exit, 1);
assert.equal(interrupted.stderr, phases.slice(0, 6).map(phase => `SYRIUS_LAB_ASSET_PHASE:${phase}\n`).join(''));
controlPhase('COMPLETE');
console.log('::notice title=Lab asset helper tests::' + JSON.stringify({ schema: 1,
  scope: 'lab_asset_helper_inmemory_cases', success: true, cases: 4,
  asset_bytes_equal: true, filesystem_scratch: 0, native_wallet_executions: 0 }));

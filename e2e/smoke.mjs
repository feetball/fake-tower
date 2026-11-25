// End-to-end smoke test: real server, 4 headless Chromium contexts, one full round.
// Run with `npm run e2e`. Requires a global Playwright install with Chromium.

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import { createServer } from 'node:net';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

// Playwright is installed globally, not in package.json. ESM ignores NODE_PATH,
// so resolve it through require with the global roots as fallbacks.
const chromium = (() => {
  const req = createRequire(import.meta.url);
  const roots = [];
  try {
    roots.push(execSync('npm root -g', { encoding: 'utf8' }).trim());
  } catch {
    /* ignore */
  }
  roots.push(...(process.env.NODE_PATH ?? '').split(':').filter(Boolean));
  try {
    return req('playwright').chromium;
  } catch {
    /* fall through */
  }
  for (const r of roots) {
    try {
      return req(join(r, 'playwright')).chromium;
    } catch {
      /* try next */
    }
  }
  throw new Error('Cannot load playwright (expected a global install)');
})();

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SHOTS = join(ROOT, 'e2e', 'screenshots');
const ROUND_TIMEOUT_MS = 8 * 60 * 1000;

// Console/page errors matching these are network-environment noise, not game bugs.
const IGNORED = [
  /ICE/i,
  /STUN/i,
  /stun:/i,
  /WebRTC/i,
  /RTCPeerConnection/i,
  /ERR_NAME_NOT_RESOLVED/i,
  /ERR_INTERNET_DISCONNECTED/i,
  /ERR_NETWORK_CHANGED/i,
];

const steps = [];
let warnings = [];
const ignoredErrors = [];
const realErrors = [];

function log(msg) {
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`);
}
async function step(name, fn) {
  log(`STEP  ${name}`);
  const t0 = Date.now();
  try {
    const r = await fn();
    steps.push({ name, ok: true, ms: Date.now() - t0 });
    log(`PASS  ${name} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
    return r;
  } catch (e) {
    steps.push({ name, ok: false, ms: Date.now() - t0, err: e });
    log(`FAIL  ${name}: ${e && e.message ? e.message : e}`);
    throw e;
  }
}
function warn(msg) {
  warnings.push(msg);
  log(`WARN  ${msg}`);
}
function assert(cond, msg) {
  if (!cond) throw new Error(`Assertion failed: ${msg}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function freePort() {
  return new Promise((res, rej) => {
    const s = createServer();
    s.once('error', rej);
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => res(port));
    });
  });
}

let server = null;
let browser = null;

async function startServer(port) {
  server = spawn('npx', ['tsx', 'src/server/main.ts'], {
    cwd: ROOT,
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: true,
  });
  let out = '';
  server.stdout.on('data', (d) => (out += d));
  server.stderr.on('data', (d) => (out += d));
  const t0 = Date.now();
  while (!/Fake Tower server on/.test(out)) {
    if (server.exitCode !== null) throw new Error(`server exited early:\n${out}`);
    if (Date.now() - t0 > 30000) throw new Error(`server did not start:\n${out}`);
    await sleep(100);
  }
}

function stopServer() {
  if (!server || server.exitCode !== null) return;
  try {
    process.kill(-server.pid, 'SIGTERM'); // whole process group (npx -> tsx -> node)
  } catch {
    try {
      server.kill('SIGTERM');
    } catch {
      /* already gone */
    }
  }
}

async function main() {
  mkdirSync(SHOTS, { recursive: true });

  await step('build client (vite build)', async () => {
    const r = spawnSync('npx', ['vite', 'build'], { cwd: ROOT, encoding: 'utf8' });
    if (r.status !== 0) throw new Error(`vite build failed:\n${r.stdout}\n${r.stderr}`);
    assert(existsSync(join(ROOT, 'dist', 'client', 'index.html')), 'dist/client/index.html exists');
  });

  const port = await freePort();
  const url = `http://127.0.0.1:${port}/`;
  await step(`start server on port ${port}`, () => startServer(port));

  browser = await chromium.launch({
    args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'],
  });

  const names = ['Alice', 'Bob', 'Carol', 'Dave'];
  const pages = [];
  for (const name of names) {
    const ctx = await browser.newContext({
      viewport: { width: 1280, height: 720 },
      deviceScaleFactor: 1,
      permissions: ['microphone'],
    });
    const page = await ctx.newPage();
    page.ftName = name;
    page.on('pageerror', (e) => record(name, 'pageerror', e.message));
    page.on('console', (m) => {
      if (m.type() === 'error') record(name, 'console.error', m.text());
    });
    pages.push(page);
  }
  function record(who, kind, text) {
    const line = `${who} ${kind}: ${text}`;
    if (IGNORED.some((re) => re.test(text))) ignoredErrors.push(line);
    else realErrors.push(line);
  }

  const lobbyCount = (p) => p.locator('.player-list li').count();

  await step('create room and join with 3 other players', async () => {
    const [host, ...rest] = pages;
    await host.goto(url);
    await host.fill('#name-input', host.ftName);
    await host.waitForFunction(() => window.__ft.state.conn === 'open');
    await host.click('#create-btn');
    await host.waitForSelector('#room-code:not(:empty)');
    const code = (await host.textContent('#room-code')).trim();
    assert(/^[A-Z]{4}$/.test(code), `room code looks like 4 letters, got "${code}"`);
    log(`room code ${code}`);
    for (const p of rest) {
      await p.goto(url);
      await p.fill('#name-input', p.ftName);
      await p.fill('#join-code', code);
      await p.waitForFunction(() => window.__ft.state.conn === 'open');
      await p.click('#join-btn');
      await p.waitForSelector('#room-code:not(:empty)');
    }
  });

  await step('lobby shows 4 players on every page', async () => {
    for (const p of pages) {
      await p.waitForFunction(() => document.querySelectorAll('.player-list li').length === 4, null, { timeout: 10000 });
      assert((await lobbyCount(p)) === 4, `${p.ftName} sees 4 players`);
    }
    await sleep(500);
    await pages[0].screenshot({ path: join(SHOTS, '01-lobby.png') });
  });

  let voiceConnected = false;
  await step('voice: wait for WebRTC peers to connect in the lobby (non-fatal)', async () => {
    const micOk = await Promise.all(pages.map((p) => p.evaluate(() => window.__ft.state.mic.ok)));
    log(`mic ok per page: ${micOk.join(', ')}`);
    if (micOk.some((v) => !v)) warn('fake microphone not available on some pages');
    try {
      await Promise.all(
        pages.map((p) =>
          p.waitForFunction(() => window.__ft.state.mic.connected.length >= 3, null, { timeout: 25000 }),
        ),
      );
      voiceConnected = true;
      log('all 4 pages have 3 connected voice peers (full mesh)');
    } catch {
      const counts = await Promise.all(pages.map((p) => p.evaluate(() => window.__ft.state.mic.connected.length)));
      warn(`WebRTC peers did not fully connect within 25s (connected peers per page: ${counts.join(', ')}). Likely no STUN/host-candidate connectivity in this sandbox.`);
    }
  });

  await step('host starts the round', async () => {
    await pages[0].click('#start-btn');
    for (const p of pages) {
      await p.waitForFunction(() => window.__ft.state.view === 'round' && !!window.__ft.state.round, null, { timeout: 15000 });
    }
  });

  let controllers = [];
  let pilots = [];
  await step('roles: 2 controller scopes, 2 pilot cockpits, exactly one impostor banner', async () => {
    const scopeVis = await Promise.all(pages.map((p) => p.locator('#scope-canvas').isVisible()));
    const ckVis = await Promise.all(pages.map((p) => p.locator('#cockpit').isVisible()));
    assert(scopeVis.filter(Boolean).length === 2, `exactly 2 pages show #scope-canvas (got ${scopeVis})`);
    assert(ckVis.filter(Boolean).length === 2, `exactly 2 pages show #cockpit (got ${ckVis})`);
    pages.forEach((p, i) => {
      assert(scopeVis[i] !== ckVis[i], `${p.ftName} shows exactly one of scope/cockpit`);
      (scopeVis[i] ? controllers : pilots).push(p);
    });
    const imp = await Promise.all(pages.map((p) => p.locator('#role-banner.impostor').count()));
    assert(imp.reduce((a, b) => a + b, 0) === 1, `exactly one impostor banner (got ${imp})`);
    for (const p of controllers) {
      const t = await p.textContent('#role-banner');
      assert(/IMPOSTOR|REAL TOWER/.test(t), `controller banner text sensible: ${t}`);
    }
    log(`controllers: ${controllers.map((p) => p.ftName)}; pilots: ${pilots.map((p) => p.ftName)}`);
  });

  await step('pilot client state does not leak impostor identity or radar targets', async () => {
    await sleep(3000); // let at least one radar sweep (2 s) go out
    for (const p of pilots) {
      const info = await p.evaluate(() => {
        const s = window.__ft.state;
        const json = JSON.stringify(s, (k, v) => (v instanceof Map ? Object.fromEntries(v) : v));
        return {
          radar: s.radar,
          role: s.round.you.role,
          youImpostor: s.round.you.impostor,
          playerKeys: [...new Set(s.round.players.flatMap((x) => Object.keys(x)))],
          hasImpostorTrue: /"impostor"\s*:\s*true/.test(json),
          hasImpostorId: /impostorId|realControllerId/.test(json),
          end: s.end,
          hasOwn: !!s.own,
        };
      });
      assert(info.role === 'pilot', `${p.ftName} is a pilot`);
      assert(info.radar === null, `${p.ftName} has no radar data in state`);
      assert(info.youImpostor === false, `${p.ftName} you.impostor is false`);
      assert(!info.hasImpostorTrue, `${p.ftName} state has no impostor:true anywhere`);
      assert(!info.hasImpostorId, `${p.ftName} state has no impostorId/realControllerId before the end`);
      assert(!info.playerKeys.some((k) => /impost|real/i.test(k)), `${p.ftName} round.players entries carry no impostor field (keys: ${info.playerKeys})`);
      assert(info.hasOwn, `${p.ftName} receives own aircraft data`);
    }
    // sanity: controllers do get radar targets and exactly one knows it is the impostor
    const flags = [];
    for (const p of controllers) {
      const r = await p.evaluate(() => ({ n: window.__ft.state.radar?.targets.length ?? -1, imp: window.__ft.state.round.you.impostor }));
      assert(r.n === 2, `${p.ftName} (controller) sees 2 radar targets (got ${r.n})`);
      flags.push(r.imp);
    }
    assert(flags.filter(Boolean).length === 1, `exactly one controller has you.impostor=true (got ${flags})`);
  });

  await step('screenshots: scope and cockpit (plate, ATIS)', async () => {
    await sleep(1500);
    await controllers[0].screenshot({ path: join(SHOTS, '02-scope.png') });
    const pl = pilots[0];
    await pl.screenshot({ path: join(SHOTS, '03-cockpit.png') });
    await pl.keyboard.press('p');
    await pl.waitForSelector('.plate-card', { state: 'visible' });
    await sleep(700);
    await pl.screenshot({ path: join(SHOTS, '04-cockpit-plate.png') });
    await pl.keyboard.press('Escape');
    await pl.keyboard.press('i');
    await pl.waitForSelector('.atis-card', { state: 'visible' });
    await sleep(300);
    await pl.screenshot({ path: join(SHOTS, '05-cockpit-atis.png') });
    await pl.keyboard.press('Escape');
    assert(!(await pl.locator('.atis-card').isVisible()), 'ATIS closed with Escape');
  });

  const indicator = (p) => p.locator('#radio-indicator');
  const waitIndicator = (p, re, label) =>
    p.waitForFunction(
      (src) => new RegExp(src).test(document.getElementById('radio-indicator')?.textContent ?? ''),
      re.source,
      { timeout: 8000 },
    ).catch(async () => {
      throw new Error(`${label}: expected #radio-indicator to match ${re}, got "${await indicator(p).textContent()}"`);
    });

  await step('push-to-talk: Space on one page -> TX there, RX everywhere else', async () => {
    const sender = controllers[0];
    await sender.bringToFront();
    await sender.keyboard.down('Space');
    await waitIndicator(sender, /^TX$/, `${sender.ftName} (sender)`);
    for (const p of pages) if (p !== sender) await waitIndicator(p, /^RX /, `${p.ftName} (listener)`);
    const rx = await indicator(pages.find((p) => p !== sender)).textContent();
    log(`listener indicator: "${rx}"`);
    await sender.keyboard.up('Space');
    for (const p of pages) await waitIndicator(p, /^IDLE$/, `${p.ftName} after release`);
  });

  await step('push-to-talk: two keyed at once -> BLOCKED everywhere', async () => {
    const [a, b] = [controllers[0], controllers[1]];
    await a.bringToFront();
    await a.keyboard.down('Space');
    await b.bringToFront();
    await b.keyboard.down('Space');
    for (const p of pages) await waitIndicator(p, /^BLOCKED$/, `${p.ftName}`);
    await a.keyboard.up('Space');
    await b.keyboard.up('Space');
    for (const p of pages) await waitIndicator(p, /^IDLE$/, `${p.ftName} after release`);
  });

  await step('voice: report WebRTC status at round time', async () => {
    const counts = await Promise.all(pages.map((p) => p.evaluate(() => window.__ft.state.mic.connected.length)));
    log(`voice peers connected per page: ${counts.join(', ')} (voice connected in lobby: ${voiceConnected})`);
    if (counts.some((c) => c < 3)) warn(`WebRTC voice mesh incomplete during round (${counts.join(', ')} of 3 peers)`);
  });

  await step('descend both pilots to altitude 0 so they crash', async () => {
    for (const p of pilots) {
      await p.bringToFront();
      await p.fill('#mcp-alt', '0');
      await p.press('#mcp-alt', 'Enter');
      try {
        await p.waitForFunction(() => window.__ft.state.own?.ac.selAlt === 0, null, { timeout: 4000 });
      } catch {
        log(`${p.ftName}: MCP field did not take, falling back to Shift+ArrowDown`);
        await p.locator('body').click({ position: { x: 5, y: 5 } }).catch(() => {});
        for (let i = 0; i < 20; i++) await p.keyboard.press('Shift+ArrowDown');
        await p.waitForFunction(() => window.__ft.state.own?.ac.selAlt === 0, null, { timeout: 4000 });
      }
      log(`${p.ftName}: selected altitude 0 confirmed by server`);
    }
  });

  await step('wait for the round to end (#end-screen on all pages)', async () => {
    const t0 = Date.now();
    let lastLog = 0;
    for (;;) {
      const vis = await Promise.all(pages.map((p) => p.locator('#end-screen').isVisible()));
      if (vis.every(Boolean)) break;
      if (Date.now() - t0 > ROUND_TIMEOUT_MS) throw new Error('round did not end within timeout');
      if (Date.now() - lastLog > 20000) {
        lastLog = Date.now();
        const st = await Promise.all(pilots.map((p) => p.evaluate(() => {
          const a = window.__ft.state.own?.ac;
          return a ? `${a.callsign} ${a.status} alt=${Math.round(a.indAlt)} vs=${Math.round(a.vs)}` : 'n/a';
        })));
        log(`  waiting... ${st.join(' | ')}`);
      }
      await sleep(1000);
    }
    await sleep(800);
    await pages[0].screenshot({ path: join(SHOTS, '06-end.png') });
  });

  await step('end screen: impostor wins, reveal names shown', async () => {
    for (const p of pages) {
      const banner = (await p.textContent('.end-banner')).trim();
      assert(/IMPOSTOR WINS/.test(banner), `${p.ftName} banner says impostor wins (got "${banner}")`);
      const sub = await p.textContent('.end-sub');
      assert(/^0 of 2 aircraft landed/.test(sub.trim()), `0 of 2 landed (got "${sub.trim()}")`);
      const real = (await p.textContent('.rev.real .rev-name')).trim();
      const imp = (await p.textContent('.rev.imp .rev-name')).trim();
      assert(names.includes(real) && names.includes(imp) && real !== imp, `reveal names real="${real}" impostor="${imp}"`);
      const res = await p.evaluate(() => window.__ft.state.end);
      assert(res.winner === 'impostor', `state.end.winner is impostor (got ${res.winner})`);
      assert(res.outcomes.length === 2 && res.outcomes.every((o) => o.outcome !== 'landed'), 'both outcomes are crashes');
      const rows = await p.locator('.end-table tbody tr').count();
      assert(rows === 2, `end table has 2 rows (got ${rows})`);
    }
    // the revealed impostor must be the controller whose banner said impostor
    const impBannerPage = (await Promise.all(pages.map(async (p) => ((await p.locator('#role-banner.impostor').count()) ? p : null)))).find(Boolean);
    // banner element is hidden on the end screen but still in the DOM; compare by name
    if (impBannerPage) {
      const revealed = (await pages[0].textContent('.rev.imp .rev-name')).trim();
      assert(revealed === impBannerPage.ftName, `revealed impostor (${revealed}) matches the page that was told it was the impostor (${impBannerPage.ftName})`);
    }
  });

  await step('host returns everyone to the lobby', async () => {
    await pages[0].click('#back-to-lobby');
    for (const p of pages) {
      await p.waitForFunction(() => window.__ft.state.view === 'lobby', null, { timeout: 10000 });
      await p.waitForFunction(() => document.querySelectorAll('.player-list li').length === 4);
      assert(await p.locator('#end-screen').isHidden(), `${p.ftName} end screen hidden`);
      assert(await p.locator('#start-btn, #room-code').first().isVisible(), `${p.ftName} lobby visible`);
    }
  });

  await step('no unexpected page or console errors', async () => {
    if (ignoredErrors.length) {
      log(`ignored ${ignoredErrors.length} benign WebRTC/ICE/network error(s) (patterns: ${IGNORED.map(String).join(' ')}):`);
      for (const l of [...new Set(ignoredErrors)].slice(0, 10)) log(`  ignored: ${l}`);
    }
    assert(realErrors.length === 0, `unexpected errors:\n  ${realErrors.join('\n  ')}`);
  });

  return { voiceConnected };
}

let exitCode = 0;
let outcome = null;
try {
  outcome = await main();
} catch (e) {
  exitCode = 1;
  log(`ERROR ${e && e.stack ? e.stack : e}`);
  if (realErrors.length) log(`collected page/console errors:\n  ${realErrors.join('\n  ')}`);
} finally {
  try {
    await browser?.close();
  } catch {
    /* ignore */
  }
  stopServer();
}

console.log('\n==== e2e summary ====');
for (const s of steps) console.log(`${s.ok ? 'PASS' : 'FAIL'}  ${s.name}  (${(s.ms / 1000).toFixed(1)}s)`);
if (outcome) console.log(`WebRTC voice mesh connected in lobby: ${outcome.voiceConnected ? 'yes' : 'NO'}`);
if (warnings.length) {
  console.log('Warnings:');
  for (const w of warnings) console.log(`  - ${w}`);
}
console.log(`Ignored benign errors: ${ignoredErrors.length}; unexpected errors: ${realErrors.length}`);
console.log(`Screenshots: ${SHOTS}`);
console.log(exitCode === 0 ? 'RESULT: PASS' : 'RESULT: FAIL');
process.exit(exitCode);

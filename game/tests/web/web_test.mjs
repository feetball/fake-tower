// Real-browser tests of the web export (headless Chromium through Playwright).
//
//   node game/tests/web/web_test.mjs [--dir DIR] [--out DIR] [--only a,b,...]
//   node game/tests/web/web_test.mjs --shot '<query>' <out.png> [--dir DIR] [--wait SEC] [--size WxH]
//
// DIR is the exported web build (default build/dist/fake-tower-web, see
// game/tools/export_build.sh web). Screenshots and logs go to --out (default
// build/web-test). Tests (all by default):
//   load        index.html loads, the menu renders, no console errors
//   demo        ?demo=controller and ?demo=pilot start an offline round and render
//   touch       phone emulation (landscape, touch): the touch UI is up; a finger holds
//               PTT while another taps the autopilot strip (HDG tab, +)
//   multiplayer a headless dedicated server (needs Godot: env GODOT, else `godot` on
//               PATH) and two pages joining ws://127.0.0.1:<port>; both reach the
//               lobby and the round starts
// Game state is read from the `?debug-state=1` hook (core/debug_state.gd):
// window.ftState, a JSON string. Playwright is not a dependency of the repo: it is
// resolved from node_modules, NODE_PATH or the global npm root (as e2e/lib.mjs does).
// Exit code 0 only when every selected test passed.

/* global process, console, setTimeout, URL, document, window */

import { execSync, spawn } from 'node:child_process';
import { createReadStream, existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { dirname, extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..', '..');
const GAME = join(REPO, 'game');

const playwright = (() => {
  const req = createRequire(import.meta.url);
  const roots = [...(process.env.NODE_PATH ?? '').split(':').filter(Boolean)];
  try {
    roots.push(execSync('npm root -g', { encoding: 'utf8' }).trim());
  } catch {
    /* no npm */
  }
  for (const id of ['playwright', ...roots.map((r) => join(r, 'playwright'))]) {
    try {
      return req(id);
    } catch {
      /* try next */
    }
  }
  throw new Error(
    'Cannot load playwright: npm install -g playwright, then npx playwright install chromium',
  );
})();
const { chromium, devices } = playwright;

// ------------------------------------------------------------------- arguments

const argv = process.argv.slice(2);
function opt(name, def) {
  const i = argv.indexOf(name);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : def;
}
const DIR = resolve(opt('--dir', join(REPO, 'build', 'dist', 'fake-tower-web')));
const OUT = resolve(opt('--out', join(REPO, 'build', 'web-test')));
const ONLY = opt('--only', 'load,demo,touch,multiplayer').split(',');
const GODOT = process.env.GODOT || whichGodot();
const LOAD_TIMEOUT = Number(process.env.WEB_TEST_LOAD_TIMEOUT_MS || 180000);

function whichGodot() {
  try {
    return execSync('command -v godot', { encoding: 'utf8', shell: '/bin/bash' }).trim();
  } catch {
    return existsSync('/home/user/tools/godot/godot') ? '/home/user/tools/godot/godot' : 'godot';
  }
}

// WebGL 2 without a GPU: SwiftShader through ANGLE. Fake microphone, auto-granted.
const CHROMIUM_ARGS = [
  '--use-angle=swiftshader',
  '--enable-unsafe-swiftshader',
  '--ignore-gpu-blocklist',
  '--use-fake-ui-for-media-stream',
  '--use-fake-device-for-media-stream',
  '--autoplay-policy=no-user-gesture-required',
];

// Console noise that is not a game bug: headless audio, WebGL performance hints,
// the browser asking for a favicon.
const IGNORED = [
  /favicon/i,
  /GPU stall due to ReadPixels/i,
  /AudioContext was not allowed to start/i,
  /Automatic fallback to software WebGL has been deprecated/i,
  /WebGL: INVALID_ENUM: getParameter/i,
];

const log = (m) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${m}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ------------------------------------------------------------------- static server

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.json': 'application/json',
  '.md': 'text/markdown',
  '.txt': 'text/plain',
};

function serve(dir) {
  const server = createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    let p = normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, '');
    if (p === '' || p.endsWith(sep)) p += 'index.html';
    const file = join(dir, p);
    if (!file.startsWith(dir + sep) || !existsSync(file) || !statSync(file).isFile()) {
      res.writeHead(404).end('not found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': MIME[extname(file)] || 'application/octet-stream',
      'Content-Length': statSync(file).size,
      'Cache-Control': 'no-store',
    });
    createReadStream(file).pipe(res);
  });
  return new Promise((ok) => server.listen(0, '127.0.0.1', () => ok(server)));
}

// ------------------------------------------------------------------- page helpers

/** Opens index.html?<query> and resolves once Godot has started (the loading overlay is gone). */
const OPENED = [];

async function openGame(ctx, base, query, label) {
  const page = await ctx.newPage();
  const errors = [];
  const lines = [];
  OPENED.push({ errors, lines, label });
  page.on('console', (m) => {
    const t = m.text();
    lines.push(`${new Date().toISOString().slice(11, 23)} ${m.type()}: ${t}`);
    if (m.type() === 'error' && !IGNORED.some((r) => r.test(t))) errors.push(t);
  });
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  await page.goto(`${base}/index.html${query ? `?${query}` : ''}`);
  await page.waitForFunction(() => !document.getElementById('status'), null, {
    timeout: LOAD_TIMEOUT,
  });
  return { page, errors, lines, label };
}

async function state(page) {
  const s = await page.evaluate(() => window.ftState ?? null);
  return s ? JSON.parse(s) : null;
}

async function waitState(page, pred, what, timeoutMs = 60000) {
  const t0 = Date.now();
  let last = null;
  while (Date.now() - t0 < timeoutMs) {
    last = await state(page);
    if (last && pred(last)) return last;
    await sleep(250);
  }
  throw new Error(`timed out waiting for ${what}; last state ${JSON.stringify(last)}`);
}

/** A rendered (non-blank) frame: a black or empty canvas compresses to a few KB. */
async function shot(page, name, minBytes = 25000) {
  const file = join(OUT, `${name}.png`);
  // The 3D pilot view under software WebGL on a small CI runner can take over a
  // minute per frame capture. The state checks are the test; a capture that times
  // out is logged, not failed.
  let buf;
  try {
    buf = await page.screenshot({ path: file, timeout: 120000 });
  } catch (e) {
    if (!/Timeout/.test(String(e))) throw e;
    log(`      screenshot ${name} skipped: capture timed out`);
    return null;
  }
  log(`      screenshot ${file} (${(buf.length / 1024).toFixed(0)} KB)`);
  if (buf.length < minBytes)
    throw new Error(`${name}: screenshot looks blank (${buf.length} bytes)`);
  return file;
}

function saveLog(g) {
  writeFileSync(join(OUT, `${g.label}.console.log`), g.lines.join('\n') + '\n');
}

function noErrors(g) {
  saveLog(g);
  if (g.errors.length)
    throw new Error(`${g.label}: console errors:\n  ${g.errors.slice(0, 10).join('\n  ')}`);
}

/** Canvas-pixel rect [x, y, w, h] -> centre in CSS pixels. */
async function centre(page, rect) {
  const k = await page.evaluate(() => {
    const c = document.querySelector('canvas');
    const b = c.getBoundingClientRect();
    return { sx: b.width / c.width, sy: b.height / c.height, ox: b.left, oy: b.top };
  });
  return { x: k.ox + (rect[0] + rect[2] / 2) * k.sx, y: k.oy + (rect[1] + rect[3] / 2) * k.sy };
}

// ------------------------------------------------------------------- tests

async function testLoad(browser, base) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  try {
    const g = await openGame(ctx, base, 'debug-state=1', 'load');
    const s = await waitState(g.page, (x) => x.phase === 'menu', 'the main menu');
    if (s.touch) throw new Error('desktop browser came up in touch mode');
    await sleep(3000);
    await shot(g.page, 'web_menu');
    noErrors(g);
  } finally {
    await ctx.close();
  }
}

async function testDemo(browser, base) {
  for (const role of ['controller', 'pilot']) {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
    try {
      const g = await openGame(ctx, base, `demo=${role}&debug-state=1`, `demo_${role}`);
      await waitState(
        g.page,
        (x) => x.phase === 'playing' && x.role === role,
        `a ${role} demo round`,
      );
      await sleep(role === 'pilot' ? 8000 : 5000);
      await shot(g.page, `web_demo_${role}`);
      noErrors(g);
    } finally {
      await ctx.close();
    }
  }
}

async function testTouch(browser, base) {
  const phone = devices['Pixel 7 landscape'] ?? devices['Pixel 5 landscape'];
  const ctx = await browser.newContext({ ...phone, hasTouch: true, isMobile: true });
  try {
    const g = await openGame(ctx, base, 'demo=pilot&debug-state=1', 'touch');
    const s0 = await waitState(
      g.page,
      (x) =>
        x.phase === 'playing' && x.touch && x.targets.ptt && x.targets.tab_hdg && x.targets.plus,
      'the pilot touch UI',
    );
    await sleep(4000);
    await shot(g.page, 'web_touch_pilot');
    const cdp = await ctx.newCDPSession(g.page);
    const ptt = await centre(g.page, s0.targets.ptt);
    const tab = await centre(g.page, s0.targets.tab_hdg);
    const plus = await centre(g.page, s0.targets.plus);
    const touch = (type, points) =>
      cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points });
    const finger0 = { ...ptt, id: 0 };
    // Finger 0 holds PTT.
    await touch('touchStart', [finger0]);
    await waitState(g.page, (x) => x.ptt, 'PTT keyed by a held touch', 10000);
    log('      PTT keyed while finger 0 is down');
    // Finger 1 taps the HDG tab, then + twice, while finger 0 stays down.
    const hdg0 = (await state(g.page)).sel_hdg;
    for (const p of [tab, plus, plus]) {
      const finger1 = { ...p, id: 1 };
      await touch('touchStart', [finger0, finger1]);
      // Long enough for a frame or two at software-rendered frame rates.
      await sleep(400);
      // touchEnd lists the points that lift: finger 0 stays down.
      await touch('touchEnd', [finger1]);
      await sleep(1000);
    }
    const want = (hdg0 + 2) % 360;
    const s1 = await waitState(
      g.page,
      (x) => x.sel_hdg === want,
      `sel_hdg ${hdg0} -> ${want}`,
      10000,
    );
    log(`      HDG ${hdg0} -> ${s1.sel_hdg} with PTT held`);
    if (!s1.ptt) throw new Error('PTT dropped while the other finger tapped');
    await shot(g.page, 'web_touch_ptt_held');
    await touch('touchEnd', [finger0]);
    await waitState(g.page, (x) => !x.ptt, 'PTT released', 10000);
    noErrors(g);
  } finally {
    await ctx.close();
  }
}

async function testMultiplayer(browser, base) {
  const port = 27270 + 100 + Math.floor(Math.random() * 500) * 2;
  const wsPort = port + 1;
  const serverLog = [];
  const srv = spawn(
    GODOT,
    [
      '--headless',
      '--path',
      GAME,
      'res://core/net/server.tscn',
      '--',
      '--server',
      `--port=${port}`,
      `--ws-port=${wsPort}`,
      '--min-players=2',
      '--autostart-at=2',
    ],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  );
  const onData = (d) => serverLog.push(...d.toString().split('\n').filter(Boolean));
  srv.stdout.on('data', onData);
  srv.stderr.on('data', onData);
  const ctxs = [];
  const extraBrowsers = [];
  try {
    const t0 = Date.now();
    while (!serverLog.some((l) => /\[server\]/.test(l))) {
      if (srv.exitCode !== null)
        throw new Error(`server exited: ${serverLog.slice(-5).join(' | ')}`);
      if (Date.now() - t0 > 60000) throw new Error('server did not start');
      await sleep(250);
    }
    log(`      server up: ${serverLog.find((l) => /\[server\]/.test(l))}`);
    // Each player in a browser of its own, joining one after the other: in one headless
    // browser the second software-rendered page's WebSocket never opened (Chromium
    // quirk with two SwiftShader WebGL pages; separate browsers, as for real players, work).
    const games = [];
    for (const name of ['A', 'B']) {
      const b = name === 'A' ? browser : await chromium.launch({ args: CHROMIUM_ARGS });
      if (b !== browser) extraBrowsers.push(b);
      const ctx = await b.newContext({ viewport: { width: 1280, height: 720 } });
      ctxs.push(ctx);
      const g = await openGame(
        ctx,
        base,
        `join=ws://127.0.0.1:${wsPort}&name=${name}&debug-state=1`,
        `mp_${name}`,
      );
      games.push(g);
      await waitState(
        g.page,
        (x) => x.phase === 'lobby' || x.phase === 'playing',
        `${g.label} in the lobby`,
        60000,
      );
      if (name === 'A') await shot(g.page, 'web_mp_A_lobby');
    }
    log('      both pages joined the lobby over WebSocket');
    for (const g of games) {
      const s = await waitState(
        g.page,
        (x) => x.phase === 'playing' && x.role !== '',
        `${g.label} in a round`,
        60000,
      );
      log(`      ${g.label}: role ${s.role}, transport ${s.transport}`);
      if (s.transport !== 'ws')
        throw new Error(`${g.label}: transport ${s.transport}, expected ws`);
    }
    await sleep(5000);
    await shot(games[0].page, 'web_mp_A_round');
    await shot(games[1].page, 'web_mp_B_round');
    if (!serverLog.some((l) => /round/i.test(l))) throw new Error('server log has no round start');
    for (const g of games) noErrors(g);
  } finally {
    for (const c of ctxs) await c.close();
    for (const b of extraBrowsers) await b.close();
    srv.kill('SIGTERM');
    writeFileSync(join(OUT, 'mp_server.log'), serverLog.join('\n') + '\n');
  }
}

// ------------------------------------------------------------------- main

async function main() {
  if (!existsSync(join(DIR, 'index.html'))) {
    console.error(
      `No web build in ${DIR}: run game/tools/export_build.sh web first (or pass --dir)`,
    );
    process.exit(2);
  }
  mkdirSync(OUT, { recursive: true });
  const server = await serve(DIR);
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ args: CHROMIUM_ARGS });
  let failed = 0;
  try {
    if (argv.includes('--shot')) {
      // Ad-hoc screenshot: --shot '<query>' <out.png> [--wait SEC] [--size WxH]
      const i = argv.indexOf('--shot');
      const [w, h] = opt('--size', '1280x720').split('x').map(Number);
      const ctx = await browser.newContext({ viewport: { width: w, height: h } });
      const g = await openGame(ctx, base, argv[i + 1], 'shot');
      await sleep(Number(opt('--wait', '10')) * 1000);
      await g.page.screenshot({ path: resolve(argv[i + 2]) });
      saveLog(g);
      log(
        `saved ${argv[i + 2]}; console errors: ${g.errors.length ? g.errors.join(' | ') : 'none'}`,
      );
      await ctx.close();
      return;
    }
    const tests = {
      load: testLoad,
      demo: testDemo,
      touch: testTouch,
      multiplayer: testMultiplayer,
    };
    for (const name of ONLY) {
      if (!tests[name]) throw new Error(`unknown test ${name}`);
      const t0 = Date.now();
      log(`STEP  ${name}`);
      try {
        await tests[name](browser, base);
        log(`PASS  ${name} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
      } catch (e) {
        failed++;
        log(`FAIL  ${name}: ${e && e.stack ? e.stack : e}`);
      }
    }
  } finally {
    for (const g of OPENED) saveLog(g);
    await browser.close();
    server.close();
  }
  log(failed ? `${failed} test(s) failed` : 'all web tests passed');
  process.exitCode = failed ? 1 : 0;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

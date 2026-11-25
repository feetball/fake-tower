// Shared helpers for the end-to-end scenarios: Playwright loading, logging with
// PASS/FAIL steps, server lifecycle, browser players and cockpit/lobby actions.

import { execSync, spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createServer } from 'node:net';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Playwright is installed globally, not in package.json. ESM ignores NODE_PATH,
// so resolve it through require with the global roots as fallbacks.
export const chromium = (() => {
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

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const SHOTS = join(ROOT, 'e2e', 'screenshots');

/** Chromium flags: fake microphone + auto-granted permission prompt. */
export const CHROMIUM_ARGS = ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'];

// Console/page errors matching these are network-environment noise, not game bugs.
export const IGNORED = [
  /ICE/i,
  /STUN/i,
  /stun:/i,
  /WebRTC/i,
  /RTCPeerConnection/i,
  /ERR_NAME_NOT_RESOLVED/i,
  /ERR_INTERNET_DISCONNECTED/i,
  /ERR_NETWORK_CHANGED/i,
];

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function log(msg) {
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`);
}

export function assert(cond, msg) {
  if (!cond) throw new Error(`Assertion failed: ${msg}`);
}

export function freePort() {
  return new Promise((res, rej) => {
    const s = createServer();
    s.once('error', rej);
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => res(port));
    });
  });
}

export function buildClient() {
  const r = spawnSync('npx', ['vite', 'build'], { cwd: ROOT, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`vite build failed:\n${r.stdout}\n${r.stderr}`);
  assert(existsSync(join(ROOT, 'dist', 'client', 'index.html')), 'dist/client/index.html exists');
}

/**
 * One scenario run: its own steps, warnings, error collection, server and
 * browser contexts. Everything it starts is torn down by cleanup(), also on failure.
 */
export class Scenario {
  constructor(name, browser) {
    this.name = name;
    this.browser = browser;
    this.steps = [];
    this.warnings = [];
    this.ignoredErrors = [];
    this.realErrors = [];
    this.contexts = [];
    this.server = null;
    this.serverOut = '';
    this.url = '';
    mkdirSync(SHOTS, { recursive: true });
  }

  log(msg) {
    log(`[${this.name}] ${msg}`);
  }

  warn(msg) {
    this.warnings.push(msg);
    this.log(`WARN  ${msg}`);
  }

  async step(name, fn) {
    this.log(`STEP  ${name}`);
    const t0 = Date.now();
    try {
      const r = await fn();
      this.steps.push({ name, ok: true, ms: Date.now() - t0 });
      this.log(`PASS  ${name} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
      return r;
    } catch (e) {
      this.steps.push({ name, ok: false, ms: Date.now() - t0, err: e });
      this.log(`FAIL  ${name}: ${e && e.message ? e.message : e}`);
      throw e;
    }
  }

  shot(file) {
    return join(SHOTS, `${this.name}-${file}`);
  }

  /** Start `tsx src/server/main.ts` on a free port with extra env (FT_MIN_PLAYERS, FT_TIME_SCALE...). */
  async startServer(env = {}) {
    const port = await freePort();
    this.server = spawn('npx', ['tsx', 'src/server/main.ts'], {
      cwd: ROOT,
      env: { ...process.env, ...env, PORT: String(port) },
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: true,
    });
    this.server.stdout.on('data', (d) => (this.serverOut += d));
    this.server.stderr.on('data', (d) => (this.serverOut += d));
    const t0 = Date.now();
    while (!/Fake Tower server on/.test(this.serverOut)) {
      if (this.server.exitCode !== null) throw new Error(`server exited early:\n${this.serverOut}`);
      if (Date.now() - t0 > 30000) throw new Error(`server did not start:\n${this.serverOut}`);
      await sleep(100);
    }
    this.url = `http://127.0.0.1:${port}/`;
    this.log(`server: ${this.serverOut.trim().split('\n').at(-1)}`);
    return port;
  }

  stopServer() {
    const s = this.server;
    if (!s || s.exitCode !== null) return;
    try {
      process.kill(-s.pid, 'SIGTERM'); // whole process group (npx -> tsx -> node)
    } catch {
      try {
        s.kill('SIGTERM');
      } catch {
        /* already gone */
      }
    }
  }

  record(who, kind, text) {
    const line = `${who} ${kind}: ${text}`;
    if (IGNORED.some((re) => re.test(text))) this.ignoredErrors.push(line);
    else this.realErrors.push(line);
  }

  /** One browser context + page per name, with error collection. */
  async newPlayers(names) {
    const pages = [];
    for (const name of names) {
      const ctx = await this.browser.newContext({
        viewport: { width: 1280, height: 720 },
        deviceScaleFactor: 1,
        permissions: ['microphone'],
      });
      this.contexts.push(ctx);
      const page = await ctx.newPage();
      page.ftName = name;
      page.on('pageerror', (e) => this.record(name, 'pageerror', e.message));
      page.on('console', (m) => {
        if (m.type() === 'error') this.record(name, 'console.error', m.text());
      });
      pages.push(page);
    }
    return pages;
  }

  /** Host creates a room, everyone else joins by code. Returns the code. */
  async createAndJoin(pages) {
    const [host, ...rest] = pages;
    await host.goto(this.url);
    await host.fill('#name-input', host.ftName);
    await host.waitForFunction(() => window.__ft.state.conn === 'open');
    await host.click('#create-btn');
    await host.waitForSelector('#room-code:not(:empty)');
    const code = (await host.textContent('#room-code')).trim();
    assert(/^[A-Z]{4}$/.test(code), `room code looks like 4 letters, got "${code}"`);
    this.log(`room code ${code}`);
    for (const p of rest) {
      await p.goto(this.url);
      await p.fill('#name-input', p.ftName);
      await p.fill('#join-code', code);
      await p.waitForFunction(() => window.__ft.state.conn === 'open');
      await p.click('#join-btn');
      await p.waitForSelector('#room-code:not(:empty)');
    }
    for (const p of pages) {
      await p.waitForFunction((n) => document.querySelectorAll('.player-list li').length === n, pages.length, { timeout: 10000 });
    }
    return code;
  }

  /** Host clicks start; every page reaches the round view. */
  async startRound(pages) {
    await pages[0].click('#start-btn');
    for (const p of pages) {
      await p.waitForFunction(() => window.__ft.state.view === 'round' && !!window.__ft.state.round, null, { timeout: 15000 });
    }
  }

  /** Split pages by role from client state. */
  async roles(pages) {
    const controllers = [];
    const pilots = [];
    let impostor = null;
    for (const p of pages) {
      const you = await p.evaluate(() => window.__ft.state.round.you);
      if (you.role === 'pilot') pilots.push(p);
      else controllers.push(p);
      if (you.impostor) impostor = p;
    }
    return { controllers, pilots, impostor };
  }

  /** Wait until the end screen is visible on all pages, logging pilot state while waiting. */
  async waitForEnd(pages, pilots, timeoutMs) {
    const t0 = Date.now();
    let lastLog = 0;
    for (;;) {
      const vis = await Promise.all(pages.map((p) => p.locator('#end-screen').isVisible()));
      if (vis.every(Boolean)) return;
      if (Date.now() - t0 > timeoutMs) {
        throw new Error(`round did not end within ${timeoutMs / 1000}s; pilots: ${(await pilotSummaries(pilots)).join(' | ')}`);
      }
      if (Date.now() - lastLog > 10000) {
        lastLog = Date.now();
        this.log(`  waiting... ${(await pilotSummaries(pilots)).join(' | ')}`);
      }
      await sleep(250);
    }
  }

  /** The browser-collected errors (minus known network noise) must be empty. */
  checkErrors() {
    if (this.ignoredErrors.length) {
      this.log(`ignored ${this.ignoredErrors.length} benign WebRTC/ICE/network error(s):`);
      for (const l of [...new Set(this.ignoredErrors)].slice(0, 5)) this.log(`  ignored: ${l}`);
    }
    assert(this.realErrors.length === 0, `unexpected errors:\n  ${this.realErrors.join('\n  ')}`);
  }

  async cleanup() {
    for (const c of this.contexts.splice(0)) {
      try {
        await c.close();
      } catch {
        /* ignore */
      }
    }
    this.stopServer();
  }
}

async function pilotSummaries(pilots) {
  return Promise.all(
    pilots.map(async (p) => {
      if (p.isClosed()) return `${p.ftName} (closed)`;
      try {
        return await p.evaluate(() => {
          const a = window.__ft.state.own?.ac;
          return a ? `${a.callsign} ${a.status} alt=${Math.round(a.indAlt)} vs=${Math.round(a.vs)} dme=${a.dme}` : 'n/a';
        });
      } catch (e) {
        return `${p.ftName} (${e.message.split('\n')[0]})`;
      }
    }),
  );
}

// ---------------------------------------------------------------- cockpit helpers

/** Own aircraft as the client store has it (null before the first 'own'). */
export function ownAc(page) {
  return page.evaluate(() => window.__ft.state.own?.ac ?? null);
}

const KNOB_FIELD = { hdg: 'selHdg', alt: 'selAlt', spd: 'selSpd', baro: 'altSetting' };

/**
 * Type a value into an MCP field (#mcp-hdg/alt/spd/baro) and press Enter, then
 * wait until the server echoes it back in the own-aircraft state. `expect` is the
 * value the server will hold after its own clamping (defaults to `value`).
 */
export async function setKnob(page, knob, value, expect = value) {
  const field = KNOB_FIELD[knob];
  for (let attempt = 0; attempt < 3; attempt++) {
    await page.fill(`#mcp-${knob}`, String(value));
    await page.press(`#mcp-${knob}`, 'Enter');
    try {
      await page.waitForFunction(
        ([f, v]) => window.__ft.state.own?.ac[f] === v || window.__ft.state.own?.ac.status !== 'flying',
        [field, expect],
        { timeout: 4000 },
      );
      return;
    } catch {
      /* retry */
    }
  }
  const ac = await ownAc(page);
  throw new Error(`${page.ftName}: MCP ${knob}=${value} not confirmed by the server (${field}=${ac?.[field]}); ac=${JSON.stringify(ac)}`);
}

/** Click a cockpit control until the server's own-aircraft state has ac[field] === value. */
export async function clickUntil(page, selector, field, value, what) {
  for (let attempt = 0; attempt < 3; attempt++) {
    await page.click(selector);
    try {
      await page.waitForFunction(
        ([f, v]) => {
          const ac = window.__ft.state.own?.ac;
          return !!ac && (ac.status !== 'flying' || ac[f] === v);
        },
        [field, value],
        { timeout: 4000 },
      );
      return;
    } catch {
      /* retry */
    }
  }
  throw new Error(`${page.ftName}: ${what} not confirmed by the server; ac=${JSON.stringify(await ownAc(page))}`);
}

export async function setFlaps(page, n) {
  const ac = await ownAc(page);
  if (ac && ac.flaps === n) return;
  await clickUntil(page, `.flap-btn:nth-child(${n + 1})`, 'flaps', n, `flaps ${n}`);
}

export async function setGear(page, down) {
  const ac = await ownAc(page);
  if (ac && ac.gearDown === down) return;
  await clickUntil(page, '.gear-lever', 'gearDown', down, `gear ${down ? 'down' : 'up'}`);
}

export async function setApp(page, armed) {
  const ac = await ownAc(page);
  if (ac && ac.appArmed === armed) return;
  await clickUntil(page, '.mcp-btn.app', 'appArmed', armed, `APP ${armed ? 'arm' : 'disarm'}`);
}

// ---------------------------------------------------------------- radio indicator

export function waitIndicator(page, re, label, timeout = 8000) {
  return page
    .waitForFunction((src) => new RegExp(src).test(document.getElementById('radio-indicator')?.textContent ?? ''), re.source, { timeout })
    .catch(async () => {
      throw new Error(`${label}: expected #radio-indicator to match ${re}, got "${await page.locator('#radio-indicator').textContent()}"`);
    });
}

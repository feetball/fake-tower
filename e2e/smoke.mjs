// End-to-end tests: builds the client once, then runs each scenario against its
// own real server with headless Chromium players. Requires a global Playwright
// install with Chromium.
//
//   npm run e2e                         all scenarios
//   node e2e/smoke.mjs tower-wins       one scenario (several names allowed)
//   node e2e/smoke.mjs --list           list scenario names
//
// Exit code is non-zero if any step of any selected scenario fails.

import * as impostorWins from './scenarios/impostor-wins.mjs';
import * as towerWins from './scenarios/tower-wins.mjs';
import * as lonePilot from './scenarios/lone-pilot.mjs';
import * as disconnect from './scenarios/disconnect.mjs';
import { CHROMIUM_ARGS, SHOTS, Scenario, buildClient, chromium, log } from './lib.mjs';

const ALL = [impostorWins, towerWins, lonePilot, disconnect];

const args = process.argv.slice(2);
if (args.includes('--list')) {
  for (const s of ALL) console.log(`${s.name.padEnd(16)} ${s.description}`);
  process.exit(0);
}
const unknown = args.filter((a) => !ALL.some((s) => s.name === a));
if (unknown.length) {
  console.error(`Unknown scenario(s): ${unknown.join(', ')}. Known: ${ALL.map((s) => s.name).join(', ')}`);
  process.exit(2);
}
const selected = args.length ? ALL.filter((s) => args.includes(s.name)) : ALL;

const results = [];
let browser = null;
let buildStep = null;
const t0All = Date.now();

try {
  log('STEP  build client (vite build)');
  const tb = Date.now();
  try {
    buildClient();
    buildStep = { ok: true, ms: Date.now() - tb };
    log(`PASS  build client (${((Date.now() - tb) / 1000).toFixed(1)}s)`);
  } catch (e) {
    buildStep = { ok: false, ms: Date.now() - tb, err: e };
    log(`FAIL  build client: ${e.message}`);
    throw e;
  }
  browser = await chromium.launch({ args: CHROMIUM_ARGS });

  for (const mod of selected) {
    const sc = new Scenario(mod.name, browser);
    const t0 = Date.now();
    let ok = true;
    let extra = null;
    log(`==== scenario ${mod.name}: ${mod.description}`);
    try {
      extra = await mod.run(sc);
    } catch (e) {
      ok = false;
      sc.log(`ERROR ${e && e.stack ? e.stack : e}`);
      if (sc.realErrors.length) sc.log(`collected page/console errors:\n  ${sc.realErrors.join('\n  ')}`);
      if (sc.serverOut) sc.log(`server output (tail):\n${sc.serverOut.split('\n').slice(-20).join('\n')}`);
    } finally {
      await sc.cleanup();
    }
    results.push({ name: mod.name, ok, ms: Date.now() - t0, sc, extra });
  }
} catch (e) {
  log(`ERROR ${e && e.stack ? e.stack : e}`);
} finally {
  try {
    await browser?.close();
  } catch {
    /* ignore */
  }
  for (const r of results) r.sc.stopServer();
}

console.log('\n==== e2e summary ====');
if (buildStep) console.log(`${buildStep.ok ? 'PASS' : 'FAIL'}  build client  (${(buildStep.ms / 1000).toFixed(1)}s)`);
for (const r of results) {
  console.log(`\n${r.ok ? 'PASS' : 'FAIL'}  scenario ${r.name}  (${(r.ms / 1000).toFixed(1)}s)`);
  for (const s of r.sc.steps) console.log(`  ${s.ok ? 'PASS' : 'FAIL'}  ${s.name}  (${(s.ms / 1000).toFixed(1)}s)`);
  if (r.extra && 'voiceConnected' in r.extra) console.log(`  WebRTC voice mesh connected in lobby: ${r.extra.voiceConnected ? 'yes' : 'NO'}`);
  for (const w of r.sc.warnings) console.log(`  WARN  ${w}`);
  console.log(`  ignored benign errors: ${r.sc.ignoredErrors.length}; unexpected errors: ${r.sc.realErrors.length}`);
}
const allOk = !!buildStep?.ok && results.length === selected.length && results.every((r) => r.ok);
console.log(`\nScreenshots: ${SHOTS}`);
console.log(`Total ${((Date.now() - t0All) / 1000).toFixed(1)}s`);
console.log(allOk ? 'RESULT: PASS' : 'RESULT: FAIL');
process.exit(allOk ? 0 : 1);

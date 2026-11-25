// 4 players; both pilots are flown through the real cockpit UI by a scripted
// "competent pilot" (e2e/autopilot.mjs) that reads only window.__ft.state.own:
// baro to the ATIS QNH, vectors to an entry point, sequenced ILS intercepts at
// the platform altitude, APP, flaps, gear. Both land -> the tower wins.
// The same autopilot is checked against the sim over hundreds of seeds by
// src/shared/sim/e2e-autopilot.test.ts, so this scenario is not flaky by design.

import { ApproachPilot, assignSequence, panelDiff, position } from '../autopilot.mjs';
import { assert, ownAc, setApp, setFlaps, setGear, setKnob, sleep } from '../lib.mjs';

export const name = 'tower-wins';
export const description = 'both pilots fly the ILS through the cockpit UI and land -> tower wins';
const TIME_SCALE = 20;
const FLIGHT_TIMEOUT_MS = 4 * 60 * 1000; // ~25 sim-minutes at x20; fuel runs out well before that

/** Apply panel differences through the UI, flaps before speed (speed is clamped to the flap minimum). */
async function applyPanel(page, diff) {
  if (diff.altSetting !== undefined) await setKnob(page, 'baro', diff.altSetting);
  if (diff.flaps !== undefined) await setFlaps(page, diff.flaps);
  if (diff.gear !== undefined) await setGear(page, diff.gear);
  if (diff.app !== undefined) await setApp(page, diff.app);
  if (diff.hdg !== undefined) await setKnob(page, 'hdg', diff.hdg);
  if (diff.alt !== undefined) await setKnob(page, 'alt', diff.alt);
  if (diff.spd !== undefined) await setKnob(page, 'spd', diff.spd);
}

function describeAc(ac) {
  if (!ac) return 'no data';
  const { x, y } = position(ac);
  return (
    `${ac.callsign} ${ac.status}${ac.outcome ? `/${ac.outcome}` : ''} pos=(${x.toFixed(1)},${y.toFixed(1)}) ` +
    `dme=${ac.dme} hdg=${ac.hdg} ias=${ac.ias} indAlt=${ac.indAlt} vs=${ac.vs} fuel=${ac.fuelMin} ` +
    `sel=${ac.selHdg}/${ac.selAlt}/${ac.selSpd} baro=${ac.altSetting} mode=${ac.apMode} app=${ac.appArmed} ` +
    `gs=${ac.gsCaptured} gear=${ac.gearDown} flaps=${ac.flaps} loc=${ac.locDev} gsDev=${ac.gsDev} warn=[${ac.warnings}]`
  );
}

export async function run(sc) {
  await sc.step(`start server (x${TIME_SCALE})`, () => sc.startServer({ FT_TIME_SCALE: String(TIME_SCALE) }));
  const names = ['Mia', 'Ned', 'Ola', 'Pat'];
  const pages = await sc.newPlayers(names);
  await sc.step('create room, 4 players join, start', async () => {
    await sc.createAndJoin(pages);
    await sc.startRound(pages);
  });

  const { pilots, impostor } = await sc.roles(pages);
  assert(pilots.length === 2 && impostor, 'two pilots and an impostor');
  const qnh = await pilots[0].evaluate(() => window.__ft.state.round.atis.qnh);
  const flyers = [];

  await sc.step('pilots read the ATIS and set the altimeter to QNH', async () => {
    for (const p of pilots) {
      await p.waitForFunction(() => !!window.__ft.state.own, null, { timeout: 5000 });
      const atisText = await p.evaluate(() => window.__ft.state.round.atis.text);
      assert(atisText.includes(`QNH ${qnh}`), `${p.ftName}: ATIS text carries QNH ${qnh}`);
      await setKnob(p, 'baro', qnh);
    }
    const acs = await Promise.all(pilots.map(ownAc));
    const roles = assignSequence(acs);
    pilots.forEach((p, i) => flyers.push({ page: p, pilot: new ApproachPilot(roles[i], qnh), last: acs[i], phase: '' }));
    for (const f of flyers) sc.log(`${f.page.ftName} ${f.last.callsign} is ${f.pilot.role}: ${describeAc(f.last)}`);
  });

  await sc.step('fly both aircraft to a landing through the cockpit UI', async () => {
    const lead = flyers.find((f) => f.pilot.role === 'lead').pilot;
    const t0 = Date.now();
    let lastLog = 0;
    const dump = () => flyers.map((f) => `\n    ${f.page.ftName} [${f.pilot.role} ${f.pilot.phase}] ${describeAc(f.last)}`).join('');
    for (;;) {
      for (const f of flyers) {
        const ac = await ownAc(f.page);
        f.last = ac;
        if (ac.status === 'crashed') throw new Error(`${ac.callsign} crashed (${ac.outcome}):${dump()}`);
        const { panel, fail } = f.pilot.decide(ac, lead.established);
        if (fail) throw new Error(`${ac.callsign} (${f.pilot.role}): ${fail}:${dump()}`);
        if (f.pilot.phase !== f.phase) {
          f.phase = f.pilot.phase;
          sc.log(`  ${ac.callsign} (${f.pilot.role}) -> ${f.phase}: ${describeAc(ac)}`);
        }
        if (panel) {
          try {
            await applyPanel(f.page, panelDiff(ac, panel));
          } catch (e) {
            throw new Error(`${e.message}:${dump()}`);
          }
        }
      }
      if (flyers.every((f) => f.last.status === 'landed')) break;
      if (Date.now() - t0 > FLIGHT_TIMEOUT_MS) throw new Error(`not both landed within ${FLIGHT_TIMEOUT_MS / 1000}s:${dump()}`);
      if (Date.now() - lastLog > 10000) {
        lastLog = Date.now();
        sc.log(`  flying...${dump()}`);
      }
      await sleep(100);
    }
    sc.log(`both landed:${dump()}`);
  });

  await sc.step('round ends: tower wins, 2 of 2 landed, reveal correct', async () => {
    await sc.waitForEnd(pages, pilots, 30000);
    await sleep(300);
    await pages[0].screenshot({ path: sc.shot('01-end.png') });
    const impId = await impostor.evaluate(() => window.__ft.state.selfId);
    const realPage = (await sc.roles(pages)).controllers.find((p) => p !== impostor);
    const realId = await realPage.evaluate(() => window.__ft.state.selfId);
    for (const p of pages) {
      const end = await p.evaluate(() => window.__ft.state.end);
      assert(end.winner === 'tower', `${p.ftName}: winner tower (got ${end.winner})`);
      assert(end.outcomes.length === 2 && end.outcomes.every((o) => o.outcome === 'landed'), `${p.ftName}: both landed (got ${JSON.stringify(end.outcomes)})`);
      assert(end.impostorId === impId && end.realControllerId === realId, `${p.ftName}: reveal ids match the roles`);
      const banner = (await p.textContent('.end-banner')).trim();
      assert(/TOWER WINS/.test(banner), `${p.ftName}: banner (got "${banner}")`);
      const sub = (await p.textContent('.end-sub')).trim();
      assert(/^2 of 2 aircraft landed/.test(sub), `${p.ftName}: end-sub (got "${sub}")`);
      assert((await p.textContent('.rev.imp .rev-name')).trim() === impostor.ftName, `${p.ftName}: impostor revealed as ${impostor.ftName}`);
      assert((await p.textContent('.rev.real .rev-name')).trim() === realPage.ftName, `${p.ftName}: real tower revealed as ${realPage.ftName}`);
      const you = (await p.textContent('.rev.you .rev-name')).trim();
      assert(you === (p === impostor ? 'LOST' : 'WON'), `${p.ftName}: "You" shows ${you}`);
      const timeline = await p.locator('.end-timeline .tl.landed').count();
      assert(timeline === 2, `${p.ftName}: 2 landed events in the timeline (got ${timeline})`);
    }
  });

  await sc.step('no unexpected page or console errors', () => sc.checkErrors());
}

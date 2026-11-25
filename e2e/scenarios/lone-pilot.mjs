// Reduced roles (FT_MIN_PLAYERS=1): a single player gets a lone pilot round,
// can transmit, crashes, sees the end screen, returns to the lobby and can
// start a second round.

import { assert, setKnob, waitIndicator } from '../lib.mjs';

export const name = 'lone-pilot';
export const description = 'FT_MIN_PLAYERS=1: one lone pilot, round starts, ends, restarts';
const TIME_SCALE = 20;

export async function run(sc) {
  await sc.step(`start server (min players 1, x${TIME_SCALE})`, () =>
    sc.startServer({ FT_MIN_PLAYERS: '1', FT_TIME_SCALE: String(TIME_SCALE) }),
  );
  const [solo] = await sc.newPlayers(['Solo']);

  await sc.step('create a room alone and start', async () => {
    await sc.createAndJoin([solo]);
    assert(await solo.locator('#start-btn').isEnabled(), 'start button enabled with 1 player');
    await sc.startRound([solo]);
  });

  await sc.step('lone pilot: cockpit, no scope, no controllers, own data flows', async () => {
    assert(await solo.locator('#cockpit').isVisible(), 'cockpit visible');
    assert(!(await solo.locator('#scope-canvas').isVisible()), 'scope hidden');
    const info = await solo.evaluate(() => {
      const s = window.__ft.state;
      return { you: s.round.you, players: s.round.players, qnh: s.round.atis.qnh };
    });
    assert(info.you.role === 'pilot' && !info.you.impostor && /^[A-Z]{3}\d+$/.test(info.you.callsign ?? ''), `you=${JSON.stringify(info.you)}`);
    assert(info.players.length === 1 && info.players[0].role === 'pilot', `players=${JSON.stringify(info.players)}`);
    await solo.waitForFunction(() => window.__ft.state.own?.ac.status === 'flying', null, { timeout: 5000 });
    const t1 = await solo.evaluate(() => window.__ft.state.own.time);
    await solo.waitForFunction((t) => window.__ft.state.own.time >= t + 4, t1, { timeout: 5000 });
    sc.log(`sim time advancing (>= 4 s of sim in < 5 s real at x${TIME_SCALE})`);
  });

  await sc.step('push-to-talk works for the lone pilot', async () => {
    await solo.bringToFront();
    await solo.keyboard.down('Space');
    await waitIndicator(solo, /^TX$/, 'Solo');
    await solo.waitForFunction(() => window.__ft.state.radio.length === 1);
    await solo.keyboard.up('Space');
    await waitIndicator(solo, /^IDLE$/, 'Solo after release');
  });

  await sc.step('descend into the ground; round ends with 0 of 1 landed', async () => {
    await setKnob(solo, 'alt', 0);
    await sc.waitForEnd([solo], [solo], 90000);
    const end = await solo.evaluate(() => window.__ft.state.end);
    assert(end.winner === 'impostor', `winner (got ${end.winner})`);
    assert(end.impostorId === '' && end.realControllerId === '', `no controllers (got ${JSON.stringify(end)})`);
    assert(end.outcomes.length === 1 && end.outcomes[0].outcome === 'terrain', `outcome terrain (got ${JSON.stringify(end.outcomes)})`);
    const sub = (await solo.textContent('.end-sub')).trim();
    assert(/^0 of 1 aircraft landed/.test(sub), `end-sub (got "${sub}")`);
    await solo.screenshot({ path: sc.shot('01-end.png') });
  });

  await sc.step('back to the lobby and start a second round', async () => {
    await solo.click('#back-to-lobby');
    await solo.waitForFunction(() => window.__ft.state.view === 'lobby' && !window.__ft.state.end && !window.__ft.state.own);
    await sc.startRound([solo]);
    await solo.waitForFunction(() => window.__ft.state.own?.ac.status === 'flying' && window.__ft.state.events.length === 0, null, { timeout: 5000 });
  });

  await sc.step('no unexpected page or console errors', () => sc.checkErrors());
}

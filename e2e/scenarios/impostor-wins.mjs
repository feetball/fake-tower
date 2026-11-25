// 4 players: lobby, roles, information hiding, push-to-talk and blocking,
// WebRTC connection check, both pilots descend into the ground, impostor wins,
// end screen, return to lobby. The server runs the sim at FT_TIME_SCALE.

import { assert, setKnob, sleep, waitIndicator } from '../lib.mjs';

export const name = 'impostor-wins';
export const description = 'everyone crashes -> impostor wins (4 players, PTT, info hiding)';
const TIME_SCALE = 10;

export async function run(sc) {
  await sc.step(`start server (x${TIME_SCALE})`, () => sc.startServer({ FT_TIME_SCALE: String(TIME_SCALE) }));
  const names = ['Alice', 'Bob', 'Carol', 'Dave'];
  const pages = await sc.newPlayers(names);

  await sc.step('create room and join with 3 other players', () => sc.createAndJoin(pages));

  await sc.step('lobby shows 4 players on every page', async () => {
    for (const p of pages) assert((await p.locator('.player-list li').count()) === 4, `${p.ftName} sees 4 players`);
    await sleep(300);
    await pages[0].screenshot({ path: sc.shot('01-lobby.png') });
  });

  let voiceConnected = false;
  await sc.step('voice: wait for WebRTC peers to connect in the lobby (non-fatal)', async () => {
    const micOk = await Promise.all(pages.map((p) => p.evaluate(() => window.__ft.state.mic.ok)));
    sc.log(`mic ok per page: ${micOk.join(', ')}`);
    if (micOk.some((v) => !v)) sc.warn('fake microphone not available on some pages');
    try {
      await Promise.all(
        pages.map((p) => p.waitForFunction(() => window.__ft.state.mic.connected.length >= 3, null, { timeout: 15000 })),
      );
      voiceConnected = true;
      sc.log('all 4 pages have 3 connected voice peers (full mesh)');
    } catch {
      const counts = await Promise.all(pages.map((p) => p.evaluate(() => window.__ft.state.mic.connected.length)));
      sc.warn(`WebRTC peers did not fully connect within 15s (connected peers per page: ${counts.join(', ')}). Likely no STUN/host-candidate connectivity in this sandbox.`);
    }
  });

  await sc.step('host starts the round', () => sc.startRound(pages));

  const controllers = [];
  const pilots = [];
  await sc.step('roles: 2 controller scopes, 2 pilot cockpits, exactly one impostor banner', async () => {
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
    sc.log(`controllers: ${controllers.map((p) => p.ftName)}; pilots: ${pilots.map((p) => p.ftName)}`);
  });

  await sc.step('pilot client state does not leak impostor identity or radar targets', async () => {
    // let at least one radar sweep go out (2 s of sim time)
    await Promise.all(controllers.map((p) => p.waitForFunction(() => !!window.__ft.state.radar, null, { timeout: 5000 })));
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
    const flags = [];
    for (const p of controllers) {
      const r = await p.evaluate(() => ({ n: window.__ft.state.radar?.targets.length ?? -1, imp: window.__ft.state.round.you.impostor }));
      assert(r.n === 2, `${p.ftName} (controller) sees 2 radar targets (got ${r.n})`);
      flags.push(r.imp);
    }
    assert(flags.filter(Boolean).length === 1, `exactly one controller has you.impostor=true (got ${flags})`);
  });

  await sc.step('screenshots: scope and cockpit (plate, ATIS)', async () => {
    await sleep(500);
    await controllers[0].screenshot({ path: sc.shot('02-scope.png') });
    const pl = pilots[0];
    await pl.screenshot({ path: sc.shot('03-cockpit.png') });
    await pl.keyboard.press('p');
    await pl.waitForSelector('.plate-card', { state: 'visible' });
    await sleep(500);
    await pl.screenshot({ path: sc.shot('04-cockpit-plate.png') });
    await pl.keyboard.press('Escape');
    await pl.keyboard.press('i');
    await pl.waitForSelector('.atis-card', { state: 'visible' });
    await pl.screenshot({ path: sc.shot('05-cockpit-atis.png') });
    await pl.keyboard.press('Escape');
    assert(!(await pl.locator('.atis-card').isVisible()), 'ATIS closed with Escape');
  });

  await sc.step('push-to-talk: Space on one page -> TX there, RX everywhere else', async () => {
    const sender = controllers[0];
    await sender.bringToFront();
    await sender.keyboard.down('Space');
    await waitIndicator(sender, /^TX$/, `${sender.ftName} (sender)`);
    for (const p of pages) if (p !== sender) await waitIndicator(p, /^RX /, `${p.ftName} (listener)`);
    await sender.keyboard.up('Space');
    for (const p of pages) await waitIndicator(p, /^IDLE$/, `${p.ftName} after release`);
  });

  await sc.step('push-to-talk: two keyed at once -> BLOCKED everywhere', async () => {
    const [a, b] = controllers;
    await a.bringToFront();
    await a.keyboard.down('Space');
    await b.bringToFront();
    await b.keyboard.down('Space');
    for (const p of pages) await waitIndicator(p, /^BLOCKED$/, `${p.ftName}`);
    await a.keyboard.up('Space');
    await b.keyboard.up('Space');
    for (const p of pages) await waitIndicator(p, /^IDLE$/, `${p.ftName} after release`);
  });

  await sc.step('voice: report WebRTC status at round time', async () => {
    const counts = await Promise.all(pages.map((p) => p.evaluate(() => window.__ft.state.mic.connected.length)));
    sc.log(`voice peers connected per page: ${counts.join(', ')} (voice connected in lobby: ${voiceConnected})`);
    if (counts.some((c) => c < 3)) sc.warn(`WebRTC voice mesh incomplete during round (${counts.join(', ')} of 3 peers)`);
  });

  await sc.step('descend both pilots to altitude 0 so they crash', async () => {
    for (const p of pilots) {
      await p.bringToFront();
      await setKnob(p, 'alt', 0);
      sc.log(`${p.ftName}: selected altitude 0 confirmed by server`);
    }
  });

  await sc.step('wait for the round to end (#end-screen on all pages)', async () => {
    await sc.waitForEnd(pages, pilots, 120000);
    await sleep(500);
    await pages[0].screenshot({ path: sc.shot('06-end.png') });
  });

  await sc.step('end screen: impostor wins, reveal names shown', async () => {
    for (const p of pages) {
      const banner = (await p.textContent('.end-banner')).trim();
      assert(/IMPOSTOR WINS/.test(banner), `${p.ftName} banner says impostor wins (got "${banner}")`);
      const sub = (await p.textContent('.end-sub')).trim();
      assert(/^0 of 2 aircraft landed/.test(sub), `0 of 2 landed (got "${sub}")`);
      const real = (await p.textContent('.rev.real .rev-name')).trim();
      const imp = (await p.textContent('.rev.imp .rev-name')).trim();
      assert(names.includes(real) && names.includes(imp) && real !== imp, `reveal names real="${real}" impostor="${imp}"`);
      const res = await p.evaluate(() => window.__ft.state.end);
      assert(res.winner === 'impostor', `state.end.winner is impostor (got ${res.winner})`);
      assert(res.outcomes.length === 2 && res.outcomes.every((o) => o.outcome !== 'landed' && o.outcome !== 'flying'), `both outcomes are crashes (got ${res.outcomes.map((o) => o.outcome)})`);
      const rows = await p.locator('.end-table tbody tr').count();
      assert(rows === 2, `end table has 2 rows (got ${rows})`);
    }
    // the revealed impostor must be the controller whose banner said impostor
    const impBannerPage = (await Promise.all(pages.map(async (p) => ((await p.locator('#role-banner.impostor').count()) ? p : null)))).find(Boolean);
    assert(impBannerPage, 'some page kept the impostor banner in the DOM');
    const revealed = (await pages[0].textContent('.rev.imp .rev-name')).trim();
    assert(revealed === impBannerPage.ftName, `revealed impostor (${revealed}) matches the page that was told it was the impostor (${impBannerPage.ftName})`);
  });

  await sc.step('host returns everyone to the lobby', async () => {
    await pages[0].click('#back-to-lobby');
    for (const p of pages) {
      await p.waitForFunction(() => window.__ft.state.view === 'lobby', null, { timeout: 10000 });
      await p.waitForFunction(() => document.querySelectorAll('.player-list li').length === 4);
      assert(await p.locator('#end-screen').isHidden(), `${p.ftName} end screen hidden`);
      assert(await p.locator('#start-btn, #room-code').first().isVisible(), `${p.ftName} lobby visible`);
    }
  });

  await sc.step('no unexpected page or console errors', () => sc.checkErrors());
  return { voiceConnected };
}

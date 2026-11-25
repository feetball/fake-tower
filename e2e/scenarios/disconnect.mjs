// Disconnects: a pilot's page closes mid-round -> the round carries on, the
// others see that player as disconnected, the abandoned aircraft keeps flying
// (and crashes on the descent it was given), the round still ends. Then, in
// the lobby, the host leaves -> host migrates to a remaining player who can start.

import { assert, setKnob, sleep } from '../lib.mjs';

export const name = 'disconnect';
export const description = 'pilot drops mid-round (round continues/ends), host leaves lobby (migrates)';
const TIME_SCALE = 20;

const roomPlayers = (p) => p.evaluate(() => window.__ft.state.room.players);

export async function run(sc) {
  await sc.step(`start server (x${TIME_SCALE})`, () => sc.startServer({ FT_TIME_SCALE: String(TIME_SCALE) }));
  const names = ['Hank', 'Iris', 'Jack', 'Kate'];
  const pages = await sc.newPlayers(names);
  await sc.step('create room, 4 players join, start', async () => {
    await sc.createAndJoin(pages);
    await sc.startRound(pages);
  });

  const { pilots } = await sc.roles(pages);
  // Drop a pilot that is not the host, so host handling stays for the lobby part.
  const leaver = pilots.find((p) => p !== pages[0]) ?? pilots[0];
  const stayer = pilots.find((p) => p !== leaver);
  const others = pages.filter((p) => p !== leaver);
  let leaverId = '';
  let leaverCs = '';

  await sc.step(`${leaver.ftName} (pilot) sets a descent to 0, then closes the page`, async () => {
    const info = await leaver.evaluate(() => ({ id: window.__ft.state.selfId, cs: window.__ft.state.round.you.callsign }));
    leaverId = info.id;
    leaverCs = info.cs;
    await setKnob(leaver, 'alt', 0);
    await leaver.context().close();
  });

  await sc.step('others see the player as disconnected; the round continues', async () => {
    for (const p of others) {
      await p.waitForFunction(
        (id) => window.__ft.state.room?.players.some((q) => q.id === id && !q.connected),
        leaverId,
        { timeout: 10000 },
      );
      const st = await p.evaluate(() => ({ view: window.__ft.state.view, phase: window.__ft.state.room.phase }));
      assert(st.view === 'round' && st.phase === 'playing', `${p.ftName} still in the round (got ${JSON.stringify(st)})`);
      assert((await roomPlayers(p)).length === 4, `${p.ftName}: disconnected player still listed mid-round`);
    }
    const t = await stayer.evaluate(() => window.__ft.state.own.time);
    await stayer.waitForFunction((t0) => window.__ft.state.own.time > t0 + 2, t, { timeout: 5000 });
  });

  await sc.step('remaining pilot descends too; round ends with both aircraft accounted for', async () => {
    await setKnob(stayer, 'alt', 0);
    await sc.waitForEnd(others, [stayer], 90000);
    for (const p of others) {
      const end = await p.evaluate(() => window.__ft.state.end);
      assert(end.outcomes.length === 2, `${p.ftName}: 2 outcomes`);
      const left = end.outcomes.find((o) => o.playerId === leaverId);
      assert(left && left.callsign === leaverCs && left.outcome === 'terrain', `abandoned aircraft ${leaverCs} crashed into terrain (got ${JSON.stringify(left)})`);
      assert(end.winner === 'impostor', `${p.ftName}: impostor wins`);
    }
  });

  await sc.step('back to the lobby: the disconnected player is gone', async () => {
    await pages[0].click('#back-to-lobby');
    for (const p of others) {
      await p.waitForFunction(() => window.__ft.state.view === 'lobby' && document.querySelectorAll('.player-list li').length === 3, null, { timeout: 10000 });
      assert(!(await roomPlayers(p)).some((q) => q.id === leaverId), `${p.ftName}: leaver removed`);
    }
  });

  await sc.step('host leaves the lobby -> host migrates to a remaining player', async () => {
    const host = pages[0];
    const hostId = await host.evaluate(() => window.__ft.state.selfId);
    const rest = others.filter((p) => p !== host);
    await host.context().close();
    for (const p of rest) {
      await p.waitForFunction(
        (hid) => {
          const ps = window.__ft.state.room?.players ?? [];
          return ps.length === 2 && !ps.some((q) => q.id === hid) && ps.filter((q) => q.host).length === 1;
        },
        hostId,
        { timeout: 10000 },
      );
    }
    const states = await Promise.all(rest.map((p) => p.evaluate(() => ({ id: window.__ft.state.selfId, players: window.__ft.state.room.players }))));
    const newHostId = states[0].players.find((q) => q.host).id;
    assert(states.every((s) => s.players.find((q) => q.host).id === newHostId), 'all agree on the new host');
    const newHost = rest[states.findIndex((s) => s.id === newHostId)];
    assert(newHost, 'new host is one of the remaining pages');
    await sleep(200);
    assert(await newHost.locator('#start-btn').isVisible(), `${newHost.ftName} (new host) sees the start button`);
    for (const p of rest.filter((q) => q !== newHost)) {
      assert(!(await p.locator('#start-btn').isVisible()), `${p.ftName} (not host) has no visible start button`);
    }
    sc.log(`host migrated to ${newHost.ftName}`);
  });

  await sc.step('no unexpected page or console errors', () => sc.checkErrors());
}

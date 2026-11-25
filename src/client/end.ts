import type { Actions } from './actions';
import { h, setText, show } from './dom';
import { isHost, playerName, type State } from './store';
import { eventText, mmss, OUTCOME_TEXT } from './text';

export function createEnd(actions: Actions): { el: HTMLElement; render: (s: State) => void } {
  const banner = h('div', { class: 'end-banner' });
  const sub = h('div', { class: 'end-sub' });
  const reveal = h('div', { class: 'end-reveal' });
  const table = h('table', { class: 'end-table' });
  const timeline = h('div', { class: 'end-timeline' });
  const back = h('button', { id: 'back-to-lobby', class: 'btn primary big' }, 'Back to lobby');
  back.addEventListener('click', () => actions.send({ t: 'lobby' }));
  const waitNote = h('div', { class: 'dim small' });
  const el = h(
    'section',
    { id: 'end-screen', class: 'screen end-screen' },
    h('div', { class: 'end-card card' }, banner, sub, reveal, table, h('h4', {}, 'Timeline'), timeline, h('div', { class: 'end-actions' }, back, waitNote)),
  );
  let sig = '';
  const render = (s: State) => {
    const visible = s.view === 'end' && !!s.end;
    show(el, visible);
    if (!visible || !s.end) return;
    const r = s.end;
    const host = isHost();
    show(back, host);
    back.disabled = s.conn !== 'open';
    setText(waitNote, host ? 'Open mic is live again.' : 'Open mic is live again. Waiting for the host to return everyone to the lobby.');
    const nextSig = JSON.stringify(r) + s.events.length + s.selfId;
    if (nextSig === sig) return;
    sig = nextSig;
    const towerWon = r.winner === 'tower';
    const landed = r.outcomes.filter((o) => o.outcome === 'landed').length;
    setText(banner, towerWon ? 'THE TOWER WINS' : 'THE IMPOSTOR WINS');
    banner.className = `end-banner ${towerWon ? 'tower' : 'impostor'}`;
    setText(
      sub,
      `${landed} of ${r.outcomes.length} aircraft landed${towerWon ? ' — more than half made it down.' : ' — not more than half made it down.'}  Round time ${mmss(r.durationSec)}.`,
    );
    const youWon =
      (towerWon && s.selfId !== r.impostorId) || (!towerWon && s.selfId === r.impostorId);
    reveal.replaceChildren(
      h('div', { class: 'rev real' }, h('div', { class: 'rev-label' }, 'Real tower'), h('div', { class: 'rev-name' }, playerName(r.realControllerId))),
      h('div', { class: 'rev imp' }, h('div', { class: 'rev-label' }, 'Impostor'), h('div', { class: 'rev-name' }, playerName(r.impostorId))),
      h('div', { class: `rev you ${youWon ? 'won' : 'lost'}` }, h('div', { class: 'rev-label' }, 'You'), h('div', { class: 'rev-name' }, youWon ? 'WON' : 'LOST')),
    );
    table.replaceChildren(
      h('thead', {}, h('tr', {}, h('th', {}, 'Callsign'), h('th', {}, 'Pilot'), h('th', {}, 'Outcome'))),
      h(
        'tbody',
        {},
        ...r.outcomes.map((o) =>
          h(
            'tr',
            { class: `oc-${o.outcome} ${o.playerId === s.selfId ? 'self' : ''}` },
            h('td', { class: 'mono' }, o.callsign),
            h('td', {}, playerName(o.playerId)),
            h('td', {}, OUTCOME_TEXT[o.outcome] ?? o.outcome),
          ),
        ),
      ),
    );
    timeline.replaceChildren(
      ...(s.events.length
        ? s.events.map((e) => h('div', { class: `tl ${e.kind}` }, h('span', { class: 'mono dim' }, mmss(e.time)), ' ', eventText(e)))
        : [h('div', { class: 'dim small' }, 'No events recorded.')]),
    );
  };
  return { el, render };
}

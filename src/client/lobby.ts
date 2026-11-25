import { MAX_PLAYERS, MIN_PLAYERS } from '../shared/protocol';
import type { Actions } from './actions';
import { h, setText, show, storageGet, storageSet, toast } from './dom';
import { isHost, type State } from './store';

function howToPlay(): HTMLElement {
  return h(
    'div',
    { class: 'howto' },
    h('h3', {}, 'How to play'),
    h(
      'div',
      { class: 'howto-cols' },
      h(
        'div',
        { class: 'howto-col' },
        h('h4', {}, 'Controllers (2)'),
        h(
          'ul',
          {},
          h('li', {}, 'Two players get the radar scope. Both claim to be Fallow Approach.'),
          h('li', {}, 'One is the real tower: vector everyone to the ILS 27 and land them safely.'),
          h(
            'li',
            {},
            'The other is the impostor: wins unless strictly more than half the aircraft land. Below the MSA, wrong QNH, two on the approach at once, endless holding…',
          ),
          h('li', {}, 'Everyone knows who the two controllers are. Only they know which one is real.'),
        ),
      ),
      h(
        'div',
        { class: 'howto-col' },
        h('h4', {}, 'Pilots (2–6)'),
        h(
          'ul',
          {},
          h('li', {}, 'You fly a twin jet in fog through the autopilot panel. No outside view, no traffic display.'),
          h('li', {}, 'Use the ATIS and the approach plate to check every instruction: QNH, MSA, platform altitude 3000.'),
          h('li', {}, 'Only you see your fuel. Declare "minimum fuel" by voice.'),
          h('li', {}, 'Land: on the localizer and glideslope, gear down, flaps 3, 155 kt or less.'),
        ),
      ),
    ),
    h(
      'p',
      { class: 'howto-radio' },
      'One frequency, push-to-talk on ',
      h('kbd', {}, 'Space'),
      '. Two people keying at once block the frequency — nobody hears anything but a squeal.',
    ),
  );
}

export function createLobby(root: HTMLElement, actions: Actions): (s: State) => void {
  const params = new URLSearchParams(location.search);
  const urlRoom = (params.get('room') ?? '').toUpperCase().replace(/[^A-Z]/g, '').slice(0, 4);

  // ---------------------------------------------------------------- menu
  const nameInput = h('input', {
    id: 'name-input',
    type: 'text',
    maxlength: 16,
    placeholder: 'Your name',
    autocomplete: 'nickname',
    spellcheck: 'false',
  });
  nameInput.value = storageGet('ft.name') ?? '';
  const createBtn = h('button', { id: 'create-btn', class: 'btn primary' }, 'Create room');
  const codeInput = h('input', {
    id: 'join-code',
    type: 'text',
    maxlength: 4,
    placeholder: 'CODE',
    autocomplete: 'off',
    spellcheck: 'false',
    class: 'code-input',
  });
  codeInput.value = urlRoom;
  const joinBtn = h('button', { id: 'join-btn', class: 'btn' }, 'Join');
  const connLine = h('div', { class: 'conn-line' });

  const getName = (): string | null => {
    const n = nameInput.value.trim().replace(/\s+/g, ' ');
    if (!n) {
      toast('Enter your name first');
      nameInput.focus();
      return null;
    }
    storageSet('ft.name', n);
    return n;
  };
  createBtn.addEventListener('click', () => {
    const n = getName();
    if (!n) return;
    actions.initAudio();
    actions.create(n);
  });
  const doJoin = () => {
    const n = getName();
    if (!n) return;
    const code = codeInput.value.toUpperCase().replace(/[^A-Z]/g, '');
    if (code.length !== 4) {
      toast('Room codes are 4 letters');
      codeInput.focus();
      return;
    }
    actions.initAudio();
    actions.join(code, n);
  };
  joinBtn.addEventListener('click', doJoin);
  codeInput.addEventListener('input', () => {
    const v = codeInput.value.toUpperCase().replace(/[^A-Z]/g, '').slice(0, 4);
    if (v !== codeInput.value) codeInput.value = v;
  });
  codeInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') doJoin();
  });
  nameInput.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    if (codeInput.value.length === 4) doJoin();
    else createBtn.click();
  });

  const menu = h(
    'div',
    { class: 'menu-card card' },
    h('label', { class: 'field-label', for: 'name-input' }, 'Callsign on the frequency — your name'),
    nameInput,
    h(
      'div',
      { class: 'menu-actions' },
      createBtn,
      h('span', { class: 'or' }, 'or'),
      codeInput,
      joinBtn,
    ),
    urlRoom ? h('div', { class: 'hint' }, `Invited to room ${urlRoom} — enter your name and press Join.`) : null,
    connLine,
  );

  // ---------------------------------------------------------------- lobby
  const roomCode = h('span', { id: 'room-code', class: 'room-code' });
  const inviteLink = h('input', { class: 'invite-link', type: 'text', readonly: true });
  const copyBtn = h('button', { class: 'btn small' }, 'Copy invite link');
  copyBtn.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(inviteLink.value);
      toast('Invite link copied', 'info');
    } catch {
      inviteLink.select();
      document.execCommand('copy');
      toast('Invite link copied', 'info');
    }
  });
  const playerList = h('ul', { class: 'player-list' });
  const countLine = h('div', { class: 'count-line' });
  const startBtn = h('button', { id: 'start-btn', class: 'btn primary big' }, 'Start round');
  startBtn.addEventListener('click', () => actions.send({ t: 'start' }));
  const startReason = h('div', { class: 'start-reason' });
  const micLine = h('div', { class: 'mic-line' });
  const vol = h('input', { type: 'range', min: 0, max: 1, step: 0.01, class: 'vol', 'aria-label': 'Volume' });
  vol.addEventListener('input', () => actions.setVolume(Number(vol.value)));
  const waitingLine = h('div', { class: 'waiting-line' });

  const lobby = h(
    'div',
    { class: 'lobby-card card' },
    h('div', { class: 'room-head' }, h('span', { class: 'room-label' }, 'ROOM'), roomCode),
    h('div', { class: 'invite' }, inviteLink, copyBtn),
    h('div', { class: 'lobby-grid' },
      h('div', {}, h('h3', {}, 'On frequency'), countLine, playerList),
      h(
        'div',
        { class: 'lobby-side' },
        h('h3', {}, 'Audio'),
        micLine,
        h('label', { class: 'vol-row' }, 'Volume ', vol),
        h('p', { class: 'dim small' }, 'Lobby is open mic: everyone hears everyone. In the round you only transmit while holding Space.'),
        h('h3', {}, 'Round'),
        startBtn,
        startReason,
        waitingLine,
      ),
    ),
  );

  const screen = h(
    'section',
    { id: 'screen-lobby', class: 'screen screen-lobby' },
    h(
      'header',
      { class: 'brand' },
      h('div', { class: 'brand-mark' }, h('span', { class: 'brand-sq' }), 'FAKE TOWER'),
      h('div', { class: 'brand-sub' }, 'Two voices on the frequency both claim to be the tower. One is real. One wants you dead.'),
    ),
    menu,
    lobby,
    howToPlay(),
  );
  root.append(screen);

  let lastRoom = '';
  return (s: State) => {
    const inLobbyish = s.view === 'menu' || s.view === 'lobby' || s.view === 'waiting';
    show(screen, inLobbyish);
    if (!inLobbyish) return;
    const inRoom = !!s.room && s.view !== 'menu';
    show(menu, !inRoom);
    show(lobby, inRoom);

    const canSend = s.conn === 'open';
    createBtn.disabled = !canSend;
    joinBtn.disabled = !canSend;
    setText(
      connLine,
      s.conn === 'open' ? 'Connected to server.' : s.conn === 'connecting' ? 'Connecting to server…' : `Disconnected: ${s.closeReason}`,
    );
    connLine.className = `conn-line conn-${s.conn}`;

    if (!inRoom || !s.room) return;
    const room = s.room;
    setText(roomCode, room.code);
    if (lastRoom !== room.code) {
      lastRoom = room.code;
      const url = new URL(location.href);
      url.search = `?room=${room.code}`;
      url.hash = '';
      inviteLink.value = url.toString();
      try {
        history.replaceState(null, '', url.toString());
      } catch {
        /* ignore */
      }
    }
    const connected = room.players.filter((p) => p.connected);
    setText(countLine, `${connected.length} / ${MAX_PLAYERS} players · need ${MIN_PLAYERS} to start`);
    const sig = JSON.stringify(room.players) + s.selfId + s.mic.connected.join();
    if (playerList.dataset.sig !== sig) {
      playerList.dataset.sig = sig;
      playerList.replaceChildren(
        ...room.players.map((p) => {
          const self = p.id === s.selfId;
          const linked = self ? s.mic.ok : s.mic.connected.includes(p.id);
          return h(
            'li',
            { class: `player ${p.connected ? '' : 'gone'} ${self ? 'self' : ''}` },
            h('span', { class: `dot ${linked ? 'on' : ''}`, title: self ? 'Your mic' : 'Voice link' }),
            h('span', { class: 'pname' }, p.name),
            p.host ? h('span', { class: 'badge host' }, 'HOST') : null,
            self ? h('span', { class: 'badge you' }, 'YOU') : null,
            p.connected ? null : h('span', { class: 'badge off' }, 'OFFLINE'),
          );
        }),
      );
    }
    const host = isHost();
    show(startBtn, host);
    const enough = connected.length >= MIN_PLAYERS;
    startBtn.disabled = !host || !enough || s.conn !== 'open' || room.phase !== 'lobby';
    setText(
      startReason,
      !host
        ? ''
        : room.phase !== 'lobby'
          ? 'A round is in progress.'
          : enough
            ? 'Roles are assigned at random when you start.'
            : `Waiting for players: ${connected.length}/${MIN_PLAYERS} (2 controllers + at least 2 pilots).`,
    );
    setText(
      waitingLine,
      s.view === 'waiting'
        ? 'Round in progress — waiting for round data…'
        : host
          ? ''
          : `Waiting for the host (${room.players.find((p) => p.host)?.name ?? '—'}) to start.`,
    );
    setText(
      micLine,
      !s.mic.initDone
        ? 'Microphone: starting…'
        : s.mic.ok
          ? `Microphone: OK · voice links ${s.mic.connected.length}/${Math.max(0, connected.length - 1)}`
          : `Microphone unavailable — receive only · voice links ${s.mic.connected.length}/${Math.max(0, connected.length - 1)}`,
    );
    micLine.className = `mic-line ${s.mic.ok ? 'ok' : s.mic.initDone ? 'bad' : ''}`;
    if (document.activeElement !== vol) vol.value = String(s.volume);
  };
}

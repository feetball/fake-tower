import { WS_PATH, type ClientMsg, type ServerMsg } from '../shared/protocol';

export interface Net {
  send(msg: ClientMsg): void;
  isOpen(): boolean;
}

export function connect(
  onMsg: (m: ServerMsg) => void,
  onOpen: () => void,
  onClose: (reason: string) => void,
): Net {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  const url = `${proto}://${location.host}${WS_PATH}`;
  let ws: WebSocket;
  let closed = false;
  try {
    ws = new WebSocket(url);
  } catch (e) {
    queueMicrotask(() => onClose(`Could not open ${url}`));
    return { send() {}, isOpen: () => false };
  }
  ws.addEventListener('open', onOpen);
  ws.addEventListener('message', (ev) => {
    if (typeof ev.data !== 'string') return;
    let msg: unknown;
    try {
      msg = JSON.parse(ev.data);
    } catch {
      console.warn('bad message', ev.data);
      return;
    }
    if (!msg || typeof msg !== 'object' || typeof (msg as { t?: unknown }).t !== 'string') return;
    onMsg(msg as ServerMsg);
  });
  const fin = (reason: string) => {
    if (closed) return;
    closed = true;
    onClose(reason);
  };
  ws.addEventListener('close', (ev) =>
    fin(ev.reason || (ev.code === 1000 ? 'Connection closed' : `Connection lost (code ${ev.code})`)),
  );
  ws.addEventListener('error', () => fin('Cannot reach the game server'));
  return {
    send(msg) {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
    },
    isOpen: () => ws.readyState === WebSocket.OPEN,
  };
}

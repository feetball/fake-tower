// Entry point: HTTP (static client from dist/client) + WebSocket game server.
//   PORT            listen port (default SERVER_PORT)
//   FT_MIN_PLAYERS  minimum players to start, for local testing (default MIN_PLAYERS)
//   FT_TIME_SCALE   simulation speed multiplier for tests, 1-20 (default 1 = real time).
//                   Each 100 ms tick runs that many fixed 0.1 s sim sub-steps, so the
//                   physics are identical to real time, just compressed (see HubOptions).

import { createReadStream, existsSync, statSync } from 'node:fs';
import { type IncomingMessage, type ServerResponse, createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { WebSocketServer, type WebSocket } from 'ws';
import { MIN_PLAYERS, SERVER_PORT, type ServerMsg, WS_PATH } from '../shared/protocol';
import { type Conn, Hub, type HubOptions, clampTimeScale } from './rooms';

const MAX_MESSAGE_BYTES = 64 * 1024; // SDP offers with candidates fit comfortably

const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.wav': 'audio/wav',
  '.mp3': 'audio/mpeg',
  '.ogg': 'audio/ogg',
  '.wasm': 'application/wasm',
  '.txt': 'text/plain; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
};

function isFile(p: string): boolean {
  try {
    return statSync(p).isFile();
  } catch {
    return false;
  }
}

export function staticHandler(root: string | null) {
  return (req: IncomingMessage, res: ServerResponse): void => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405, { Allow: 'GET, HEAD' }).end();
      return;
    }
    if (!root) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Fake Tower server. No client build found (run `npm run build`, or use `npm run dev`).\n');
      return;
    }
    let pathname: string;
    try {
      pathname = decodeURIComponent(new URL(req.url ?? '/', 'http://x').pathname);
    } catch {
      res.writeHead(400).end();
      return;
    }
    let file = normalize(join(root, pathname));
    if (file !== root && !file.startsWith(root + sep)) {
      res.writeHead(403).end();
      return;
    }
    if (!isFile(file)) {
      // SPA fallback for routes; a missing asset (has an extension) is a real 404.
      if (extname(pathname) && extname(pathname) !== '.html') {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found\n');
        return;
      }
      file = join(root, 'index.html');
      if (!isFile(file)) {
        res.writeHead(404).end();
        return;
      }
    }
    const type = TYPES[extname(file).toLowerCase()] ?? 'application/octet-stream';
    const hashed = file.includes(`${sep}assets${sep}`); // Vite fingerprints these
    res.writeHead(200, {
      'Content-Type': type,
      'Content-Length': statSync(file).size,
      'Cache-Control': hashed ? 'public, max-age=31536000, immutable' : 'no-cache',
      'X-Content-Type-Options': 'nosniff',
    });
    if (req.method === 'HEAD') res.end();
    else createReadStream(file).pipe(res);
  };
}

export interface RunningServer {
  port: number;
  hub: Hub;
  close(): Promise<void>;
}

export function startServer(opts: HubOptions & { port?: number; staticRoot?: string | null } = {}): Promise<RunningServer> {
  const defaultRoot = resolve(fileURLToPath(new URL('../../dist/client', import.meta.url)));
  const root =
    opts.staticRoot !== undefined
      ? opts.staticRoot && resolve(opts.staticRoot)
      : existsSync(defaultRoot)
        ? defaultRoot
        : null;
  const hub = new Hub(opts);
  const http = createServer(staticHandler(root));
  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES });

  http.on('upgrade', (req, socket, head) => {
    const path = new URL(req.url ?? '/', 'http://x').pathname;
    if (path !== WS_PATH) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  });

  wss.on('connection', (ws: WebSocket) => {
    const conn: Conn = {
      send(msg: ServerMsg) {
        if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
      },
    };
    hub.connect(conn);
    ws.on('message', (data, isBinary) => {
      if (isBinary) return conn.send({ t: 'error', msg: 'Binary frames not supported' });
      hub.handle(conn, data.toString());
    });
    ws.on('close', () => hub.disconnect(conn));
    ws.on('error', () => ws.terminate()); // e.g. maxPayload exceeded; 'close' follows
  });

  // Drop dead peers so their PTT and lobby slot are released.
  const alive = new WeakSet<WebSocket>();
  wss.on('connection', (ws: WebSocket) => {
    alive.add(ws);
    ws.on('pong', () => alive.add(ws));
  });
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!alive.has(ws)) ws.terminate();
      else {
        alive.delete(ws);
        ws.ping();
      }
    }
  }, 15000);

  return new Promise((res, rej) => {
    http.once('error', rej);
    http.listen(opts.port ?? SERVER_PORT, () => {
      const port = (http.address() as AddressInfo).port;
      res({
        port,
        hub,
        close: () =>
          new Promise<void>((done) => {
            clearInterval(heartbeat);
            hub.close();
            for (const ws of wss.clients) ws.terminate();
            wss.close();
            http.close(() => done());
            http.closeAllConnections();
          }),
      });
    });
  });
}

const isMain = process.argv[1] !== undefined && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isMain) {
  const envMin = Number(process.env.FT_MIN_PLAYERS);
  const minPlayers = Number.isInteger(envMin) && envMin >= 1 ? envMin : MIN_PLAYERS;
  const port = Number(process.env.PORT ?? SERVER_PORT);
  const timeScale = clampTimeScale(process.env.FT_TIME_SCALE);
  startServer({ port, minPlayers, timeScale }).then(
    (s) =>
      console.log(
        `Fake Tower server on http://localhost:${s.port} (ws ${WS_PATH}, min players ${minPlayers}${timeScale !== 1 ? `, time scale x${timeScale}` : ''})`,
      ),
    (e: unknown) => {
      console.error('Failed to start:', e);
      process.exit(1);
    },
  );
}

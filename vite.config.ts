import { defineConfig } from 'vite';

// Client lives in src/client. In dev, Vite serves it on :5173 and proxies the
// WebSocket to the game server on :8080. In prod, `npm run build` emits
// dist/client, which the game server serves itself.
export default defineConfig({
  root: 'src/client',
  build: { outDir: '../../dist/client', emptyOutDir: true },
  server: {
    port: 5173,
    proxy: { '/ws': { target: 'ws://localhost:8080', ws: true } },
  },
});

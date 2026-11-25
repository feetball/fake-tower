import { defineConfig } from 'vitest/config';

// vite.config.ts roots Vite at src/client; tests live across src/, so vitest gets its own root.
export default defineConfig({
  test: { root: '.', include: ['src/**/*.test.ts'], testTimeout: 20000 },
});

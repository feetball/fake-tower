import { defineConfig } from 'vitest/config';

// vite.config.ts roots Vite at src/client; tests live across src/, so vitest gets its own root.
export default defineConfig({
  test: {
    root: '.',
    include: ['src/**/*.test.ts'],
    testTimeout: 20000,
    coverage: {
      provider: 'v8',
      reporter: ['text-summary', 'text', 'lcov', 'json-summary'],
      reportsDirectory: 'coverage',
      include: ['src/**/*.ts'],
      exclude: [
        'src/**/*.test.ts',
        'src/**/*.d.ts',
        // Canvas / DOM rendering and wiring: not meaningfully testable in node, covered by e2e.
        'src/client/main.ts',
        'src/client/scope.ts',
        'src/client/pfd.ts',
        'src/client/plate.ts',
        'src/client/cockpit.ts',
        'src/client/lobby.ts',
        'src/client/end.ts',
        'src/client/roundbar.ts',
        'src/client/alerts.ts',
        'src/client/dom.ts',
        'src/client/net.ts',
        'src/client/voice/index.ts',
        // Server entrypoint (process bootstrap), exercised by server tests/e2e.
        'src/server/main.ts',
      ],
      // Floors set just below measured values (82.7 stmts/lines, 87.8 branches, 97.4 funcs).
      thresholds: { statements: 95, lines: 95, branches: 90, functions: 97 },
    },
  },
});

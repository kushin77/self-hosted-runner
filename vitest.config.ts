import { defineConfig } from 'vitest/config'

/**
 * P2 Safety: Vitest Configuration
 * TypeScript/JavaScript test framework with 80%+ coverage gates
 * Auto-generated as part of 10X Enhancement Phase 2 deployment
 * Idempotent: Safe to regenerate multiple times
 */
export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['**/*.test.ts', '**/*.spec.ts'],
    exclude: ['node_modules', 'dist', 'build'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      include: ['src/**/*.ts'],
      exclude: [
        'node_modules/',
        'tests/',
        '**/*.test.ts',
        '**/*.spec.ts',
        '**/*.d.ts'
      ],
      all: true,
      lines: 80,
      functions: 80,
      branches: 80,
      statements: 80,
      perFile: true,
      skipFull: false,
      reportOnFailure: true
    },
    setupFiles: ['./tests/setup.ts'],
    reporters: ['default', 'json'],
    outputFile: {
      json: './test-results/vitest-results.json'
    },
    bail: 0,
    silent: false,
    testTimeout: 30000,
    hookTimeout: 30000
  }
})

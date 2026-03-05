import React from 'react';
import { COLORS, COLORS_DARK } from '../theme';
// simple HTML elements are used rather than custom text components

export const RepoFunctions: React.FC = () => {
  const theme = React.useContext<any>(React.createContext('light'));
  const colors = theme === 'light' ? COLORS : COLORS_DARK;

  return (
    <div
      style={{
        flex: 1,
        padding: 24,
        overflowY: 'auto',
        background: colors.bg,
        color: colors.text,
        transition: 'background 0.3s ease, color 0.3s ease',
      }}
    >
      <h1 style={{ fontSize: 24, fontWeight: 800, marginBottom: 12 }}>
        📄 Repository Functions
      </h1>
      <p style={{ fontSize: 13, color: colors.muted, marginBottom: 24 }}>
        This page lists named JavaScript/TypeScript or shell functions that are
        defined anywhere in the repository.  It's a simple index for
        development visibility; the source is kept in
        <code>FUNCTIONS_IN_REPO.md</code> at the repo root.
      </p>

      <strong>Shell helpers</strong>
      <ul>
        <li>
          <code>tests/performance/run-performance-benchmarks.sh</code>:{' '}
          <code>record_result()</code>
        </li>
        <li>
          <code>tests/smoke/run-smoke-tests.sh</code>:{' '}
          <code>run_test()</code>, <code>run_test_timeout()</code>
        </li>
        <li>
          <code>tests/vault-security/run-vault-security-tests.sh</code>:{' '}
          <code>assert_test()</code>, <code>skip_test()</code>
        </li>
        <li>
          <code>tests/integration/provisioner-integration-tests.sh</code>:{' '}
          <code>assert_test()</code>
        </li>
      </ul>

      <strong>Node.js helpers (provisioner-worker)</strong>
      <ul>
        <li>
          <code>services/provisioner-worker/lib/metricsServer.js</code>:{' '}
          <code>startMetricsServer()</code>, <code>stopMetricsServer()</code>,{' '}
          <code>getSummary()</code>
        </li>
        <li>
          <code>services/provisioner-worker/lib/audit.cjs</code>:{' '}
          <code>writeLocal()</code>, <code>log()</code>
        </li>
        <li>
          <code>services/provisioner-worker/lib/logger.js</code>:{' '}
          <code>formatMessage(), log(), error(), warn(), info(), debug(),
          child(), genCorrelationId()</code>
        </li>
        <li>
          <code>services/provisioner-worker/lib/terraform_runner_cli.js</code>:{' '}
          <code>runCommand()</code>
        </li>
      </ul>

      <p style={{ fontSize: 12, color: colors.muted, marginTop: 24 }}>
        &gt; This list is generated manually via repository search and maintained
        &gt; alongside the code. Developers can reference the markdown file for
        &gt; updates or propose enhancements to this page.
      </p>
    </div>
  );
};

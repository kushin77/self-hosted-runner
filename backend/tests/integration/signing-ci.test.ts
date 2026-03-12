import { execFileSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';

// This test is gated and only runs when RUN_SIGNING_CI=1 is set in the CI/staging job.
// It expects `SIGNING_KEY_PATH` to point to a PEM private key file (fetched from GSM
// in the build step). The test signs a small artifact and verifies the signature.

const RUN_SIGNING_CI = process.env.RUN_SIGNING_CI === '1';

describe('Signing CI Integration (staging-only)', () => {
  if (!RUN_SIGNING_CI) {
    it.skip('skipped unless RUN_SIGNING_CI=1', () => {});
    return;
  }

  it('signs and verifies an artifact using ssh-keygen', () => {
    const keyPath = process.env.SIGNING_KEY_PATH;
    if (!keyPath) {
      throw new Error('SIGNING_KEY_PATH must be set in staging CI to run this test');
    }

    if (!fs.existsSync(keyPath)) {
      throw new Error(`Signing key not found at ${keyPath}`);
    }

    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sign-ci-'));
    const artifact = path.join(tmpDir, 'artifact.bin');
    const sig = `${artifact}.sig`;
    const pub = path.join(tmpDir, 'signing_key.pub');

    fs.writeFileSync(artifact, 'integration-test-artifact');

    // Derive public key
    execFileSync('ssh-keygen', ['-y', '-f', keyPath], { stdio: ['ignore', fs.openSync(pub, 'w'), 'inherit'] });

    // Sign artifact
    const signOut = execFileSync('ssh-keygen', ['-Y', 'sign', '-f', keyPath, '-n', 'artifact', artifact]);
    fs.writeFileSync(sig, signOut);

    // Verify
    execFileSync('ssh-keygen', ['-Y', 'verify', '-f', pub, '-s', sig, '-n', 'artifact', artifact]);

    // If we reached here, sign+verify succeeded
    expect(fs.existsSync(sig)).toBe(true);
  }, 120000);
});

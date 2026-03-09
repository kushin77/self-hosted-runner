const core = require('@actions/core');
const fs = require('fs');
const path = require('path');

// Cleanup function: revoke/cleanup credentials after job completion
async function cleanup() {
  try {
    core.info('Cleaning up ephemeral credentials...');

    // Clear cache directory
    const cacheDir = path.join(process.env.RUNNER_TEMP, '.cred-cache');
    if (fs.existsSync(cacheDir)) {
      const files = fs.readdirSync(cacheDir);
      for (const file of files) {
        const filePath = path.join(cacheDir, file);
        fs.unlinkSync(filePath);
      }
      core.info('Credential cache cleared');
    }

    // Clear any temporary credential files
    const tmpDir = process.env.RUNNER_TEMP;
    const credFiles = fs.readdirSync(tmpDir)
      .filter(f => f.match(/cred.*\.tmp|.*\.cred/) || f.startsWith('auth_token'));
    
    for (const file of credFiles) {
      const filePath = path.join(tmpDir, file);
      try {
        fs.unlinkSync(filePath);
      } catch (e) {
        core.debug(`Could not delete ${file}: ${e.message}`);
      }
    }

    if (credFiles.length > 0) {
      core.info(`Cleaned up ${credFiles.length} temporary credential files`);
    }

    core.info('Credential cleanup complete');

  } catch (error) {
    core.warning(`Cleanup warning: ${error.message}`);
  }
}

cleanup();

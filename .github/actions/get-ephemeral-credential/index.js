const core = require('@actions/core');
const exec = require('@actions/exec');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

async function run() {
  try {
    const credentialName = core.getInput('credential-name', { required: true });
    const retrieveFrom = core.getInput('retrieve-from') || 'auto';
    const cacheTtl = parseInt(core.getInput('cache-ttl')) || 300;
    const auditLog = core.getInput('audit-log') === 'true';

    core.info(`Retrieving credential: ${credentialName} (from: ${retrieveFrom})`);

    // Generate audit ID
    const auditId = crypto.randomUUID();
    const timestamp = new Date().toISOString();

    // Check cache first
    const cacheDir = path.join(process.env.RUNNER_TEMP, '.cred-cache');
    const cacheFile = path.join(cacheDir, `${credentialName}.cache`);
    
    let fromCache = false;
    let credentialValue = null;

    if (fs.existsSync(cacheFile)) {
      const cacheData = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
      const cacheAge = (Date.now() - cacheData.timestamp) / 1000;

      if (cacheAge < cacheTtl) {
        core.info(`Found cached credential (age: ${cacheAge.toFixed(0)}s)`);
        credentialValue = cacheData.value;
        fromCache = true;
      } else {
        core.info(`Cache expired (age: ${cacheAge.toFixed(0)}s > ${cacheTtl}s)`);
        fs.unlinkSync(cacheFile);
      }
    }

    // Retrieve credential if not cached
    if (!credentialValue) {
      core.info('Credential not cached or cache expired, retrieving...');
      
      // Call the shell script to retrieve
      let output = '';
      let sourceLayer = 'unknown';

      try {
        const scriptPath = path.join(__dirname, '..', '..', '..', 'scripts', 'credential-manager.sh');
        
        const options = {
          listeners: {
            stdout: (data) => {
              output += data.toString();
            },
            stderr: (data) => {
              core.debug(`[credential-manager] ${data.toString()}`);
            }
          }
        };

        // Export environment variables for the script
        process.env.CREDENTIAL_NAME = credentialName;
        process.env.RETRIEVE_FROM = retrieveFrom;

        await exec.exec('bash', [scriptPath, credentialName, retrieveFrom], options);
        
        credentialValue = output.split('\n')
          .filter(line => line && !line.includes('['))
          .join('')
          .trim();

        if (!credentialValue) {
          throw new Error('Credential retrieval returned empty value');
        }

        // Determine which layer was used (parse from script output or env)
        sourceLayer = process.env.CREDENTIAL_SOURCE_LAYER || retrieveFrom;

      } catch (error) {
        core.setFailed(`Failed to retrieve credential: ${error.message}`);
        return;
      }

      // Cache the credential
      fs.mkdirSync(cacheDir, { recursive: true });
      fs.writeFileSync(cacheFile, JSON.stringify({
        timestamp: Date.now(),
        value: credentialValue,
        source: sourceLayer,
        ttl: cacheTtl
      }), { mode: 0o600 });

      core.info(`Credential retrieved successfully (source: ${sourceLayer})`);
    }

    // Mask the credential in logs
    core.setSecret(credentialValue);

    // Set outputs
    const expiresAt = new Date(Date.now() + cacheTtl * 1000).toISOString();
    core.setOutput('credential', credentialValue);
    core.setOutput('cached', fromCache.toString());
    core.setOutput('expires_at', expiresAt);
    core.setOutput('source_layer', retrieveFrom);
    core.setOutput('audit_id', auditId);

    // Log to audit trail if enabled
    if (auditLog) {
      const auditEntry = {
        timestamp,
        audit_id: auditId,
        credential_name: credentialName,
        source_layer: retrieveFrom,
        from_cache: fromCache,
        actor: process.env.GITHUB_ACTOR,
        workflow: process.env.GITHUB_WORKFLOW,
        job: process.env.GITHUB_JOB,
        run_id: process.env.GITHUB_RUN_ID,
        status: 'success'
      };

      core.info(`Credential access logged: ${auditId}`);
    }

  } catch (error) {
    core.setFailed(`Action failed: ${error.message}`);
  }
}

run();

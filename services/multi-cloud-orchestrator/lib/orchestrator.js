const AWSAdapter = require('../adapters/aws');
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [new winston.transports.Console()]
});

/**
 * Multi-Cloud Runner Orchestrator (MVP)
 * Regional runner pools and regional failover logic
 */
class Orchestrator {
  constructor(config = {}) {
    this.config = config;
    this.adapters = {
      aws: new AWSAdapter(config.aws || { region: 'us-east-1' })
      // gcp: new GCPAdapter(config.gcp || { region: 'us-central1' }) // Roadmap
    };
    this.pools = {
      primary: 'aws',
      secondary: 'aws' // Mocking for MVP until GCP is active
    };
  }

  /**
   * Request a new runner instance from a pool
   * @param {string} regionalPool - Pool to Provision from
   * @param {Object} options - Provisioning options
   * @returns {Promise<Object>} Provisioned instance metadata
   */
  async requestRunner(regionalPool = 'primary', options = {}) {
    const provider = this.pools[regionalPool] || 'aws';
    const adapter = this.adapters[provider];
    
    if (!adapter) throw new Error(`NO_ADAPTER: ${provider}`);
    
    logger.info(`[ORCHESTRATOR] requesting runner from pool: ${regionalPool} (provider: ${provider})`, { options });
    
    try {
      const instance = await adapter.provision(options);
      logger.info(`[ORCHESTRATOR] Successfully provisioned: ${instance.id}`, { instance });
      return instance;
    } catch (err) {
      logger.error(`[ORCHESTRATOR] Failed to provision: ${err.message}`, { regionalPool, provider });
      throw err;
    }
  }

  /**
   * Cleanup / Terminate
   */
  async cleanup(instanceId, provider = 'aws') {
    const adapter = this.adapters[provider];
    if (adapter) return await adapter.terminate(instanceId);
  }
}

module.exports = Orchestrator;

if (require.main === module) {
  const orchestrator = new Orchestrator();
  orchestrator.requestRunner('primary', { tier: 'large' })
    .then(inst => logger.info('[RUNNER_READY]', inst))
    .catch(err => logger.error('[RUNNER_FAILED]', err));
}

const CloudAdapter = require('./base');
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()]
});

/**
 * AWS Cloud Adapter (EC2/EKS Runner Provider)
 */
class AWSAdapter extends CloudAdapter {
  constructor(config = {}) {
    super(config);
    this.region = config.region || 'us-east-1';
  }

  async provision(options = {}) {
    logger.info('[AWS] provisioning instance...', { region: this.region, options });
    
    // MVP Mock for AWS Provisioning
    const instanceId = `i-${Math.random().toString(36).substring(2, 10)}`;
    return {
      id: instanceId,
      provider: 'AWS',
      region: this.region,
      status: 'pending',
      launchedAt: new Date().toISOString()
    };
  }

  async terminate(instanceId) {
    logger.info(`[AWS] terminating instance: ${instanceId}`);
    return { id: instanceId, status: 'shutting-down' };
  }
}

module.exports = AWSAdapter;

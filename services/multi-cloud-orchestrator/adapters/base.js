/**
 * Base Cloud Adapter Interface
 * Defines mandatory methods for multi-cloud runner provisioning
 */
class CloudAdapter {
  constructor(config = {}) {
    this.config = config;
  }

  /**
   * Provision a new runner instance
   * @param {Object} options 
   * @returns {Promise<Object>} Instance details
   */
  async provision(options) {
    throw new Error('NOT_IMPLEMENTED: provision');
  }

  /**
   * Terminate a runner instance
   * @param {string} instanceId 
   */
  async terminate(instanceId) {
    throw new Error('NOT_IMPLEMENTED: terminate');
  }

  /**
   * Get health status 
   */
  async getHealth() {
    return { status: 'OK', adapter: this.constructor.name };
  }
}

module.exports = CloudAdapter;

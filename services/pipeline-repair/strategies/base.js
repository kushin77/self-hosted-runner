/**
 * Base Repair Strategy
 */
class RepairStrategy {
  constructor(name) {
    this.name = name;
  }

  /**
   * Assess if the failure can be repaired by this strategy
   * @param {Object} event - Detailed failure event
   * @returns {number} Confidence score (0-1)
   */
  assess(event) {
    return 0;
  }

  /**
   * Execute repair action
   * @param {Object} event 
   * @returns {Promise<Object>} Repair result
   */
  async execute(event) {
    throw new Error('NOT_IMPLEMENTED');
  }
}

module.exports = RepairStrategy;

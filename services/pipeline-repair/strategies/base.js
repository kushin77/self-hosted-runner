class RepairStrategy {
  constructor(name) {
    this.name = name;
  }

  assess(event) {
    return 0;
  }

  async execute(event) {
    throw new Error('NOT_IMPLEMENTED');
  }
}

module.exports = RepairStrategy;

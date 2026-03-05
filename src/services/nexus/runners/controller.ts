/**
 * EIQ Nexus Runner Controller - Multi-Cloud Orchestration logic
 */

import { RunnerProvider, AWSProvider, K8sProvider } from './providers';

export class RunnerController {
  private providers: RunnerProvider[] = [AWSProvider, K8sProvider];

  async getCapableProviders(labels: string[]): Promise<RunnerProvider[]> {
    return this.providers.filter(p => p.isCapableOf(labels));
  }

  async scalePool(labels: string[], targetCount: number) {
    const providers = await this.getCapableProviders(labels);
    if (!providers.length) throw new Error("No providers capable of handling those labels");
    
    // Split the load based on provider capacity (Simplified)
    console.log(`Scaling up ${targetCount} runners for labels: ${labels.join(', ')}`);
    for (const p of providers) {
      await p.provision(targetCount); // Simplified for MVP
    }
  }
}

export const nexusRunnerController = new RunnerController();

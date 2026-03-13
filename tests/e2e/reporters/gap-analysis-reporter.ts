import {
  FullConfig,
  FullResult,
  Reporter,
  Suite,
  TestCase,
  TestResult,
} from '@playwright/test/reporter';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Gap Analysis Reporter for Playwright
 * Generates coverage reports based on test results
 */
class GapAnalysisReporter implements Reporter {
  private results: Map<string, TestCase> = new Map();
  private testToSpecMap: Map<string, string> = new Map();

  constructor() {
    // Map test IDs to spec item IDs
    this.testToSpecMap.set('credentials.spec.ts', 'api-credentials');
  }

  onBegin(config: FullConfig, suite: Suite) {
    console.log('🔍 Starting Gap Analysis Reporter...');
    console.log(`  Total tests: ${suite.allTests().length}`);
  }

  onTestBegin(test: TestCase, result: TestResult) {
    this.results.set(test.id, test);
  }

  onTestEnd(test: TestCase, result: TestResult) {
    // Track test results for gap analysis
    const specId = this.mapTestToSpec(test);
    if (specId) {
      console.log(`  ✓ ${specId}: ${test.title}`);
    }
  }

  onEnd(result: FullResult) {
    console.log('\n📊 Gap Analysis Complete');
    
    // Generate gap analysis data
    const gapData = this.generateGapData();
    
    // Write gap analysis JSON
    const outputPath = path.join(process.cwd(), 'tests/e2e/reports/gap-analysis-data.json');
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, JSON.stringify(gapData, null, 2));
    console.log(`  Gap analysis data written to: ${outputPath}`);
  }

  /**
   * Map test case to specification item ID
   */
  private mapTestToSpec(test: TestCase): string | null {
    const testFile = path.basename(test.location.file);
    
    // Map based on test file and title
    if (testFile === 'credentials.spec.ts') {
      if (test.title.includes('list')) return 'api-credentials-list';
      if (test.title.includes('create')) return 'api-credentials-create';
      if (test.title.includes('retrieve') || test.title.includes('get')) return 'api-credentials-get';
      if (test.title.includes('update')) return 'api-credentials-update';
      if (test.title.includes('delete')) return 'api-credentials-delete';
      if (test.title.includes('rotate')) return 'api-credentials-rotate';
      if (test.title.includes('history')) return 'api-credentials-rotations';
      if (test.title.includes('audit')) return 'api-audit-list';
    }
    
    return null;
  }

  /**
   * Generate gap analysis data
   */
  private generateGapData() {
    const testedSpecs = new Set<string>();
    
    for (const [testId, test] of this.results) {
      const specId = this.mapTestToSpec(test);
      if (specId) {
        testedSpecs.add(specId);
      }
    }

    return {
      timestamp: new Date().toISOString(),
      totalTests: this.results.size,
      testedSpecs: Array.from(testedSpecs),
    };
  }
}

export default GapAnalysisReporter;

import * as fs from 'fs';
import * as path from 'path';

export interface SpecItem {
  id: string;
  name: string;
  category: string;
  description: string;
  testStatus?: 'complete' | 'partial' | 'untested' | 'missing';
  testId?: string;
}

export interface Scorecard {
  itemId: string;
  name: string;
  category: string;
  status: 'complete' | 'partial' | 'untested' | 'missing';
  coveredBy: string[];
  gaps: string[];
}

export interface GapAnalysisReport {
  summary: {
    completeItems: number;
    partialItems: number;
    unterstedItems: number;
    missingItems: number;
  };
  coverage: {
    apis: number;
    clis: number;
    uis: number;
    overall: number;
  };
  criticalGaps: Array<{ itemId: string; reason: string }>;
  recommendations: string[];
}

export default class GapAnalysisGenerator {
  private apiEndpoints: SpecItem[];
  private cliFunctions: SpecItem[];
  private uiElements: SpecItem[];

  constructor(
    apiEndpoints: SpecItem[] = [],
    cliFunctions: SpecItem[] = [],
    uiElements: SpecItem[] = []
  ) {
    this.apiEndpoints = apiEndpoints;
    this.cliFunctions = cliFunctions;
    this.uiElements = uiElements;
  }

  /**
   * Generate scorecards from specification inventory
   */
  generateScorecards(): Scorecard[] {
    const scorecards: Scorecard[] = [];

    // Process API endpoints
    for (const api of this.apiEndpoints) {
      scorecards.push({
        itemId: api.id,
        name: api.name,
        category: 'api',
        status: api.testStatus || 'untested',
        coveredBy: api.testId ? [api.testId] : [],
        gaps: this.identifyGaps(api),
      });
    }

    // Process CLI functions
    for (const cli of this.cliFunctions) {
      scorecards.push({
        itemId: cli.id,
        name: cli.name,
        category: 'cli',
        status: cli.testStatus || 'untested',
        coveredBy: cli.testId ? [cli.testId] : [],
        gaps: this.identifyGaps(cli),
      });
    }

    // Process UI elements
    for (const ui of this.uiElements) {
      scorecards.push({
        itemId: ui.id,
        name: ui.name,
        category: 'ui',
        status: ui.testStatus || 'untested',
        coveredBy: ui.testId ? [ui.testId] : [],
        gaps: this.identifyGaps(ui),
      });
    }

    return scorecards;
  }

  /**
   * Identify gaps for a specification item
   */
  private identifyGaps(item: SpecItem): string[] {
    const gaps: string[] = [];

    if (!item.testStatus || item.testStatus === 'untested') {
      gaps.push(`No test coverage for ${item.name}`);
    } else if (item.testStatus === 'partial') {
      gaps.push(`Partial test coverage - needs more scenarios`);
    } else if (item.testStatus === 'missing') {
      gaps.push(`Missing implementation for ${item.name}`);
    }

    return gaps;
  }

  /**
   * Generate the full gap analysis report
   */
  generateGapAnalysisReport(scorecards: Scorecard[]): GapAnalysisReport {
    const summary = {
      completeItems: scorecards.filter(s => s.status === 'complete').length,
      partialItems: scorecards.filter(s => s.status === 'partial').length,
      unterstedItems: scorecards.filter(s => s.status === 'untested').length,
      missingItems: scorecards.filter(s => s.status === 'missing').length,
    };

    const total = scorecards.length || 1;
    const coverage = {
      apis: this.calculateCategoryCoverage(scorecards, 'api'),
      clis: this.calculateCategoryCoverage(scorecards, 'cli'),
      uis: this.calculateCategoryCoverage(scorecards, 'ui'),
      overall: (summary.completeItems / total) * 100,
    };

    const criticalGaps = scorecards
      .filter(s => s.status === 'missing' || s.status === 'untested')
      .slice(0, 20)
      .map(s => ({
        itemId: s.itemId,
        reason: s.gaps[0] || 'No test coverage',
      }));

    const recommendations: string[] = [];
    if (summary.unterstedItems > 0) {
      recommendations.push(`Add tests for ${summary.unterstedItems} untested items`);
    }
    if (summary.missingItems > 0) {
      recommendations.push(`Implement ${summary.missingItems} missing features`);
    }
    if (summary.partialItems > 0) {
      recommendations.push(`Expand test coverage for ${summary.partialItems} partially tested items`);
    }
    if (coverage.overall < 50) {
      recommendations.push('Critical: Test coverage is below 50% - prioritize test creation');
    }

    return { summary, coverage, criticalGaps, recommendations };
  }

  /**
   * Calculate coverage percentage for a category
   */
  private calculateCategoryCoverage(scorecards: Scorecard[], category: string): number {
    const categoryCards = scorecards.filter(s => s.category === category);
    if (categoryCards.length === 0) return 0;
    const complete = categoryCards.filter(s => s.status === 'complete').length;
    return (complete / categoryCards.length) * 100;
  }

  /**
   * Export report as HTML
   */
  exportHTMLReport(scorecards: Scorecard[], outputPath: string): void {
    const report = this.generateGapAnalysisReport(scorecards);
    const html = this.generateHTML(report, scorecards);
    fs.writeFileSync(outputPath, html, 'utf-8');
  }

  /**
   * Export report as JSON
   */
  exportJSONReport(scorecards: Scorecard[], outputPath: string): void {
    const report = this.generateGapAnalysisReport(scorecards);
    fs.writeFileSync(outputPath, JSON.stringify(report, null, 2), 'utf-8');
  }

  /**
   * Export report as CSV
   */
  exportCSVReport(scorecards: Scorecard[], outputPath: string): void {
    const headers = 'Item ID,Name,Category,Status,Covered By,Gaps\n';
    const rows = scorecards
      .map(s => `${s.itemId},"${s.name}",${s.category},${s.status},"${s.coveredBy.join('; ')}","${s.gaps.join('; ')}"`)
      .join('\n');
    fs.writeFileSync(outputPath, headers + rows, 'utf-8');
  }

  /**
   * Generate HTML report
   */
  private generateHTML(report: GapAnalysisReport, scorecards: Scorecard[]): string {
    return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Gap Analysis Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
    .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
    h1 { color: #333; }
    .summary { display: flex; gap: 20px; margin: 20px 0; }
    .summary-card { flex: 1; padding: 20px; background: #f0f0f0; border-radius: 8px; text-align: center; }
    .summary-card h3 { margin: 0 0 10px 0; }
    .summary-card .value { font-size: 32px; font-weight: bold; }
    .coverage { margin: 20px 0; }
    .coverage-bar { height: 30px; background: #e0e0e0; border-radius: 15px; overflow: hidden; }
    .coverage-fill { height: 100%; background: #4caf50; transition: width 0.3s; }
    .gaps { margin: 20px 0; }
    .gap-item { padding: 10px; margin: 5px 0; background: #ffebee; border-left: 4px solid #f44336; }
    .recommendations { margin: 20px 0; }
    .recommendation { padding: 10px; margin: 5px 0; background: #e8f5e9; border-left: 4px solid #4caf50; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
    th { background: #f5f5f5; }
  </style>
</head>
<body>
  <div class="container">
    <h1>📊 Gap Analysis Report</h1>
    
    <div class="summary">
      <div class="summary-card">
        <h3>Complete</h3>
        <div class="value" style="color: #4caf50;">${report.summary.completeItems}</div>
      </div>
      <div class="summary-card">
        <h3>Partial</h3>
        <div class="value" style="color: #ff9800;">${report.summary.partialItems}</div>
      </div>
      <div class="summary-card">
        <h3>Untested</h3>
        <div class="value" style="color: #2196f3;">${report.summary.unterstedItems}</div>
      </div>
      <div class="summary-card">
        <h3>Missing</h3>
        <div class="value" style="color: #f44336;">${report.summary.missingItems}</div>
      </div>
    </div>

    <div class="coverage">
      <h2>Coverage</h2>
      <p>Overall: ${report.coverage.overall.toFixed(1)}%</p>
      <div class="coverage-bar">
        <div class="coverage-fill" style="width: ${report.coverage.overall}%"></div>
      </div>
      <p>APIs: ${report.coverage.apis.toFixed(1)}% | CLIs: ${report.coverage.clis.toFixed(1)}% | UIs: ${report.coverage.uis.toFixed(1)}%</p>
    </div>

    ${report.criticalGaps.length > 0 ? `
    <div class="gaps">
      <h2>Critical Gaps (${report.criticalGaps.length})</h2>
      ${report.criticalGaps.map(g => `<div class="gap-item">${g.itemId}: ${g.reason}</div>`).join('')}
    </div>
    ` : ''}

    ${report.recommendations.length > 0 ? `
    <div class="recommendations">
      <h2>Recommendations</h2>
      ${report.recommendations.map(r => `<div class="recommendation">${r}</div>`).join('')}
    </div>
    ` : ''}

    <h2>All Items</h2>
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Name</th>
          <th>Category</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        ${scorecards.map(s => `
        <tr>
          <td>${s.itemId}</td>
          <td>${s.name}</td>
          <td>${s.category}</td>
          <td>${s.status}</td>
        </tr>
        `).join('')}
      </tbody>
    </table>
  </div>
</body>
</html>
    `.trim();
  }
}

#!/usr/bin/env python3
"""
Interactive reclassification report generator for milestone organizer.

Generates an HTML report from classification JSON showing:
- Milestone assignments and scores
- Issue details, confidence levels, and keywords matched
- Top unassigned issues (low confidence)
- Summary statistics
"""

import json
import sys
import os
from datetime import datetime
from typing import Dict, List, Any

def generate_html_report(classification_file: str, output_file: str = "milestone-organizer-report.html") -> str:
    """Generate HTML report from classification JSON."""
    
    if not os.path.exists(classification_file):
        print(f"ERROR: Classification file not found: {classification_file}", file=sys.stderr)
        sys.exit(1)
    
    with open(classification_file, 'r') as f:
        data = json.load(f)
    
    # Extract data
    assignments = data.get('assignments', {})
    unassigned = data.get('unassigned', [])
    stats = data.get('stats', {})
    timestamp = data.get('timestamp', 'unknown')
    
    # Build HTML
    html_parts = [
        "<!DOCTYPE html>",
        "<html>",
        "<head>",
        "  <meta charset='utf-8'>",
        "  <meta name='viewport' content='width=device-width, initial-scale=1'>",
        "  <title>Milestone Organizer Report</title>",
        "  <style>",
        "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f5f5f5; margin: 0; padding: 20px; }",
        "    .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); padding: 30px; }",
        "    h1 { color: #1f2937; margin: 0 0 10px 0; }",
        "    .timestamp { color: #6b7280; font-size: 0.9em; }",
        "    .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin: 30px 0; }",
        "    .stat-card { background: #f0f9ff; border-left: 4px solid #3b82f6; padding: 15px; border-radius: 4px; }",
        "    .stat-value { font-size: 2em; font-weight: bold; color: #3b82f6; }",
        "    .stat-label { color: #6b7280; font-size: 0.9em; margin-top: 5px; }",
        "    .milestone-group { margin: 30px 0; border: 1px solid #e5e7eb; border-radius: 4px; }",
        "    .milestone-header { background: #f3f4f6; padding: 15px; border-bottom: 1px solid #e5e7eb; font-weight: 600; color: #1f2937; }",
        "    .issues-list { padding: 15px; }",
        "    .issue-item { border: 1px solid #e5e7eb; padding: 15px; margin: 10px 0; border-radius: 4px; background: #fafafa; }",
        "    .issue-number { font-weight: 600; color: #0066cc; }",
        "    .issue-title { margin: 5px 0; color: #1f2937; }",
        "    .issue-score { display: inline-block; background: #dbeafe; color: #1e40af; padding: 2px 8px; border-radius: 4px; font-size: 0.85em; margin: 5px 0; }",
        "    .unassigned-section { margin: 30px 0; border: 2px solid #fca5a5; border-radius: 4px; background: #fef2f2; padding: 20px; }",
        "    .unassigned-header { font-size: 1.2em; font-weight: 600; color: #991b1b; margin-bottom: 15px; }",
        "    .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #e5e7eb; color: #6b7280; font-size: 0.85em; }",
        "  </style>",
        "</head>",
        "<body>",
        "  <div class='container'>",
        f"    <h1>🎯 Milestone Organizer Report</h1>",
        f"    <div class='timestamp'>Generated {timestamp}</div>",
    ]
    
    # Stats cards
    html_parts.append("    <div class='stats'>")
    html_parts.append(f"      <div class='stat-card'><div class='stat-value'>{stats.get('total_issues', 0)}</div><div class='stat-label'>Total Issues</div></div>")
    html_parts.append(f"      <div class='stat-card'><div class='stat-value'>{stats.get('assigned', 0)}</div><div class='stat-label'>Assigned</div></div>")
    html_parts.append(f"      <div class='stat-card'><div class='stat-value'>{stats.get('unassigned', 0)}</div><div class='stat-label'>Unassigned</div></div>")
    html_parts.append(f"      <div class='stat-card'><div class='stat-value'>{stats.get('milestones_count', 0)}</div><div class='stat-label'>Milestones</div></div>")
    html_parts.append("    </div>")
    
    # Milestone groups
    html_parts.append("    <h2>📊 Assignments by Milestone</h2>")
    for milestone, issues in sorted(assignments.items()):
        html_parts.append(f"    <div class='milestone-group'>")
        html_parts.append(f"      <div class='milestone-header'>{milestone} ({len(issues)} issues)</div>")
        html_parts.append(f"      <div class='issues-list'>")
        
        for issue in issues[:50]:  # Limit to top 50 per milestone
            score = issue.get('score', 'N/A')
            html_parts.append(f"        <div class='issue-item'>")
            html_parts.append(f"          <div><span class='issue-number'>#{issue.get('number')}</span></div>")
            html_parts.append(f"          <div class='issue-title'>{issue.get('title')}</div>")
            html_parts.append(f"          <div><span class='issue-score'>Score: {score}</span></div>")
            html_parts.append(f"        </div>")
        
        if len(issues) > 50:
            html_parts.append(f"        <div style='color: #6b7280; font-size: 0.9em; padding: 10px;'>... and {len(issues) - 50} more</div>")
        
        html_parts.append(f"      </div>")
        html_parts.append(f"    </div>")
    
    # Unassigned section
    if unassigned:
        html_parts.append("    <div class='unassigned-section'>")
        html_parts.append(f"      <div class='unassigned-header'>⚠️ {len(unassigned)} Unassigned Issues (Score < {stats.get('min_score', 2)})</div>")
        html_parts.append("      <div class='issues-list'>")
        
        for issue in unassigned[:20]:  # Top 20 unassigned
            html_parts.append(f"        <div class='issue-item' style='background:#fefce8;'>")
            html_parts.append(f"          <div><span class='issue-number'>#{issue.get('number')}</span></div>")
            html_parts.append(f"          <div class='issue-title'>{issue.get('title')}</div>")
            html_parts.append(f"        </div>")
        
        if len(unassigned) > 20:
            html_parts.append(f"        <div style='color: #92400e; font-size: 0.9em; padding: 10px;'>... and {len(unassigned) - 20} more</div>")
        
        html_parts.append("      </div>")
        html_parts.append("    </div>")
    
    # Footer
    html_parts.append("    <div class='footer'>")
    html_parts.append("      <p>Generated by Milestone Organizer v2")
    html_parts.append(f"      <br>Min confidence score: {stats.get('min_score', 2)}")
    html_parts.append(f"      <br>Batch assignment enabled: {stats.get('batch_mode', False)}</p>")
    html_parts.append("    </div>")
    
    html_parts.extend([
        "  </div>",
        "</body>",
        "</html>"
    ])
    
    # Write report
    html_content = "\n".join(html_parts)
    with open(output_file, 'w') as f:
        f.write(html_content)
    
    return output_file


if __name__ == '__main__':
    classification_file = sys.argv[1] if len(sys.argv) > 1 else "artifacts/milestones-assignments/classification.json"
    output_file = sys.argv[2] if len(sys.argv) > 2 else "milestone-organizer-report.html"
    
    try:
        result = generate_html_report(classification_file, output_file)
        print(f"✓ Report generated: {result}")
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

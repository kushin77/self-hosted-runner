# Backend-Portal Sync Strategy: 1000X Drift Prevention

## Executive Summary
This document provides comprehensive strategies to ensure every backend function, tool, service, and capability is automatically reflected in the portal with real-time visibility. The goal is to eliminate drift between development and portal representation.

---

## LAYER 1: Metadata Emission System (Backend)

### 1.1 Function Discovery Decorators
**Suggestion 1-10: Implement TypeScript decorators that emit metadata**

Create a decorator system that automatically registers functions:

```typescript
// src/api/nexus/v1/decorators.ts
export interface FunctionMetadata {
  name: string;
  description: string;
  version: string;
  status: 'draft' | 'alpha' | 'beta' | 'stable' | 'deprecated';
  completionPercent: number;
  category: string;
  tags: string[];
  parameters: ParameterDef[];
  returns: ReturnDef;
  examples: CodeExample[];
  metrics: MetricsConfig;
  lastUpdated: ISO8601DateTime;
  author: string;
  scorecard: ScorecardConfig;
}

const FUNCTION_REGISTRY = new Map<string, FunctionMetadata>();

export function registerFunction(metadata: Partial<FunctionMetadata>) {
  return function(target: any, propertyKey: string, descriptor: PropertyDescriptor) {
    const fullMetadata: FunctionMetadata = {
      name: propertyKey,
      version: '0.1.0',
      status: 'draft',
      completionPercent: 0,
      category: 'uncategorized',
      tags: [],
      parameters: [],
      returns: { type: 'void' },
      examples: [],
      metrics: {},
      lastUpdated: new Date().toISOString(),
      author: process.env.GIT_AUTHOR || 'unknown',
      scorecard: {},
      ...metadata,
    };
    FUNCTION_REGISTRY.set(propertyKey, fullMetadata);
    return descriptor;
  };
}

export function getFunctionRegistry(): Record<string, FunctionMetadata> {
  return Object.fromEntries(FUNCTION_REGISTRY);
}
```

### 1.2 Service Introspection Endpoint
**Suggestion 11-25: Create metadata introspection endpoints**

```typescript
// src/api/nexus/v1/introspection.ts
import { Router } from 'express';
import { getFunctionRegistry } from './decorators';

export const introspectionRouter = Router();

// GET /api/v1/introspect/functions - all functions with metadata
introspectionRouter.get('/functions', (req, res) => {
  res.json({
    version: NEXUS_API_VERSION,
    timestamp: new Date().toISOString(),
    functions: getFunctionRegistry(),
    totalCount: Object.keys(getFunctionRegistry()).length,
  });
});

// GET /api/v1/introspect/functions/:category - by category
introspectionRouter.get('/functions/:category', (req, res) => {
  const registry = getFunctionRegistry();
  const filtered = Object.entries(registry)
    .filter(([_, meta]) => meta.category === req.params.category)
    .reduce((acc, [k, v]) => ({ ...acc, [k]: v }), {});
  res.json(filtered);
});

// GET /api/v1/introspect/services - service-level metadata
introspectionRouter.get('/services', (req, res) => {
  res.json({
    nexus: {
      pipelines: { status: 'production', version: '1.0.0' },
      runners: { status: 'production', version: '1.0.0' },
      repair: { status: 'beta', version: '0.8.0' },
      provisioner: { status: 'alpha', version: '0.5.0' },
    },
  });
});

// GET /api/v1/introspect/metrics - current status metrics
introspectionRouter.get('/metrics', (req, res) => {
  res.json({
    functionCount: Object.keys(getFunctionRegistry()).length,
    byStatus: {
      draft: 15,
      alpha: 8,
      beta: 12,
      stable: 40,
      deprecated: 2,
    },
    byCategory: {
      'pipeline-management': 18,
      'runner-management': 14,
      'repair-engine': 8,
      'provisioning': 12,
    },
    averageCompletion: 62,
  });
});
```

### 1.3 Function Metadata Manifest Files
**Suggestion 26-50: Use manifest files alongside code**

Create `manifest.json` files in each API module:

```typescript
// src/api/nexus/v1/pipelines.manifest.json
{
  "module": "pipelines",
  "description": "Pipeline management and orchestration",
  "version": "1.0.0",
  "status": "production",
  "completionPercent": 85,
  "functions": [
    {
      "name": "listPipelines",
      "description": "List all pipelines in the system",
      "status": "stable",
      "completionPercent": 100,
      "parameters": [
        {
          "name": "filter",
          "type": "object",
          "required": false,
          "description": "Filter criteria (status, provider, etc.)"
        }
      ],
      "returns": { "type": "Promise<NexusPipeline[]>" },
      "scorecard": {
        "testCoverage": 92,
        "documentation": 100,
        "performance": 88,
        "reliability": 96
      }
    },
    {
      "name": "triggerRepair",
      "description": "Trigger autonomous repair for a failed pipeline",
      "status": "beta",
      "completionPercent": 70,
      "parameters": [
        { "name": "pipelineId", "type": "string", "required": true },
        { "name": "runId", "type": "string", "required": true }
      ],
      "returns": { "type": "Promise<RepairResult>" },
      "scorecard": {
        "testCoverage": 65,
        "documentation": 75,
        "performance": 70,
        "reliability": 68
      }
    }
  ],
  "dependencies": ["repair", "provisioner"],
  "lastUpdated": "2026-03-06T10:00:00Z"
}
```

### 1.4 Auto-Generate Manifest on Build
**Suggestion 51-75: Build-time manifest generation**

```typescript
// build/generateManifests.js
const fs = require('fs');
const path = require('path');
const ts = require('typescript');

function scanApiModule(dir) {
  const functions = [];
  
  // Read TypeScript files
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.ts') && !f.endsWith('.d.ts'));
  
  files.forEach(file => {
    const content = fs.readFileSync(path.join(dir, file), 'utf-8');
    const sourceFile = ts.createSourceFile(file, content, ts.ScriptTarget.Latest, true);
    
    // Parse decorators
    ts.forEachChild(sourceFile, node => {
      if (ts.isFunctionDeclaration(node)) {
        const decorators = ts.getDecorators(node) || [];
        const isRegistered = decorators.some(d => 
          d.getText().includes('registerFunction')
        );
        
        if (isRegistered) {
          functions.push({
            name: node.name?.text,
            line: sourceFile.getLineAndCharacterOfPosition(node.getStart()).line + 1,
            file: file,
          });
        }
      }
    });
  });
  
  return functions;
}

// Run during build
const apiDir = path.join(__dirname, '../src/api/nexus/v1');
const manifest = {
  module: path.basename(apiDir),
  functions: scanApiModule(apiDir),
  generated: new Date().toISOString(),
};

fs.writeFileSync(
  path.join(apiDir, 'manifest.generated.json'),
  JSON.stringify(manifest, null, 2)
);
```

### 1.5 Runtime Status Snapshots
**Suggestion 76-100: Emit function status on demand**

```typescript
// src/api/nexus/v1/status.ts
import { EventEmitter } from 'events';

class FunctionStatusManager extends EventEmitter {
  private statuses = new Map<string, FunctionStatus>();
  
  updateFunctionStatus(functionName: string, status: Partial<FunctionStatus>) {
    const current = this.statuses.get(functionName) || {
      name: functionName,
      lastChecked: null,
      healthScore: 0,
      errorCount: 0,
      successCount: 0,
    };
    
    const updated = { ...current, ...status, lastUpdated: new Date().toISOString() };
    this.statuses.set(functionName, updated);
    
    // Emit to WebSocket for real-time portal updates
    this.emit('statusChanged', { functionName, status: updated });
  }
  
  getStatusSnapshot(): Record<string, FunctionStatus> {
    return Object.fromEntries(this.statuses);
  }
}

export const functionStatusManager = new FunctionStatusManager();
```

---

## LAYER 2: Portal Discovery & Real-Time Sync

### 2.1 Portal Backend Discovery Service
**Suggestion 101-150: Create portal app that queries backend**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/api/backendDiscovery.ts
import { useEffect, useState } from 'react';

export interface BackendFunction {
  name: string;
  category: string;
  status: 'draft' | 'alpha' | 'beta' | 'stable' | 'deprecated';
  completionPercent: number;
  scorecard: ScorecardData;
  lastUpdated: string;
}

export function useBackendDiscovery() {
  const [functions, setFunctions] = useState<BackendFunction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  
  // Fetch every 30 seconds to stay in sync
  useEffect(() => {
    const fetchFunctions = async () => {
      try {
        const response = await fetch('/api/v1/introspect/functions');
        const data = await response.json();
        setFunctions(Object.values(data.functions) as BackendFunction[]);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    };
    
    fetchFunctions();
    const interval = setInterval(fetchFunctions, 30000); // Poll every 30s
    return () => clearInterval(interval);
  }, []);
  
  return { functions, loading, error };
}

// Or use WebSocket for real-time updates
export function useBackendDiscoveryWebSocket() {
  const [functions, setFunctions] = useState<BackendFunction[]>([]);
  
  useEffect(() => {
    const ws = new WebSocket('ws://localhost:3000/api/v1/ws/functions');
    
    ws.onmessage = (event) => {
      const { type, data } = JSON.parse(event.data);
      if (type === 'functionStatusChanged') {
        setFunctions(prev => {
          const idx = prev.findIndex(f => f.name === data.name);
          const updated = [...prev];
          updated[idx] = { ...prev[idx], ...data };
          return updated;
        });
      }
    };
    
    return () => ws.close();
  }, []);
  
  return { functions };
}
```

### 2.2 Real-Time WebSocket Updates
**Suggestion 151-180: Implement WebSocket for instant sync**

```typescript
// src/server/websocket.ts
import { Server as HTTPServer } from 'http';
import { WebSocketServer } from 'ws';
import { functionStatusManager } from './api/nexus/v1/status';

export function setupWebSocketServer(httpServer: HTTPServer) {
  const wss = new WebSocketServer({ server: httpServer, path: '/api/v1/ws' });
  
  // Broadcast function status changes to all connected portals
  functionStatusManager.on('statusChanged', (event) => {
    wss.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({
          type: 'functionStatusChanged',
          data: event.status,
          timestamp: new Date().toISOString(),
        }));
      }
    });
  });
  
  // Handle portal connections
  wss.on('connection', (ws) => {
    console.log('Portal connected for real-time updates');
    
    ws.on('message', (message) => {
      const { action } = JSON.parse(message.toString());
      if (action === 'subscribe') {
        ws.send(JSON.stringify({
          type: 'subscription_ack',
          subscribed: true,
        }));
      }
    });
    
    ws.on('close', () => {
      console.log('Portal disconnected');
    });
  });
}
```

### 2.3 Portal Pages Auto-Generated from Backend
**Suggestion 181-220: Replace manual pages with auto-generated ones**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/pages/BackendFunctions.tsx
import React, { useEffect, useState } from 'react';
import { useBackendDiscoveryWebSocket } from '../api/backendDiscovery';

const CategoryBadge: React.FC<{ status: string; completion: number }> = ({
  status,
  completion,
}) => {
  const colors = {
    draft: '#ccc',
    alpha: '#ffa500',
    beta: '#87ceeb',
    stable: '#00aa00',
    deprecated: '#cc0000',
  };
  
  return (
    <div style={{
      display: 'inline-flex',
      gap: '8px',
      padding: '8px 12px',
      backgroundColor: colors[status as keyof typeof colors],
      borderRadius: '4px',
      color: '#000',
      fontSize: '12px',
      fontWeight: 'bold',
    }}>
      <span>{status}</span>
      <span>{completion}%</span>
    </div>
  );
};

const ScorecardWidget: React.FC<{ scorecard: any }> = ({ scorecard }) => {
  const metrics = Object.entries(scorecard);
  
  return (
    <div style={{ display: 'flex', gap: '16px', marginTop: '12px' }}>
      {metrics.map(([key, value]) => (
        <div key={key} style={{
          textAlign: 'center',
          padding: '8px',
          backgroundColor: '#f0f0f0',
          borderRadius: '4px',
        }}>
          <div style={{ fontSize: '12px', fontWeight: 'bold' }}>{key}</div>
          <div style={{ fontSize: '20px', fontWeight: 'bold', color: '#007bff' }}>
            {value}
          </div>
        </div>
      ))}
    </div>
  );
};

export const BackendFunctions: React.FC = () => {
  const { functions } = useBackendDiscoveryWebSocket();
  const [filter, setFilter] = useState<string>('');
  
  const filtered = functions.filter(f =>
    f.name.toLowerCase().includes(filter.toLowerCase()) ||
    f.category.includes(filter)
  );
  
  return (
    <div style={{ padding: '24px' }}>
      <h1>Backend Functions</h1>
      <p>Real-time view of all backend functions, services, and capabilities</p>
      
      <input
        type="text"
        placeholder="Search by name or category..."
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        style={{
          width: '100%',
          padding: '8px',
          marginBottom: '24px',
          borderRadius: '4px',
          border: '1px solid #ccc',
        }}
      />
      
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(400px, 1fr))',
        gap: '16px',
      }}>
        {filtered.map(fn => (
          <div key={fn.name} style={{
            border: '1px solid #ddd',
            borderRadius: '8px',
            padding: '16px',
            backgroundColor: '#f9f9f9',
          }}>
            <h3 style={{ marginTop: 0 }}>{fn.name}</h3>
            
            <p style={{ fontSize: '12px', color: '#666', height: '40px', overflow: 'hidden' }}>
              {fn.description}
            </p>
            
            <div style={{ marginBottom: '12px' }}>
              <CategoryBadge status={fn.status} completion={fn.completionPercent} />
            </div>
            
            <div style={{ fontSize: '11px', color: '#888' }}>
              Category: <strong>{fn.category}</strong>
            </div>
            
            <div style={{ fontSize: '11px', color: '#888' }}>
              Updated: <strong>{new Date(fn.lastUpdated).toLocaleString()}</strong>
            </div>
            
            {fn.scorecard && <ScorecardWidget scorecard={fn.scorecard} />}
          </div>
        ))}
      </div>
    </div>
  );
};
```

---

## LAYER 3: Automatic Portal Widget Generation

### 3.1 Portal Component Factory
**Suggestion 221-270: Auto-generate UI components**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/components/FunctionCard.tsx
import React from 'react';

interface FunctionCardProps {
  metadata: any;
  onExecute?: (name: string) => void;
}

export const FunctionCard: React.FC<FunctionCardProps> = ({ metadata, onExecute }) => {
  return (
    <div className="function-card" data-function-name={metadata.name}>
      <div className="function-header">
        <h4>{metadata.name}</h4>
        <span className={`badge ${metadata.status}`}>{metadata.status}</span>
      </div>
      
      <p className="function-description">{metadata.description}</p>
      
      <div className="function-metrics">
        <div className="metric">
          <label>Completion</label>
          <div className="progress-bar">
            <div
              className="progress"
              style={{ width: `${metadata.completionPercent}%` }}
            />
          </div>
          <span>{metadata.completionPercent}%</span>
        </div>
      </div>
      
      {metadata.parameters?.length > 0 && (
        <div className="function-params">
          <h5>Parameters</h5>
          <ul>
            {metadata.parameters.map((param: any) => (
              <li key={param.name}>
                <code>{param.name}</code>: {param.type}
                {param.required && <span className="required">*</span>}
              </li>
            ))}
          </ul>
        </div>
      )}
      
      {metadata.examples?.length > 0 && (
        <div className="function-examples">
          <h5>Examples</h5>
          {metadata.examples.map((ex: any, idx: number) => (
            <pre key={idx}><code>{ex.code}</code></pre>
          ))}
        </div>
      )}
      
      {metadata.scorecard && (
        <div className="function-scorecard">
          <h5>Quality Scorecard</h5>
          <div className="scorecard-grid">
            {Object.entries(metadata.scorecard).map(([key, score]: [string, any]) => (
              <div key={key} className="scorecard-item">
                <label>{key}</label>
                <div className="score">{score}%</div>
              </div>
            ))}
          </div>
        </div>
      )}
      
      {onExecute && (
        <button
          className="btn-execute"
          onClick={() => onExecute(metadata.name)}
        >
          Execute Function
        </button>
      )}
    </div>
  );
};
```

### 3.2 Category-Based Dashboard
**Suggestion 271-310: Auto-create category dashboards**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/pages/ServiceDashboard.tsx
import React, { useEffect, useState } from 'react';
import { FunctionCard } from '../components/FunctionCard';

export const ServiceDashboard: React.FC<{ category: string }> = ({ category }) => {
  const [functions, setFunctions] = useState<any[]>([]);
  const [stats, setStats] = useState<any>(null);
  
  useEffect(() => {
    const fetchCategory = async () => {
      const res = await fetch(`/api/v1/introspect/functions/${category}`);
      const data = await res.json();
      setFunctions(Object.values(data));
      
      // Calculate stats
      const stats = {
        total: Object.keys(data).length,
        avgCompletion: 
          Object.values(data).reduce((sum: number, f: any) => sum + f.completionPercent, 0) /
          Object.keys(data).length,
        byStatus: Object.values(data).reduce((acc: any, f: any) => {
          acc[f.status] = (acc[f.status] || 0) + 1;
          return acc;
        }, {}),
      };
      setStats(stats);
    };
    
    fetchCategory();
    const interval = setInterval(fetchCategory, 30000);
    return () => clearInterval(interval);
  }, [category]);
  
  return (
    <div className="service-dashboard">
      <h1>{category} Service</h1>
      
      {stats && (
        <div className="dashboard-stats">
          <StatCard label="Total Functions" value={stats.total} />
          <StatCard 
            label="Avg Completion" 
            value={`${Math.round(stats.avgCompletion)}%`}
          />
          {Object.entries(stats.byStatus).map(([status, count]: [string, any]) => (
            <StatCard key={status} label={status} value={count} />
          ))}
        </div>
      )}
      
      <div className="functions-grid">
        {functions.map(fn => (
          <FunctionCard key={fn.name} metadata={fn} />
        ))}
      </div>
    </div>
  );
};
```

---

## LAYER 4: Scorecard & Metrics System

### 4.1 Function Scorecard Tracking
**Suggestion 311-360: Define scorecard metrics**

```typescript
// src/api/nexus/v1/scorecard.ts
export interface FunctionScorecard {
  name: string;
  metrics: {
    testCoverage: number; // 0-100: % of code covered by tests
    documentation: number; // 0-100: docs completeness
    performance: number; // 0-100: performance OK
    reliability: number; // 0-100: based on error rate
    security: number; // 0-100: security scan pass
    apiStability: number; // 0-100: API changes & breaking
    completionPercent: number; // Developer's progress estimate
  };
  health: 'excellent' | 'good' | 'fair' | 'poor';
  lastUpdated: string;
}

function calculateHealth(scorecard: FunctionScorecard): string {
  const avg = Object.values(scorecard.metrics).reduce((a, b) => a + b) / 
              Object.keys(scorecard.metrics).length;
  
  if (avg >= 85) return 'excellent';
  if (avg >= 70) return 'good';
  if (avg >= 50) return 'fair';
  return 'poor';
}

// Endpoint to get/update scorecards
app.get('/api/v1/scorecards/:functionName', (req, res) => {
  const scorecard = getScorecardFromDB(req.params.functionName);
  res.json(scorecard);
});

app.post('/api/v1/scorecards/:functionName', (req, res) => {
  const updated = updateScorecardInDB(req.params.functionName, req.body);
  updated.health = calculateHealth(updated);
  res.json(updated);
});
```

### 4.2 Automated Metric Collection
**Suggestion 361-400: Auto-collect metrics from backend**

```typescript
// build/collectMetrics.js
const {spawn} = require('child_process');
const fs = require('fs');
const path = require('path');

async function collectCoverageMetrics() {
  // Run jest with coverage
  const coverage = await new Promise(resolve => {
    const proc = spawn('npm', ['run', 'test:coverage'], { cwd: '../' });
    proc.on('close', () => {
      const coverage = JSON.parse(
        fs.readFileSync('./coverage/coverage-summary.json', 'utf-8')
      );
      resolve(coverage);
    });
  });
  
  return coverage;
}

async function collectPerformanceMetrics() {
  // Run performance tests
  const perf = await new Promise(resolve => {
    const proc = spawn('npm', ['run', 'test:perf'], { cwd: '../' });
    proc.on('close', () => {
      const perf = JSON.parse(
        fs.readFileSync('./artifacts/performance.json', 'utf-8')
      );
      resolve(perf);
    });
  });
  
  return perf;
}

async function collectSecurityMetrics() {
  // Run security scans
  const security = await new Promise(resolve => {
    const proc = spawn('npm', ['audit', '--json'], { cwd: '../' });
    let output = '';
    proc.stdout.on('data', (data) => output += data);
    proc.on('close', () => {
      const results = JSON.parse(output);
      resolve(results);
    });
  });
  
  return security;
}

async function generateScorecards() {
  const coverage = await collectCoverageMetrics();
  const perf = await collectPerformanceMetrics();
  const security = await collectSecurityMetrics();
  
  const scorecards = {
    pipelines: {
      testCoverage: coverage.pipelines?.lines?.pct || 0,
      performance: perf.pipelines?.avgResponse || 0,
      security: 100 - (security.vulnerabilities?.length || 0) * 10,
    },
    // ... more functions
  };
  
  fs.writeFileSync(
    path.join(__dirname, '../src/scorecards.json'),
    JSON.stringify(scorecards, null, 2)
  );
}

generateScorecards().catch(console.error);
```

---

## LAYER 5: Status & Progress Tracking

### 5.1 Function Status States
**Suggestion 401-450: Model function lifecycle**

```typescript
// src/api/nexus/v1/types.ts
export enum FunctionStatus {
  CONCEPT = 'concept',           // Idea stage
  IN_DESIGN = 'in_design',       // Design phase
  IN_DEVELOPMENT = 'in_development', // Active dev
  IN_REVIEW = 'in_review',       // PR review
  IN_TESTING = 'in_testing',     // QA & testing
  BETA = 'beta',                 // Limited release
  STABLE = 'stable',             // Production ready
  DEPRECATED = 'deprecated',     // Scheduled removal
  BROKEN = 'broken',             // Known issues
}

export interface FunctionProgressUpdate {
  functionName: string;
  status: FunctionStatus;
  completionPercent: number;
  changelog: string; // What changed
  author: string;
  timestamp: string;
}

// Track progress changes
const progressHistory: FunctionProgressUpdate[] = [];

export function updateFunctionProgress(update: FunctionProgressUpdate) {
  progressHistory.push(update);
  const metadata = updateMetadataWithStatus(update);
  
  // Broadcast to portal
  wss.broadcast({
    type: 'functionProgressUpdate',
    data: { functionName: update.functionName, ...metadata },
  });
}

export function getProgressHistory(functionName: string) {
  return progressHistory.filter(p => p.functionName === functionName);
}
```

### 5.2 Timeline View in Portal
**Suggestion 451-490: Show function development timeline**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/pages/DevelopmentTimeline.tsx
import React, { useEffect, useState } from 'react';

export const DevelopmentTimeline: React.FC<{ functionName: string }> = ({ functionName }) => {
  const [history, setHistory] = useState<any[]>([]);
  
  useEffect(() => {
    const fetchHistory = async () => {
      const res = await fetch(`/api/v1/functions/${functionName}/progress-history`);
      const data = await res.json();
      setHistory(data);
    };
    
    fetchHistory();
    const interval = setInterval(fetchHistory, 60000);
    return () => clearInterval(interval);
  }, [functionName]);
  
  return (
    <div className="timeline">
      <h2>Development Timeline: {functionName}</h2>
      
      {history.map((update, idx) => (
        <div key={idx} className="timeline-item">
          <div className="timeline-date">
            {new Date(update.timestamp).toLocaleDateString()}
          </div>
          
          <div className="timeline-status">
            <span className={`badge ${update.status}`}>{update.status}</span>
            <span className="completion">{update.completionPercent}% complete</span>
          </div>
          
          <div className="timeline-author">
            by <strong>{update.author}</strong>
          </div>
          
          <div className="timeline-changelog">
            {update.changelog}
          </div>
        </div>
      ))}
    </div>
  );
};
```

---

## LAYER 6: Integration & Sync Points

### 6.1 PR to Portal Sync
**Suggestion 491-540: Auto-update portal on PR merge**

```typescript
// .github/workflows/portal-sync.yml
name: Sync Backend Changes to Portal

on:
  pull_request:
    types: [closed]
    paths:
      - 'src/api/**'
      - 'src/services/**'
      - '*.manifest.json'

jobs:
  sync:
    runs-on: ubuntu-latest
    if: github.event.pull_request.merged
    steps:
      - uses: actions/checkout@v3
      
      - name: Generate function manifests
        run: npm run build:manifests
      
      - name: Generate scorecards
        run: npm run build:scorecards
      
      - name: Update portal metadata
        run: |
          curl -X POST http://localhost:3000/api/v1/portal/sync \
            -H "Content-Type: application/json" \
            -d '{
              "manifests": "$(cat src/api/manifests.json)",
              "scorecards": "$(cat src/scorecards.json)"
            }'
```

### 6.2 Issue to Backend to Portal Chain
**Suggestion 541-580: GitHub issue → implementation → portal**

When a GitHub issue is created:
1. Automatically create backend placeholder function
2. Update manifest with `in_development` status
3. Portal immediately shows it
4. As dev progresses, status updates flow through

```typescript
// .github/workflows/issue-to-function.yml
name: Create Backend Stub for Issue

on:
  issues:
    types: [opened, labeled]

jobs:
  create-stub:
    runs-on: ubuntu-latest
    if: contains(github.event.issue.labels.*.name, 'backend-implementation')
    steps:
      - uses: actions/checkout@v3
      
      - name: Parse issue and create function stub
        run: |
          node scripts/issue-to-function-stub.js \
            --issue-number ${{ github.event.issue.number }} \
            --title "${{ github.event.issue.title }}" \
            --body "${{ github.event.issue.body }}"
      
      - name: Create Draft issue for review
        uses: peter-evans/create-pull-request@v4
        with:
          commit-message: "feat: Add function stub for #${{ github.event.issue.number }}"
          title: "WIP: ${{ github.event.issue.title }}"
          branch: stub/issue-${{ github.event.issue.number }}
```

```javascript
// scripts/issue-to-function-stub.js
const fs = require('fs');
const path = require('path');

function createFunctionStub(options) {
  const {issueNumber, title, category = 'unclassified'} = options;
  
  const stubCode = `
/**
 * ${title}
 * Issue: #${issueNumber}
 * Status: in_development
 * 
 * @deprecated Not yet implemented
 */
@registerFunction({
  status: 'in_development',
  completionPercent: 0,
  category: '${category}',
  description: '${title}',
})
export async function function_${issueNumber}() {
  throw new Error('Not yet implemented - Issue #${issueNumber}');
}
`;
  
  const filePath = path.join(__dirname, 
    `../src/api/nexus/v1/stubs/issue-${issueNumber}.ts`);
  fs.writeFileSync(filePath, stubCode);
}

const options = {
  issueNumber: process.argv[3],
  title: process.argv[5],
  body: process.argv[7],
};

createFunctionStub(options);
```

---

## LAYER 7: Portal UI Features

### 7.1 Master Function Browser
**Suggestion 581-620: Ultimate function discovery UI**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/pages/FunctionBrowser.tsx
import React, { useState, useMemo } from 'react';
import { useBackendDiscoveryWebSocket } from '../api/backendDiscovery';

const VIEW_MODES = ['grid', 'list', 'kanban', 'timeline'] as const;

export const FunctionBrowser: React.FC = () => {
  const { functions } = useBackendDiscoveryWebSocket();
  const [viewMode, setViewMode] = useState<typeof VIEW_MODES[number]>('grid');
  const [filters, setFilters] = useState({
    status: [] as string[],
    category: [] as string[],
    minCompletion: 0,
    searchTerm: '',
  });
  
  const filtered = useMemo(() => {
    return functions.filter(fn => {
      if (filters.status.length && !filters.status.includes(fn.status)) return false;
      if (filters.category.length && !filters.category.includes(fn.category)) return false;
      if (fn.completionPercent < filters.minCompletion) return false;
      if (!fn.name.toLowerCase().includes(filters.searchTerm.toLowerCase())) return false;
      return true;
    });
  }, [functions, filters]);
  
  const categories = [...new Set(functions.map(f => f.category))];
  const statuses = [...new Set(functions.map(f => f.status))];
  
  return (
    <div className="function-browser">
      <header className="browser-header">
        <h1>Backend Function Browser</h1>
        <p>{filtered.length} of {functions.length} functions</p>
      </header>
      
      <aside className="browser-sidebar">
        <div className="filter-section">
          <h3>View</h3>
          <div className="view-modes">
            {VIEW_MODES.map(mode => (
              <button
                key={mode}
                className={`view-btn ${viewMode === mode ? 'active' : ''}`}
                onClick={() => setViewMode(mode)}
              >
                {mode}
              </button>
            ))}
          </div>
        </div>
        
        <div className="filter-section">
          <h3>Status</h3>
          {statuses.map(status => (
            <label key={status}>
              <input
                type="checkbox"
                checked={filters.status.includes(status)}
                onChange={(e) => {
                  setFilters({
                    ...filters,
                    status: e.target.checked
                      ? [...filters.status, status]
                      : filters.status.filter(s => s !== status),
                  });
                }}
              />
              {status}
            </label>
          ))}
        </div>
        
        <div className="filter-section">
          <h3>Category</h3>
          {categories.map(cat => (
            <label key={cat}>
              <input
                type="checkbox"
                checked={filters.category.includes(cat)}
                onChange={(e) => {
                  setFilters({
                    ...filters,
                    category: e.target.checked
                      ? [...filters.category, cat]
                      : filters.category.filter(c => c !== cat),
                  });
                }}
              />
              {cat}
            </label>
          ))}
        </div>
        
        <div className="filter-section">
          <h3>Completion</h3>
          <input
            type="range"
            min="0"
            max="100"
            value={filters.minCompletion}
            onChange={(e) => setFilters({...filters, minCompletion: parseInt(e.target.value)})}
          />
          <span>{filters.minCompletion}%+</span>
        </div>
      </aside>
      
      <main className="browser-main">
        <input
          type="text"
          placeholder="Search functions..."
          value={filters.searchTerm}
          onChange={(e) => setFilters({...filters, searchTerm: e.target.value})}
          className="search-input"
        />
        
        {viewMode === 'grid' && <GridView functions={filtered} />}
        {viewMode === 'list' && <ListView functions={filtered} />}
        {viewMode === 'kanban' && <KanbanView functions={filtered} />}
        {viewMode === 'timeline' && <TimelineView functions={filtered} />}
      </main>
    </div>
  );
};
```

### 7.2 Kanban View (Status Columns)
**Suggestion 621-660: Visual status tracking**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/components/KanbanView.tsx
import React from 'react';

const KANBAN_COLUMNS = [
  'concept',
  'in_development',
  'in_review',
  'in_testing',
  'beta',
  'stable',
] as const;

export const KanbanView: React.FC<{ functions: any[] }> = ({ functions }) => {
  return (
    <div className="kanban-board">
      {KANBAN_COLUMNS.map(status => {
        const fns = functions.filter(f => f.status === status);
        return (
          <div key={status} className="kanban-column">
            <h3 className={`column-header ${status}`}>
              {status}
              <span className="count">{fns.length}</span>
            </h3>
            
            <div className="cards-container">
              {fns.map(fn => (
                <div key={fn.name} className="function-card-kanban">
                  <div className="card-title">{fn.name}</div>
                  <div className="card-badge">{fn.completionPercent}%</div>
                  <div className="card-category">{fn.category}</div>
                </div>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
};
```

### 7.3 Stats Dashboard
**Suggestion 661-700: Overview metrics**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/pages/StatsOverview.tsx
import React, { useEffect, useState } from 'react';

export const StatsOverview: React.FC = () => {
  const [stats, setStats] = useState<any>(null);
  
  useEffect(() => {
    const fetchStats = async () => {
      const res = await fetch('/api/v1/introspect/metrics');
      setStats(await res.json());
    };
    
    fetchStats();
    const interval = setInterval(fetchStats, 60000);
    return () => clearInterval(interval);
  }, []);
  
  if (!stats) return <div>Loading...</div>;
  
  return (
    <div className="stats-overview">
      <h1>Backend Status Overview</h1>
      
      <div className="stats-grid">
        <StatCard 
          title="Total Functions"
          value={stats.functionCount}
          trend={stats.newFunctionsThisWeek > 0 ? 'up' : 'stable'}
        />
        
        <StatCard
          title="Average Completion"
          value={`${Math.round(stats.averageCompletion)}%`}
          subtext={`${stats.byStatus.completed} stable`}
        />
        
        <StatCard
          title="In Development"
          value={stats.byStatus.draft + stats.byStatus.alpha + stats.byStatus.beta}
          breakdown={{
            draft: stats.byStatus.draft,
            alpha: stats.byStatus.alpha,
            beta: stats.byStatus.beta,
          }}
        />
        
        <StatCard
          title="Quality Score"
          value={Math.round(stats.avgTestCoverage)}
          subtext="% test coverage"
        />
      </div>
      
      <div className="stats-charts">
        <StatusDistributionChart data={stats.byStatus} />
        <CategoryBreakdownChart data={stats.byCategory} />
        <CompletionTrendChart data={stats.completionTrend} />
      </div>
    </div>
  );
};
```

---

## LAYER 8: Development Workflow Integration

### 8.1 Pre-commit Hooks
**Suggestion 701-740: Validate function registration**

```bash
# .husky/pre-commit
#!/bin/sh

echo "Validating function metadata..."

# Check that new functions have decorators
MODIFIED_TS_FILES=$(git diff --cached --name-only | grep '\.ts$')

for file in $MODIFIED_TS_FILES; do
  # Look for 'function' keyword without '@registerFunction'
  UNREGISTERED=$(grep -c "export.*function" "$file" || true)
  REGISTERED=$(grep -c "@registerFunction" "$file" || true)
  
  if [ "$UNREGISTERED" -gt "$REGISTERED" ]; then
    echo "⚠️  Warning: Function in $file not registered with @registerFunction"
    exit 1
  fi
done

echo "✅ All functions properly registered"
```

### 8.2 PR Template Auto-Sync Section
**Suggestion 741-770: PR template checks**

```markdown
# .github/pull_request_template.md

## Backend Changes

### Functions Modified
- [ ] Function metadata updated in decorator
- [ ] Scorecard modified (if applicable)
- [ ] `FUNCTIONS_IN_REPO.md` updated
- [ ] Portal impact assessed

### Checklist for Function Updates
- [ ] New function has `@registerFunction` decorator
- [ ] Completion % updated
- [ ] Status reflects current state (draft/alpha/beta/stable)
- [ ] Examples provided (if applicable)
- [ ] Category assigned
```

### 8.3 Automated Status Updates from CI
**Suggestion 771-810: CI updates function status**

```yaml
# .github/workflows/function-ci-status.yml
name: Update Function Status (CI)

on:
  workflow_run:
    workflows: ['Tests']
    types: [completed]

jobs:
  update-status:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Parse test results
        id: test-results
        run: |
          COVERAGE=$(cat coverage.json | jq '.total.lines.pct')
          PASSED=$(cat test-results.json | jq '.numPassedTests')
          FAILED=$(cat test-results.json | jq '.numFailedTests')
          
          echo "coverage=$COVERAGE" >> $GITHUB_OUTPUT
          echo "passed=$PASSED" >> $GITHUB_OUTPUT
          echo "failed=$FAILED" >> $GITHUB_OUTPUT
      
      - name: Update scorecard
        run: |
          curl -X POST http://portal:3000/api/v1/scorecards/batch-update \
            -H "Content-Type: application/json" \
            -d '{
              "functions": {
                "*": {
                  "testCoverage": ${{ steps.test-results.outputs.coverage }},
                  "reliability": ${{ steps.test-results.outputs.passed }} / (${{ steps.test-results.outputs.passed }} + ${{ steps.test-results.outputs.failed }}) * 100
                }
              }
            }'
```

---

## LAYER 9: Real-Time Collaboration

### 9.1 Live Updates with Server-Sent Events
**Suggestion 811-850: Alternative to WebSocket (SSE)**

```typescript
// src/middleware/sse.ts
export function setupSSE(app: Express) {
  const clients: Response[] = [];
  
  app.get('/api/v1/events/functions', (req, res) => {
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    
    clients.push(res);
    
    res.on('close', () => {
      clients.splice(clients.indexOf(res), 1);
    });
  });
  
  // Broadcast function updates to all SSE clients
  functionStatusManager.on('statusChanged', (event) => {
    clients.forEach(client => {
      client.write(
        `data: ${JSON.stringify({
          type: 'functionStatusChanged',
          data: event,
          timestamp: new Date().toISOString(),
        })}\n\n`
      );
    });
  });
}
```

### 9.2 Portal SSE Listener
**Suggestion 851-880: Portal receives SSE updates**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/hooks/useSSEFunctions.ts
import { useEffect, useState } from 'react';

export function useSSEFunctions() {
  const [functions, setFunctions] = useState<any[]>([]);
  
  useEffect(() => {
    const eventSource = new EventSource('/api/v1/events/functions');
    
    eventSource.onmessage = (event) => {
      const { type, data } = JSON.parse(event.data);
      
      if (type === 'functionStatusChanged') {
        setFunctions(prev => {
          const idx = prev.findIndex(f => f.name === data.functionName);
          const updated = [...prev];
          updated[idx] = { ...updated[idx], ...data };
          return updated;
        });
      }
    };
    
    return () => eventSource.close();
  }, []);
  
  return { functions };
}
```

---

## LAYER 10: Documentation & Visibility

### 10.1 Auto-Generated API Docs
**Suggestion 881-920: OpenAPI/Swagger integration**

```typescript
// src/openapi/generate.ts
import swaggerJsdoc from 'swagger-jsdoc';

const options = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'EIQ Nexus API',
      version: '1.0.0',
      description: 'Complete API documentation auto-generated from function metadata',
    },
    servers: [
      { url: 'http://localhost:3000', description: 'Development' },
    ],
  },
  apis: ['src/api/nexus/v1/*.ts'],
};

export const swaggerSpec = swaggerJsdoc(options);

// Serve Swagger UI
app.use('/api-docs', swaggerUi.serve);
app.get('/api-docs', swaggerUi.setup(swaggerSpec));
```

### 10.2 README Auto-Generation
**Suggestion 921-950: Generate README from metadata**

```typescript
// scripts/generate-readme-section.ts
import { getFunctionRegistry } from '../src/api/nexus/v1/decorators';

function generateReadmeSection(): string {
  const registry = getFunctionRegistry();
  const groupedByCategory = Object.values(registry).reduce((acc, fn) => {
    if (!acc[fn.category]) acc[fn.category] = [];
    acc[fn.category].push(fn);
    return acc;
  }, {} as Record<string, any[]>);
  
  let readme = '# Backend Functions\n\n';
  
  Object.entries(groupedByCategory).forEach(([category, functions]) => {
    readme += `## ${category}\n\n`;
    
    functions.forEach(fn => {
      readme += `### ${fn.name}\n`;
      readme += `**Status:** ${fn.status} (${fn.completionPercent}%)\n\n`;
      readme += `${fn.description}\n\n`;
      
      if (fn.examples?.length) {
        readme += '**Example:**\n```typescript\n';
        readme += fn.examples[0].code;
        readme += '\n```\n\n';
      }
    });
  });
  
  return readme;
}
```

### 10.3 Portal-Generated HTML Docs
**Suggestion 951-990: Docs page in portal**

```typescript
// ElevatedIQ-Mono-Repo/apps/portal/src/pages/APIDocumentation.tsx
import React, { useEffect, useState } from 'react';

export const APIDocumentation: React.FC = () => {
  const [htmlDocs, setHtmlDocs] = useState<string>('');
  
  useEffect(() => {
    const fetchDocs = async () => {
      const res = await fetch('/api/v1/docs/api');
      const html = await res.text();
      setHtmlDocs(html);
    };
    
    fetchDocs();
  }, []);
  
  return (
    <div className="api-documentation">
      <div dangerouslySetInnerHTML={{ __html: htmlDocs }} />
    </div>
  );
};
```

---

## LAYER 11: Alerting & Notifications

### 11.1 Function Health Alerts
**Suggestion 991-1000: Monitor and alert**

```typescript
// src/monitoring/function-health-monitor.ts
export class FunctionHealthMonitor {
  checkFunctionHealth(fn: FunctionMetadata): Alert[] {
    const alerts: Alert[] = [];
    
    if (fn.scorecard.testCoverage < 50) {
      alerts.push({
        severity: 'warning',
        message: `${fn.name} test coverage is ${fn.scorecard.testCoverage}%`,
        action: 'Increase test coverage',
      });
    }
    
    if (fn.completionPercent === 0 && fn.status === 'in_development') {
      if (Date.now() - new Date(fn.lastUpdated).getTime() > 7 * 24 * 60 * 60 * 1000) {
        alerts.push({
          severity: 'info',
          message: `${fn.name} hasn't been updated in 7 days`,
          action: 'Check on development progress',
        });
      }
    }
    
    return alerts;
  }
}

// Endpoint for portal alerts
app.get('/api/v1/alerts/functions', (req, res) => {
  const registry = getFunctionRegistry();
  const monitor = new FunctionHealthMonitor();
  const alerts = Object.values(registry)
    .flatMap(fn => monitor.checkFunctionHealth(fn));
  res.json(alerts);
});
```

---

## IMPLEMENTATION ROADMAP

### Phase 1: Foundation (Week 1)
- [ ] Create `@registerFunction` decorator system
- [ ] Build metadata introspection endpoints
- [ ] Add WebSocket server for real-time updates
- [ ] Update portal to query backend metadata

### Phase 2: Integration (Week 2)
- [ ] Auto-generate function manifests on build
- [ ] Create portal UI components (FunctionCard, etc.)
- [ ] Setup GitHub Actions for sync
- [ ] Implement scorecard tracking

### Phase 3: Automation (Week 3)
- [ ] Auto-status updates from CI/CD
- [ ] Issue-to-function-stub workflow
- [ ] PR template integration
- [ ] Pre-commit hooks validation

### Phase 4: Enhancement (Week 4)
- [ ] Multiple view modes (Kanban, Timeline, etc.)
- [ ] Advanced filtering & search
- [ ] Health monitoring & alerts
- [ ] OpenAPI docs generation

---

## KEY PRINCIPLES

1. **No Manual Sync**: Everything automatic via metadata
2. **Real-Time**: Portal always shows current state (WebSocket/SSE)
3. **Progress Visible**: Incomplete functions shown with completion %
4. **Scorecard Driven**: Every function has quality metrics
5. **Developer Friendly**: Minimal additional code/decorators required
6. **Discoverable**: Functions impossible to hide from portal

---

## SUCCESS METRICS

- [ ] 100% of backend functions visible in portal within 5 minutes of creation
- [ ] Zero functions undocumented
- [ ] Portal refresh ≤ 30 seconds behind backend changes
- [ ] All new functions show in portal before PR merge
- [ ] Functions grouped by category, status, completion
- [ ] Scorecards updated automatically from CI

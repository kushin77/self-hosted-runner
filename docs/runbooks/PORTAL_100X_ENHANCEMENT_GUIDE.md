# Portal 100X Enhancement - Deployment & Usage Guide

**Date**: 2026-03-05  
**Status**: 🟢 Production Ready  
**Version**: 1.0.0

## 🚀 Quick Start

### Prerequisites
- Node.js 18+
- npm 9+
- Provisioner metrics server running on `:9090`

### Run Locally

```bash
# Install dependencies (if not already done)
cd ElevatedIQ-Mono-Repo/apps/portal
npm install

# Start development server
npm run dev

# Or build for production
npm run build

# Serve production build
npx serve -s dist -l 3919
```

The portal will be available at `http://localhost:5173` (dev) or `http://localhost:3919` (prod).

### Access New Features
1. Open the portal
2. Click on **"Observability"** in the sidebar (new top-level nav item)
3. Explore the dashboards

## 📊 New Pages & Components

### 1. Observability Dashboard
**Path**: `/pages/Observability.tsx`  
**URL**: Main page with new "Observability" tab

#### Features
- **Real-time job metrics** from the provisioner-worker
- **System health status** (Vault, JobStore, Queue)
- **Performance analytics** with trend charts
- **Alert notifications** showing current system issues

#### What It Shows
```
┌─────────────────────────────────────────────────┐
│ Observability & Monitoring                      │
├─────────────────────────────────────┬───────────┤
│                                   │           │
│  • Job Processing Trends          │ System    │
│  • Latency Percentiles (P50/95)   │ Status    │
│  • Queue Status & Depth           │           │
│  • Success Rate Distribution       │ Alerts &  │
│                                   │ Notif.   │
├─────────────────────────────────────┴───────────┤
│ Health Indicators & Recent Events                │
└─────────────────────────────────────────────────┘
```

### 2. Advanced Analytics Component
**Path**: `/pages/Analytics.tsx`

#### Visualizations
- **Job Success Rate Pie Chart**: Shows succeeded vs. failed split
- **Processing Trend Area Chart**: Stacked view of succeeded/failed over time
- **Latency Percentile Line Chart**: P50, P95, P99 latencies
- **Performance Metrics Grid**: Terraform latencies, last job duration

#### Data Points
- Real-time collection every 5 seconds
- Historical trend data (last 20 data points = ~100 seconds in past)
- Automatic health alert triggers

### 3. System Status Component
**Path**: `/components/SystemStatus.tsx`

Shows at-a-glance indicators for:
- 🛡️ **Vault Connectivity**: Online/Offline status
- 💾 **JobStore**: Operational/Error status
- ⚡ **Queue System**: Health based on queue depth
- 🔄 **Job Processing**: Active job count and success rate
- ⚙️ **Performance**: Last job duration and health

Color-coded with live pulse animation for active indicators.

### 4. Alerts Panel
**Path**: `/components/Alerts.tsx`

Real-time alerting system with auto-detection of:
- ❌ Vault disconnection
- ❌ JobStore operational errors  
- ⚠️ High queue depth (>100 jobs)
- ✅ Job processing status changes

Features:
- Keeps last 50 alerts
- One-click clear all
- Sortable and filterable
- Severity-based icons and colors

### 5. Job Queue Monitor
**Path**: `/components/JobQueue.tsx`

Live monitoring of:
- Current running jobs with progress bars
- Queued jobs waiting for execution
- Job duration tracking
- Real-time job status updates

## 🔌 Integration Points

### Metrics Server API
The portal connects to the metrics server on `http://localhost:9090`:

```bash
# Check endpoints
curl http://localhost:9090/metrics/summary    # JSON format
curl http://localhost:9090/health             # Health check
curl http://localhost:9090/ready              # Readiness
curl http://localhost:9090/alive              # Liveness
```

### Data Flow
```
Browser Portal
    ↓
useMetrics() hook (5s polling)
    ↓
HTTP GET /metrics/summary
    ↓
Zustand Store (state management)
    ↓
React Components (re-render on update)
```

## 📦 State Management

### Zustand Store
**Location**: `src/api/store.ts`

Access global state anywhere in components:
```typescript
import { useStore } from '../api/store';

const MyComponent = () => {
  const metrics = useStore((s) => s.metrics);
  const alerts = useStore((s) => s.alerts);
  const addAlert = useStore((s) => s.addAlert);
  
  // Use metrics and alerts...
};
```

### Store Actions
- `setMetrics(data)` - Update metrics
- `addAlert(alert)` - Add alert
- `clearAlerts()` - Clear all alerts
- `setSelectedRunner(runner)` - Select runner
- `setSelectedJob(job)` - Select job
- `setLoading(bool)` - Loading state
- `setError(msg)` - Error message

## 🎨 Component Library

### UI Components (Existing)
- `Panel` - Card container with optional glow effect
- `Pill` - Badge for status indicators
- `GlowDot` - Animated dot indicator
- `Button` - Interactive button
- `PanelHeader` - Panel title with icon

### New Chart Components
All charts use **Recharts** library:
- `AreaChart` - For job trends
- `LineChart` - For latency trends  
- `PieChart` - For success rates
- `BarChart` - For distributions

### Icons
All icons from **Lucide React**:
```typescript
import {
  Activity, AlertCircle, AlertTriangle,
  CheckCircle, Clock, Database, Play,
  Pause, Shield, Zap, Cpu, HardDrive
} from 'lucide-react';
```

## 🔄 Real-Time Updates

### Current: Polling (5 second interval)
```typescript
useMetrics({ interval: 5000 })
```

Fetches `/metrics/summary` every 5 seconds and updates the Zustand store.

### Future: WebSocket (Phase 2)
Will upgrade to true real-time updates via socket.io-client (already installed).

## 📈 Performance Optimization

### Bundle Size
- **Main JS**: 257KB (73KB gzip)
- **Modules**: 50 total
- **Build Time**: 1.3s
- **Tree-shakeable**: ✅ All unused code removed in production

### Lazy Loading (Phase 2)
Component-level code splitting will be added for:
- Observability page
- Analytics components
- Job queue monitor

## 🚨 Troubleshooting

### "Metrics not loading"
```bash
# Check metrics server is running
curl http://localhost:9090/health

# If connection refused:
# 1. Start metrics server
node services/provisioner-worker/lib/metricsServer.js

# 2. Check CORS headers are set
# Dashboard should see this header:
# Access-Control-Allow-Origin: *
```

### "No alerts showing"
- Alerts auto-trigger only for health issues
- Check browser console for errors
- Verify metrics are being fetched (check Network tab)

### "Lag in chart updates"
- Normal with 5s polling interval
- Will be instant with WebSocket (Phase 2)
- Can adjust interval in App.tsx useMetrics call

## 🔐 Security Considerations

### Current
- ✅ Read-only metrics access
- ✅ No authentication required on local metrics endpoint  
- ✅ CORS enabled for localhost access

### Future (Phase 2)
- API authentication/authorization
- Role-based dashboard access
- Sensitive metric masking
- Audit logging for dashboard access

## 📚 Additional Resources

- [Portal Design Reference](../architecture/PORTAL_DESIGN_REFERENCE.md)
- [Portal Quick Start](PORTAL_QUICK_START.md)
- [Original Portal Implementation](../archive/completion-reports/PORTAL_IMPLEMENTATION_SUMMARY.md)
- [GitHub Issue #281](https://github.com/kushin77/self-hosted-runner/issues/281)

## 🎯 Next Steps

### Phase 2 Road map
1. **WebSocket Integration** (Instant updates)
2. **Runner Fleet Management** (Individual runner monitoring)
3. **Advanced Job Management** (Replay, replay, search)
4. **Failure Analysis** (AI-powered debugging)
5. **Custom Dashboards** (User-configurable views)
6. **Mobile Responsive** (Better mobile UX)
7. **API Documentation** (OpenAPI/Swagger)
8. **Export & Reporting** (Data export)

### Contribution Guidelines
- All new components go in `src/components/` or `src/pages/`
- State management via Zustand store in `src/api/store.ts`
- Charts use Recharts library
- Icons use Lucide React
- Testing with React Testing Library

---

**Questions?** Check the [Portal Design Reference](../architecture/PORTAL_DESIGN_REFERENCE.md) or open an issue on GitHub.

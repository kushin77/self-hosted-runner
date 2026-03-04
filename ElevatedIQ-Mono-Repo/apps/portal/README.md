# RunnerCloud Portal

**Real-time CI/CD orchestration dashboard for GitHub Actions Runners**

## 📊 Features

- **Multi-mode Deployment**: Managed, BYOC, On-Premises runner ecosystems
- **AI-Powered Intelligence**: Automated failure analysis, performance profiling, security auditing
- **Live Metrics**: Real-time runner status, job throughput, cost tracking
- **Agent Studio**: Configure and monitor sidecar agents
- **Security Monitoring**: eBPF-based supply chain security
- **Cost Analytics**: TCO comparison across providers

## 🎯 Quick Start

```bash
# Install dependencies
npm install

# Start dev server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

Dev server runs on `http://localhost:3000`

## 📁 Project Structure

```
portal/
├── src/
│   ├── App.tsx                    # Main app component
│   ├── main.tsx                   # React entry point
│   ├── theme.ts                   # Design system
│   ├── hooks.ts                   # Custom React hooks
│   ├── components/
│   │   ├── UI.tsx                 # Shared UI components
│   │   ├── Charts.tsx             # Chart & visualization components
│   │   └── Layout.tsx             # Layout (Sidebar, StatusBar)
│   ├── pages/
│   │   ├── Dashboard.tsx          # Main dashboard view
│   │   ├── AgentStudio.tsx        # (TODO) Agent configuration
│   │   ├── AIOracle.tsx           # (TODO) Failure analysis
│   │   ├── Runners.tsx            # (TODO) Runner management
│   │   ├── Security.tsx           # (TODO) Security monitoring
│   │   ├── Billing.tsx            # (TODO) Cost tracking
│   │   └── Settings.tsx           # (TODO) Configuration
│   └── types/
│       └── index.ts               # TypeScript type definitions
├── index.html                      # HTML entry point
├── vite.config.ts                 # Vite configuration
├── tsconfig.json                  # TypeScript configuration
└── package.json                   # Dependencies
```

## 🧩 Component Library

### UI Components
- **Pill**: Status/label badges
- **Button**: Primary action buttons
- **Panel**: Glowing containers with gradient backgrounds
- **GlowDot**: Animated indicator dots
- **PanelHeader**: Standard panel title headers
- **GlobalStyles**: CSS animations (spin, pulse, glow)

### Charts
- **Sparkline**: Minimal line charts (32x120px)
- **AreaChart**: Filled area with gradient
- **BarChart**: Animated bar charts
- **Gauge**: Half-circle progress indicator
- **Donut**: Multi-segment donut chart
- **ProgressBar**: Horizontal progress bars

### Layout
- **Sidebar**: Main navigation with 10 sections
- **StatusBar**: Live status indicator bar

## 🎨 Design System

### Color Palette
```typescript
const COLORS = {
  bg: "#070a0f",              // Deep black
  surface: "#0d1117",         // Panel backgrounds
  accent: "#3b82f6",          // Primary blue
  green: "#22c55e",           // Success/active
  yellow: "#f59e0b",          // Warning
  red: "#ef4444",             // Error/critical
  cyan: "#06b6d4",            // Secondary accent
  purple: "#a855f7",          // AI/special
  orange: "#f97316",          // Contrast
  
  text: "#e2e8f0",            // Primary text
  textDim: "#94a3b8",         // Secondary text
  muted: "#4b5563",           // Inactive/borders
}
```

### Features
- Ultra-dark theme with glowing accents
- Drop-shadow effects for depth
- Gradient backgrounds
- Smooth animations (spin, pulse)
- Responsive grid layouts

## 🔧 Custom Hooks

```typescript
// Periodic tick for updating metrics
const tick = useTick(2500);

// Manage rolling window of data
const { data, update } = useSparklineData(28, 60, 420);

// Simulated runner metrics
const { runners, jobsPerMin, update } = useRunnerMetrics();

// Smooth value transitions
const animated = useAnimatedValue(targetValue, 0.1);
```

## 📊 Dashboard Features

### Deployment Modes
- Managed (RunnerCloud fleet)
- BYOC (Your cloud account)
- On-Prem (Bare metal)

### Key Metrics
- Active Runners (count)
- Jobs/Min (throughput)
- Cache Hit Rate (%)
- AI Fixes Today (count)

### Resource Monitoring
- vCPU usage with gauge
- Memory usage with gauge
- GPU usage with gauge

### Active Agents
- Failure Oracle (analysis)
- Perf Profiler (performance)
- Security Auditor (scanning)
- Cache Oracle (optimization)

### Cache Tracking
- npm/pnpm cache (96% hit rate)
- Docker layers (89% hit rate)
- pip/poetry (91% hit rate)
- Go modules (88% hit rate)

## 🚀 Development Status

### ✅ Completed (Phase 1)
- Core project setup
- Theme & design system
- UI component library
- Chart components
- Layout components
- Dashboard page
- Hooks & utilities

### 🔄 In Progress (Phase 2)
- Agent Studio page
- AI Oracle detail view
- Runners management page

### 📋 TODO (Phase 3)
- Deploy Mode wizard
- Security monitoring
- Billing calculator
- Jobs view
- Cache management
- Settings panel
- Windows runners support

## 🔌 API Integration

Currently using simulated data with `rand()` function for generating realistic metrics. When connecting to backend:

```typescript
// Replace simulated updates with API calls
useEffect(() => {
  fetchRunnerMetrics().then(data => {
    setRunners(data.count);
    setJobsPerMin(data.throughput);
  });
}, [tick]);
```

## 📚 Reference Implementations

Four complete portal implementations are provided in the requirements as design references:
1. **ARC Control** - Simpler, focused layout
2. **Enhanced Dashboard** - Extended metrics and charts
3. **Multi-Mode Portal** - Deployment modes emphasis
4. **Agent Studio** - AI agents as primary feature

Use these for styling, layout, and functionality inspiration.

## 🎯 Build Commands

```bash
# Development
npm run dev          # Start dev server with HMR

# Production
npm run build        # Optimize build
npm run preview      # Preview production build locally

# Code Quality
npm run lint         # ESLint checks
npm run type-check   # TypeScript validation
```

## 🧪 Testing Strategy

- Component testing with React Testing Library (TODO)
- E2E tests with Cypress (TODO)
- Visual regression with Percy (TODO)
- Performance testing with Lighthouse (TODO)

## 📖 Styling Guidelines

- Use inline styles with theme constants
- Reference COLORS object for all colors
- Use CSS Grid for layouts
- Apply theme-consistent spacing (8px grid)
- Use drop-shadow for floating elements
- Add glow effects for interactive elements

## 🔐 Security Considerations

- No sensitive data stored in component state
- All metrics are non-sensitive telemetry
- API tokens will be server-side only (when integrated)
- CORS headers will be validated by backend

## 📞 Support

Refer to `PORTAL_DEVELOPMENT.md` for:
- Detailed component specifications
- File structure documentation
- Architecture notes
- Contributing guidelines
- Known issues tracker

## 📄 License

Part of the RunnerCloud project - see LICENSE in repo root.

# RunnerCloud Portal Development Tracker

**Status**: 🚀 Active Development - Phase 1  
**Updated**: 2026-03-04  
**Target Completion**: Sprint 2 (2 weeks)

## 📋 Overview

The RunnerCloud Portal is a real-time CI/CD orchestration dashboard built with React + TypeScript. It provides visibility into:
- **Multi-mode runner deployment** (Managed/BYOC/On-Prem)
- **AI-powered failure analysis** (Agent Studio)
- **Live metrics & performance** (Dashboard)
- **Cost & TCO tracking** (Billing)
- **Security monitoring** (eBPF layer)

## ✅ Completed

### Core Infrastructure (Phase 1)
- [x] Project structure & configuration
  - [x] package.json with dependencies
  - [x] Vite configuration
  - [x] TypeScript config
  - [x] .gitignore

- [x] Design System & Theme
  - [x] COLORS constant definitions
  - [x] Color mapping utilities
  - [x] Theme types & exports

- [x] Shared UI Components
  - [x] `Pill` - Status/label badges
  - [x] `GlowDot` - Indicator dots
  - [x] `Panel` - Container with gradient + glow
  - [x] `PanelHeader` - Standard panel headers
  - [x] `Button` - Primary buttons
  - [x] GlobalStyles - CSS animations

- [x] Chart Components
  - [x] Sparkline - Minimal line charts
  - [x] AreaChart - Filled area with gradient
  - [x] BarChart - Animated bar chart
  - [x] Gauge - Half-circle progress gauge
  - [x] Donut - Multi-segment donut chart
  - [x] ProgressBar - Horizontal progress indicator

- [x] Layout Components
  - [x] Sidebar - Main navigation
  - [x] StatusBar - Top live status bar
  - [x] Navigation items defined

- [x] Hooks & Utilities
  - [x] `useTick` - Periodic updates
  - [x] `useSparklineData` - Rolling metrics window
  - [x] `useRunnerMetrics` - Simulated metrics
  - [x] `useAnimatedValue` - Smooth transitions

- [x] Pages
  - [x] Dashboard - Main overview page
  - [x] App.tsx - Main app component
  - [x] Entry points (main.tsx, index.html)

## 🔄 In Progress

### Agent Studio (Phase 2)
- [ ] Agent Roster - Display active agents
  - [ ] Agent card components
  - [ ] Live activity feed
  - [ ] Sidecar manifest viewer
- [ ] Intent Editor
  - [ ] Markdown editor
  - [ ] Workflow compiler
  - [ ] Deploy integration

### AI Oracle Page
- [ ] Failure analysis display
- [ ] PR comment history
- [ ] Auto-fix tracking
- [ ] Confidence scoring visualization

### Runners Management
- [ ] Runners table/list
- [ ] CPU/memory monitoring
- [ ] Pool management
- [ ] Ephemeral pod tracking

## 📝 Not Started

### Phase 2 Features
- [ ] Deploy Mode Wizard
  - [ ] Managed mode setup
  - [ ] BYOC setup flow
  - [ ] On-Prem setup flow
  - [ ] Step-by-step wizard UI

- [ ] Security Layer
  - [ ] eBPF event stream
  - [ ] Network allowlisting display
  - [ ] SBOM generation timeline
  - [ ] CVE flagging

- [ ] Windows Runners
  - [ ] Windows pool configuration
  - [ ] MSBuild/Unity support
  - [ ] Unreal Engine integration

- [ ] Billing & TCO
  - [ ] Cost calculator
  - [ ] Provider comparison chart
  - [ ] Usage trends
  - [ ] Invoice history

- [ ] Settings
  - [ ] GitHub integration settings
  - [ ] Intelligence toggles
  - [ ] Theme preferences
  - [ ] Notification settings

- [ ] Jobs View
  - [ ] Job queue visualization
  - [ ] Job logs viewer
  - [ ] Workflow history
  - [ ] Status filtering

- [ ] Cache Management
  - [ ] Cache hit rate dashboard
  - [ ] Cache size management
  - [ ] Predictive invalidation
  - [ ] Cross-repo sharing config

## 🎨 Design System

### Colors
```
Primary:  #3b82f6 (Blue/Accent)
Success:  #22c55e (Green)
Warning:  #f59e0b (Yellow)
Error:    #ef4444 (Red)
Info:     #06b6d4 (Cyan)
Special:  #a855f7 (Purple)
```

### Component Library
✅ Implemented:
- Pill, GlowDot, Panel, PanelHeader, Button
- Sparkline, AreaChart, BarChart, Gauge, Donut, ProgressBar
- Sidebar, StatusBar

🔄 In Progress:
- Tabs, Modal, Dropdown components

📋 TODO:
- Select, InputField, TextArea components
- Table, DataGrid components
- Toast notifications

## 🚀 Next Steps

1. **Immediate** (This week)
   - [ ] Build Runners page with live metrics
   - [ ] Create Agent Studio roster view
   - [ ] Implement AI Oracle detail page
   
2. **Short-term** (Next week)
   - [ ] Deploy Mode wizard
   - [ ] Security monitoring view
   - [ ] Billing calculator

3. **Medium-term** (Sprint 2)
   - [ ] Intent Editor with markdown parser
   - [ ] Windows runners support
   - [ ] Full state management (if needed)
   - [ ] Backend API integration

## 📦 Dependencies

### Core
- react@18.2.0
- react-dom@18.2.0

### Dev
- typescript@5.3.0
- vite@5.0.0
- @vitejs/plugin-react@4.2.0
- @types/react@18.2.0
- @types/react-dom@18.2.0

## 🔗 File Structure

```
src/
  ├── App.tsx                 # Main app component
  ├── main.tsx               # Entry point
  ├── theme.ts               # Design system
  ├── hooks.ts               # Custom hooks
  ├── components/
  │   ├── UI.tsx             # Shared UI components
  │   ├── Charts.tsx         # Chart components
  │   └── Layout.tsx         # Layout components
  ├── pages/
  │   ├── Dashboard.tsx      # Main dashboard
  │   ├── AgentStudio.tsx    # (TODO)
  │   ├── AIOracle.tsx       # (TODO)
  │   ├── Runners.tsx        # (TODO)
  │   ├── Billing.tsx        # (TODO)
  │   └── Settings.tsx       # (TODO)
  └── types/
      └── index.ts           # TS types (TODO)
```

## 🐛 Known Issues

- Placeholder pages showing for unimplemented sections
- No real data integration yet (all metrics are simulated)
- No authentication/authorization implemented
- LocalStorage not implemented for preferences

## 📚 References

### Component Sketches (from brainstorming)
- 4 full portal implementations provided as reference
- Various agent personas (Oracle, Perf Profiler, Security, Cache)
- Multi-deployment mode setup wizard
- Comprehensive billing comparison

### Related Docs
- See `docs/PROJECT_COMPLETION_SUMMARY.md` for project context
- Phase P1 documentation in `docs/PHASE_P1_*`

## 💡 Architecture Notes

### State Management
- Currently using React hooks for local state
- Consider Redux/Zustand if grows beyond 50 components
- Real-time updates via tick hook (2.5s refresh)

### Data Flow
```
useTick (periodic) 
  → useRunnerMetrics (calculates)
    → <Component> (renders)
```

### Styling Approach
- Inline styles with theme constants
- CSS Grid for layout
- Gradient + glow effects for depth
- Drop-shadow for floating elements

## 🤝 Contributing

1. Create a feature branch: `git checkout -b portal/feature-name`
2. Implement components following existing patterns
3. Update this tracker
4. Submit PR with reference to GitHub issues

## 📞 Questions?

Refer to the brainstorming code snippets in the initial requirements. Each provides a complete UI implementation to reference for styling, layout, and functionality.

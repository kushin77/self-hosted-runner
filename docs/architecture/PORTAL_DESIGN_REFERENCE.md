# RunnerCloud Portal - Design Reference Guide

This document catalogs the four complete portal implementations provided as brainstorming references. Each represents different design approaches and feature emphasis.

## 📚 Reference Implementations Overview

### 1. **ARC Control Dashboard** (Version 1)
**Focus**: Clean, minimal runner orchestration  
**Theme**: Dark with blue/green accents  
**Complexity**: Moderate

#### Key Components
- **Navigation**: Left sidebar with 5 tabs (Overview, Runners, Jobs, Alerts, Settings)
- **Stat Cards**: 4-column metrics row with sparklist charts
- **Queue Chart**: Bar chart showing job queue depth over time
- **Runner Table**: Full table with pod status, CPU/Memory bars
- **Alerts Panel**: Colored alert feed with icons
- **AI Oracle Panel**: Purple-themed finding analysis

#### Color Scheme
```javascript
const COLORS = {
  bg: "#0a0c10",
  surface: "#111318",
  border: "#1e2330",
  accent: "#3b82f6",
  green: "#22c55e",
  red: "#ef4444",
  purple: "#a855f7",
  text: "#e2e8f0",
};
```

#### Notable Features
- Pill component with color-coded status
- Sparkline charts with smooth curves
- StatCard component (reusable metric display)
- RunnerRow table row component with progress bars
- Alert system with severity levels
- Carbon score tracking

---

### 2. **Enhanced Dashboard** (Version 2)
**Focus**: Rich metrics and real-time monitoring  
**Theme**: Ultra-dark with glowing effects  
**Complexity**: High

#### Key Components
- **GlowText**: Text with drop-shadow glow effect
- **Panel**: Gradient background with inset highlights
- **Gauge**: Half-circle progress indicators
- **Sparkline (Mini)**: Compact line chart
- **Donut Chart**: Multi-segment donut with segments
- **BarChart**: Simple bar chart with opacity gradient
- **AreaChart**: Filled area with gradient and endpoint dot
- **Top Bar**: Gradient hero stats (5 columns)
- **Main Grid**: 2-column layout with 4 quadrants

#### Features
- Live job counter metrics
- Runner fleet composition (Ephemeral/Spot/GPU breakdown)
- Pending pods indicator with pulsing
- Node pool status tracking
- AI Intelligence panel (4 metrics)
- Recent job logs with embedded status
- Windows runners beta section

#### Advanced Styling
```javascript
boxShadow: `0 0 20px ${color}22, inset 0 1px 0 #ffffff08`
filter: `drop-shadow(0 0 6px ${color})`
background: `linear-gradient(145deg, #0d1117, #0a0f1a)`
```

---

### 3. **Multi-Mode Portal** (Version 3)
**Focus**: Deployment modes, scaling, cost tracking  
**Theme**: Advanced dark with purple AI accents  
**Complexity**: Very High

#### Key Sections
1. **Deploy Mode Wizard**
   - 3 cards: Managed, BYOC, On-Premises
   - Interactive selection with setupwizard flow
   - Step-by-step setup with validation
   - Dark code blocks for CLI commands

2. **Dashboard Enhancements**
   - Mode status strip (3 cards with metrics)
   - KPI row (4 metrics in grid)
   - Agent health strip with active agents
   - Charts row (throughput + AI Oracle)
   - Cache/Windows runners bottom row

3. **AI Oracle Page**
   - Failure case list with expandable details
   - Code block output showing analysis
   - Confidence percentage tracking
   - Auto-fix vs suggested fixes

4. **Billing/TCO**
   - Range slider for cost calculator
   - Competitor comparison bars
   - Cost savings percentages

#### Advanced Features
- SetupWizard component with steps
- ButtonStyle utility function
- IntentEditor with markdown input
- Security eBPF event stream
- Pagination support

---

### 4. **AI Agent Studio** (Version 4 - Latest)
**Focus**: Sidecar agents as primary feature  
**Theme**: Most sophisticated with color-per-agent system  
**Complexity**: Extreme

#### Key Components

1. **Agent Studio**
   - Left panel: Agent roster with list
   - Right panel: Agent detail + config editor
   - Tab system (Agent Roster / Intent Editor)
   - Agent card showing: icon, name, status, tags, runs

2. **Intent Editor**
   - Split pane: Markdown input | Compiled output
   - Markdown format for CI logic:
     ```markdown
     # My CI Agent
     Goal: Run tests and build on every push to main
     
     ## Rules
     - If PR label is "experimental": use lighter matrix
     - If changes only in /docs: skip tests entirely
     ```
   - Compiles to workflow YAML

3. **Agent Personas** (6 agents)
   ```javascript
   PERSONAS = [
     {id: "oracle", icon: "🔮", name: "Failure Oracle", color: C.purple, ...},
     {id: "perf", icon: "⚡", name: "Perf Profiler", color: C.yellow, ...},
     {id: "security", icon: "🛡", name: "Security Auditor", color: C.red, ...},
     {id: "cache", icon: "💾", name: "Cache Oracle", color: C.cyan, ...},
     {id: "review", icon: "👁", name: "Code Review Agent", color: C.accent, ...},
     {id: "deploy", icon: "🚢", name: "Deploy Guardian", color: C.green, ...},
   ]
   ```

4. **Security Layer**
   - eBPF event stream display
   - Network allowlist tracking
   - SBOM generation timeline
   - CVE flagging

#### Advanced Styling Patterns
```javascript
// Color-per-component pattern
{...glowColor?`0 0 20px ${glowColor}18`:"inset 0 1px 0 #ffffff06"}

// Animation patterns
animation: pulse ? 'pulse 2s infinite' : undefined

// Gradient backgrounds
background: `linear-gradient(135deg, ${color}18, ${color}08)`
```

---

## 🎯 Component Mapping

### Across All Versions

| Component | V1 | V2 | V3 | V4 | Notes |
|-----------|----|----|----|----|-------|
| Pill | ✓ | ✓ | ✓ | ✓ | Status badges, evolved |
| Panel | ✓ | ✓ | ✓ | ✓ | Glow effects added V2+ |
| Gauge | - | ✓ | ✓ | ✓ | Half-circle progress |
| Sparkline | ✓ | ✓ | - | ✓ | Combined with AreaChart |
| AreaChart | - | ✓ | ✓ | ✓ | Filled + gradient V2+ |
| BarChart | - | ✓ | ✓ | ✓ | With opacity gradient |
| Donut | - | ✓ | ✓ | ✓ | Multi-segment |
| Sidebar | ✓ | ✓ | ✓ | ✓ | Nav items evolved |
| StatusBar | ✓ | ✓ | ✓ | ✓ | Live indicator |

### Page Structure Evolution

```
V1 (5 pages):
  Overview, Runners, Jobs, Alerts, Settings

V2 (9 pages):
  + Agent Intelligence
  + Node Pool Status
  + Windows Runners (Beta)
  - Combined Alerts into Oracle

V3 (10 pages):
  + Deploy Mode (3-mode setup wizard)
  + Runners (detailed management)
  - Windows Runners detail moved to settings
  + Lives Cache
  + Windows Runners config

V4 (10 pages - Production Ready):
  + Agent Studio (primary feature)
  + Security Layer (eBPF focus)
  - Deploy Mode (moved to onboarding)
  + Refined all existing pages
```

---

## 📐 Layout Patterns

### V1: Simple Column Layout
```
│ Sidebar │ Header │
│         │ Content │
```

### V2/V3: Grid-based
```
│ Sidebar │ Header           │
│         │ Grid(2-3 cols)   │
│         │ Grid(auto rows)  │
```

### V4: Advanced Grid + Tabs
```
│ Sidebar │ Header              │
│         │ Tab Navigation      │
│         │ Flex / Grid Content │
```

---

## 🎨 Color Usage Patterns

### V1: Basic Status Colors
- Primary: Blue accent for focus
- Status: Green/Yellow/Red/Purple
- Muted: Gray for inactive
- Backgrounds: 2 levels (bg, surface)

### V2: Enhanced Glow System
- Added: accentGlow, greenGlow variants
- Drop-shadow filters on charts
- Inset highlights on panels
- Gradient backgrounds

### V3: Mode-Based Colors
```javascript
const modeColorMap = {
  managed: C.accent,   // Blue
  byoc: C.cyan,        // Cyan
  onprem: C.purple,    // Purple
};
```

### V4: Agent-Based Colors
- Each agent has unique color
- Color per data series
- Consistent throughout UI
- Accessibility: all colors pass WCAG AA

---

## 🔄 Data Patterns

### Simulated Data Generation

```typescript
// Single random value
const val = rand(min, max);

// Rolling array (sparkline data)
data = [...data.slice(1), rand(min, max)];

// Structured object updates
{
  cpu: Math.min(98, Math.max(5, cpu + rand(-5, 8))),
  mem: Math.min(98, Math.max(5, mem + rand(-3, 5))),
  status: status === "running" ? status : "idle",
}
```

### Tick-Based Updates
```typescript
const tick = useTick(2500); // 2.5s refresh

useEffect(() => {
  // Update metrics on each tick
  setRunners(v => Math.max(400, Math.min(580, v + rand(-8, 10))));
}, [tick]);
```

---

## 📱 Responsive Considerations

All versions use:
- CSS Grid with `flexShrink: 0` for fixed sidebar
- `overflowY: "auto"` for scrollable content
- Fixed heights: `height: "100vh"` root, `height: 44px` header
- Consistent spacing: `gap: X` for grid/flex

No media queries - focus on desktop dashboards.

---

## 🧩 Component Evolution

### Pill Component
```
V1: Simple badge with 1 color param
V2: Added sm, pulse, glow effects
V3: Enhanced color map
V4: Full animation support
```

### Panel Component
```
V1: Basic border + background
V2: Added glowColor + gradient + inset highlight
V3: Box-shadow refinement
V4: Per-component color gradients
```

### Charts
```
V1: Sparkline only (basic line)
V2: Full chart library (sparkline, area, bar, gauge, donut)
V3: Charts stabilized + usage patterns
V4: Animations + filters
```

---

## 🚀 Implementation Recommendations

### For Runners Page
- Reference V3's runner table
- Use V4's agent pattern for color-coding
- Implement live CPU/memory updates

### For Agent Studio
- Full implementation in V4
- Two-tab system: Roster + Intent Editor
- Complete persona system

### For Security Page
- Complete in V4
- eBPF event stream visualization
- SBOM timeline

### For Billing
- Partially in V3
- TCO calculator with slider
- Competitor comparison bars
- Use V4's bar chart pattern

---

## 🎯 Best Practices Observed

1. **Theme Constants**: All colors in single COLORS object
2. **Utility Functions**: Shared `rand()`, `btnStyle()`, etc.
3. **Component Composition**: Reusable UI atoms + Page molecules
4. **Styling**: Inline styles with theme constants (no CSS files)
5. **State Management**: React hooks only, no Redux
6. **Data Simulation**: Realistic with `rand()` and rolling arrays
7. **Accessibility**: Color contrast, meaningful icons, semantic HTML
8. **Performance**: SVG for charts, CSS Grid for layout, useRef for data

---

## 📝 Notes for Implementation

- Start with V1/V2 patterns for core functionality
- Evolve to V3/V4 patterns for advanced features
- Maintain consistent spacing and color usage
- Use existing component patterns as templates
- Keep animation effects consistent
- Test color readability at different zoom levels
- Ensure responsive behavior on smaller screens (optional)

## 🔗 Cross-Reference

See `PORTAL_DEVELOPMENT.md` for detailed development tracking and `README.md` for quick start guide.

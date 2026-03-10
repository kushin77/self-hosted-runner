# Portal Development Quick Start

## 🚀 Get Started in 5 Minutes

### 1. Install Dependencies
```bash
cd ElevatedIQ-Mono-Repo/apps/portal
npm install
```

### 2. Start Development Server
```bash
npm run dev
```
Server opens at `http://localhost:3000` with live reload

### 3. View Implemented Pages
- Dashboard (✅ Complete)
- Agent Studio (📋 Placeholder)
- Runners (📋 Placeholder)
- Billing (📋 Placeholder)
- Settings (📋 Placeholder)

### 4. Make Your First Edit
Edit `src/pages/Dashboard.tsx` and watch it update in real-time!

---

## 📖 File Guide

### Core Files
| File | Purpose |
|------|---------|
| `src/App.tsx` | App entry point, page routing |
| `src/main.tsx` | React DOM mount |
| `src/theme.ts` | Design system colors + utilities |
| `src/hooks.ts` | Custom React hooks |

### Components
| File | Contains |
|------|----------|
| `src/components/UI.tsx` | Pill, Panel, Button, etc. |
| `src/components/Charts.tsx` | Sparkline, AreaChart, Gauge, etc. |
| `src/components/Layout.tsx` | Sidebar, StatusBar |

### Pages
| File | Status |
|------|--------|
| `src/pages/Dashboard.tsx` | ✅ DONE |
| Other pages | 📋 Placeholder |

---

## 🎨 Implementing a New Page

### Step 1: Create page component
```typescript
// src/pages/MyPage.tsx
import React from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader } from '../components/UI';

export const MyPage: React.FC = () => {
  return (
    <div style={{ flex: 1, padding: 16, overflowY: 'auto' }}>
      <Panel>
        <PanelHeader icon="⚡" title="My Section" color={COLORS.accent} />
        <div style={{ padding: 14 }}>
          Content here
        </div>
      </Panel>
    </div>
  );
};
```

### Step 2: Add to App.tsx
```typescript
import { MyPage } from './pages/MyPage';

const pages = {
  home: <Dashboard tick={tick} />,
  mypage: <MyPage />,  // Add this
  // ...
};
```

### Step 3: Add to sidebar nav
Edit `src/components/Layout.tsx` and add to `NAV_ITEMS`:
```typescript
export const NAV_ITEMS = [
  // ...
  { id: 'mypage', icon: '⚡', label: 'My Page' },
];
```

Done! Now click it in the sidebar.

---

## 🛠️ Common Tasks

### Add a New Component
```typescript
// src/components/MyComponent.tsx
import React from 'react';
import { COLORS } from '../theme';

interface MyComponentProps {
  title: string;
  value: number;
}

export const MyComponent: React.FC<MyComponentProps> = ({ title, value }) => {
  return (
    <div style={{ color: COLORS.text }}>
      {title}: {value}
    </div>
  );
};
```

### Use a Chart
```typescript
import { AreaChart, Gauge, Sparkline } from '../components/Charts';

// In your component:
<AreaChart 
  data={[60, 120, 90, 150, ...]} 
  color={COLORS.accent} 
  height={80} 
  width={300} 
/>
```

### Access Theme Colors
```typescript
import { COLORS } from '../theme';

// Use anywhere
<div style={{ color: COLORS.green }}>Success</div>
```

### Create a Data-Updating Component
```typescript
import { useTick } from '../hooks';
import { useState, useEffect } from 'react';

export const Live: React.FC = () => {
  const tick = useTick(2500);
  const [value, setValue] = useState(0);

  useEffect(() => {
    // Update on each tick
    setValue(v => v + 1);
  }, [tick]);

  return <div>{value}</div>;
};
```

---

## 📚 Design Patterns

### Consistent Spacing
```typescript
gap: 8,      // Between items
padding: 16, // Inside containers
margin: 0,   // Not used (use gap/padding)
```

### Consistent Colors
```typescript
// Text
color: COLORS.text,       // Primary
color: COLORS.textDim,    // Secondary
color: COLORS.muted,      // Inactive

// Status
background: COLORS.green + '22',   // Light green
border: `1px solid ${COLORS.green}44`, // Subtle border
boxShadow: `0 0 8px ${COLORS.green}`, // Glow
```

### Consistent Layout
```typescript
// Full-height scrollable content
style={{ flex: 1, overflowY: 'auto' }}

// Fixed header
style={{ height: 44, flexShrink: 0 }}

// Grid layouts
style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}
```

---

## 🐛 Debugging

### Enable React DevTools
- Install React DevTools browser extension
- Inspect components in the DevTools panel

### Check Console
```bash
# In browser console
// Check color values:
console.log(COLORS);

// Check data:
console.log(sparklineData);
```

### Hot Reload
- Changes to components automatically reload
- State persists (if you're not changing component structure)
- If stuck, refresh browser manually

---

## 🚀 Before Committing

### 1. Run lint (if configured)
```bash
npm run lint
```

### 2. Type check
```bash
npm run type-check
```

### 3. Test in browser
- Check all interactive elements
- Verify colors/spacing
- Test on different zoom levels

### 4. Update docs
- Add to `PORTAL_DEVELOPMENT.md` if adding new pages
- Update component list if creating new components

---

## 📞 Help

### Q: Where's the API data coming from?
A: Currently simulated with `rand()` function. Replace with API calls in `useEffect` hooks.

### Q: How do I change colors?
A: Edit `src/theme.ts` COLORS object. All components reference these constants.

### Q: How do I add animations?
A: Use CSS inlin-key frames defined in `GlobalStyles` or `animation` property.

### Q: Components not showing?
A: Check:
1. Import statements correct?
2. Component spelled correctly in JSX?
3. Export statement in component file?
4. Parent has required styles (flex, grid)?

### Q: Styling not applying?
A: Remember:
1. All styles are inline
2. No CSS files used
3. Use COLORS constants
4. Check `style={}` prop

---

## 📖 Reference Docs

- **Design Reference**: `PORTAL_DESIGN_REFERENCE.md` - All 4 UI implementations
- **Development Tracker**: `PORTAL_DEVELOPMENT.md` - Detailed specs + progress
- **Main README**: `README.md` - Project overview

---

## 🎓 Learning Path

1. **Beginner**: Make Dashboard page tweaks
2. **Intermediate**: Create a new placeholder page
3. **Advanced**: Implement full Runners page
4. **Expert**: Integrate real API data

---

## ⚡ Pro Tips

- Use Cmd/Ctrl+Shift+C to inspect elements in browser
- Use `console.log()` to debug state
- Reference existing components for patterns
- Keep component files under 500 lines
- Import only what you use from theme/components
- Test on multiple zoom levels (100%, 125%, 150%)

Happy coding! 🚀

import React, { useState, createContext, useContext, Suspense } from 'react';
import { COLORS, COLORS_DARK, Theme } from './theme';
import { useTick } from './hooks';
import { GlobalStyles } from './components/UI';
import { Sidebar, StatusBar } from './components/Layout';
import { useMetrics } from './api/client';
import { useSocket } from './api/socket';

// Lazy-load page components for code splitting
const Dashboard = React.lazy(() => import('./pages/Dashboard').then(m => ({ default: m.Dashboard })));
const AgentStudio = React.lazy(() => import('./pages/AgentStudio').then(m => ({ default: m.AgentStudio })));
const Runners = React.lazy(() => import('./pages/Runners').then(m => ({ default: m.Runners })));
const Security = React.lazy(() => import('./pages/Security').then(m => ({ default: m.Security })));
const Billing = React.lazy(() => import('./pages/Billing').then(m => ({ default: m.Billing })));
const DeployMode = React.lazy(() => import('./pages/DeployMode').then(m => ({ default: m.DeployMode })));
const AIOracleContent = React.lazy(() => import('./pages/AIOracleContent').then(m => ({ default: m.AIOracleContent })));
const LiveMirrorCache = React.lazy(() => import('./pages/LiveMirrorCache').then(m => ({ default: m.LiveMirrorCache })));
const WindowsRunners = React.lazy(() => import('./pages/WindowsRunners').then(m => ({ default: m.WindowsRunners })));
const Settings = React.lazy(() => import('./pages/Settings').then(m => ({ default: m.Settings })));
const ComponentShowcase = React.lazy(() => import('./pages/ComponentShowcase').then(m => ({ default: m.ComponentShowcase })));
const RepoFunctions = React.lazy(() => import('./pages/RepoFunctions').then(m => ({ default: m.RepoFunctions })));
const Observability = React.lazy(() => import('./pages/Observability').then(m => ({ default: m.Observability })));
const LandingPage = React.lazy(() => import('./pages/LandingPage').then(m => ({ default: m.LandingPage })));

/**
 * Theme Context for global theme management
 */
const ThemeContext = createContext<{ theme: Theme; setTheme: (t: Theme) => void }>({
  theme: 'light',
  setTheme: () => {},
});

export const useTheme = () => useContext(ThemeContext);

/**
 * Loading fallback component
 */
const LoadingPage = () => (
  <div
    style={{
      flex: 1,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      flexDirection: 'column',
      gap: 12,
    }}
  >
    <div style={{ fontSize: 28, animation: 'spin 1s linear infinite' }}>⚡</div>
    <div style={{ fontSize: 14, fontWeight: 500 }}>
      Loading page...
    </div>
  </div>
);

/**
 * Placeholder for other pages
 */
const PlaceholderPage = ({ title }: { title: string }) => (
  <div
    style={{
      flex: 1,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      flexDirection: 'column',
      gap: 8,
    }}
  >
    <div style={{ fontSize: 36 }}>🔧</div>
    <div style={{ fontSize: 16, fontWeight: 700 }}>
      {title}
    </div>
    <div style={{ fontSize: 12 }}>Coming soon...</div>
  </div>
);

/**
 * Main App Component
 */
function App() {
  const [activeTab, setActiveTab] = useState('landing');
  const [theme, setTheme] = useState<Theme>('light');
  const colors = theme === 'light' ? COLORS : COLORS_DARK;
  
  // Dashboard-specific tick — only Dashboard uses this
  const tick = useTick(2500);

  // Initialize real-time metrics
  useMetrics({ interval: 5000 });
  
  // Initialize Phase 2 WebSocket listener
  useSocket({ url: 'http://localhost:9090' });

  /**
   * Render active page only to prevent memory leaks from unused components.
   * Only the active tab component is instantiated, not all pages at once.
   */
  const renderActivePage = () => {
    switch (activeTab) {
      case 'landing':
        return <LandingPage />
      case 'home':
        return <Dashboard tick={tick} />
      case 'observability':
        return <Observability />
      case 'agents':
        return <AgentStudio />
      case 'deploy':
        return <DeployMode />
      case 'runners':
        return <Runners />
      case 'oracle':
        return <AIOracleContent />
      case 'cache':
        return <LiveMirrorCache />
      case 'security':
        return <Security />
      case 'windows':
        return <WindowsRunners />
      case 'billing':
        return <Billing />
      case 'showcase':
        return <ComponentShowcase />
      case 'functions':
        return <RepoFunctions />
      case 'settings':
        return <Settings />
      default:
        return <PlaceholderPage title="Unknown Page" />
    }
  }

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      <div
        style={{
          display: 'flex',
          height: '100vh',
          background: colors.bg,
          fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, sans-serif",
          color: colors.text,
          overflow: 'hidden',
          transition: 'background 0.3s ease, color 0.3s ease',
        }}
      >
        <GlobalStyles theme={theme} />
        <Sidebar active={activeTab} setActive={setActiveTab} theme={theme} />
        <div
          style={{
            flex: 1,
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden',
          }}
        >
          <StatusBar theme={theme} setTheme={setTheme} />
          <div
            style={{
              flex: 1,
              overflow: 'hidden',
              display: 'flex',
            }}
          >
            <Suspense fallback={<LoadingPage />}>
              {renderActivePage()}
            </Suspense>
          </div>
        </div>
      </div>
    </ThemeContext.Provider>
  );
}

export default App;

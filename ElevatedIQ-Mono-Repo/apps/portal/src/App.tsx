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
 * Main App Component
 */
function App() {
  const [activeTab, setActiveTab] = useState('landing');
  const [theme, setTheme] = useState<Theme>('light');
  const tick = useTick(2500);
  const colors = theme === 'light' ? COLORS : COLORS_DARK;

  // Initialize real-time metrics
  useMetrics({ interval: 5000 });
  
  // Initialize Phase 2 WebSocket listener
  useSocket({ url: 'http://localhost:9090' });

  // Loading fallback component
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
      <div style={{ fontSize: 14, fontWeight: 500, color: COLORS.text }}>
        Loading page...
      </div>
    </div>
  );

  // Placeholder for other pages
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
      <div style={{ fontSize: 16, fontWeight: 700, color: COLORS.text }}>
        {title}
      </div>
      <div style={{ fontSize: 12, color: COLORS.muted }}>Coming soon...</div>
    </div>
  );

  const pages: Record<string, React.ReactNode> = {
    landing: <LandingPage />,
    home: <Dashboard tick={tick} />,
    observability: <Observability />,
    agents: <AgentStudio />,
    deploy: <DeployMode />,
    runners: <Runners />,
    oracle: <AIOracleContent />,
    cache: <LiveMirrorCache />,
    security: <Security />,
    windows: <WindowsRunners />,
    billing: <Billing />,
    showcase: <ComponentShowcase />,
    functions: <RepoFunctions />,
    settings: <Settings />,
  };

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
              {pages[activeTab] || <PlaceholderPage title="Unknown Page" />}
            </Suspense>
          </div>
        </div>
      </div>
    </ThemeContext.Provider>
  );
}

export default App;

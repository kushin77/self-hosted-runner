import React, { useState, lazy, Suspense } from 'react';
import { COLORS } from './theme';
import { useTick } from './hooks';
import { GlobalStyles } from './components/UI';
import { Sidebar, StatusBar } from './components/Layout';
import { Dashboard } from './pages/Dashboard';
import { AgentStudio } from './pages/AgentStudio';
import { DeployMode } from './pages/DeployMode';
import { Runners } from './pages/Runners';
import { TCOCalculator } from './pages/TCOCalculator';
import { Security } from './pages/Security';

/**
 * Main App Component
 */
function App() {
  const [activeTab, setActiveTab] = useState('home');
  const tick = useTick(2500);

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
    home: <Dashboard tick={tick} />,
    agents: <AgentStudio />,
    deploy: <DeployMode />,
      events: (
        <Suspense fallback={<div>Loading...</div>}>
          {React.createElement(lazy(() => import('./pages/LiveEvents')))}
        </Suspense>
      ),
    runners: <Runners tick={tick} />,
    oracle: <PlaceholderPage title="AI Oracle" />,
    cache: <PlaceholderPage title="LiveMirror Cache" />,
    security: <Security />,
    windows: <PlaceholderPage title="Windows Runners" />,
    billing: <TCOCalculator />,
    settings: <PlaceholderPage title="Settings" />,
  };

  return (
    <div
      style={{
        display: 'flex',
        height: '100vh',
        background: COLORS.bg,
        fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, sans-serif",
        color: COLORS.text,
        overflow: 'hidden',
      }}
    >
      <GlobalStyles />
      <Sidebar active={activeTab} setActive={setActiveTab} />
      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}
      >
        <StatusBar />
        <div
          style={{
            flex: 1,
            overflow: 'hidden',
            display: 'flex',
          }}
        >
          {pages[activeTab] || <PlaceholderPage title="Unknown Page" />}
        </div>
      </div>
    </div>
  );
}

export default App;

import React, { useState } from 'react';
import { COLORS } from './theme';
import { useTick } from './hooks';
import { GlobalStyles } from './components/UI';
import { Sidebar, StatusBar } from './components/Layout';
import { Dashboard } from './pages/Dashboard';
import { AgentStudio } from './pages/AgentStudio';
import { Runners } from './pages/Runners';
import { Security } from './pages/Security';
import { Billing } from './pages/Billing';
import { DeployMode } from './pages/DeployMode';
import { AIOracleContent } from './pages/AIOracleContent';
import { LiveMirrorCache } from './pages/LiveMirrorCache';
import { WindowsRunners } from './pages/WindowsRunners';
import { Settings } from './pages/Settings';

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
    home: <Dashboard />,
    agents: <AgentStudio />,
    deploy: <DeployMode />,
    runners: <Runners />,
    oracle: <AIOracleContent />,
    cache: <LiveMirrorCache />,
    security: <Security />,
    windows: <WindowsRunners />,
    billing: <Billing />,
    settings: <Settings />,
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

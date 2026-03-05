import React, { useState, createContext, useContext } from 'react';
import { COLORS, COLORS_DARK, Theme } from './theme';
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
import { ComponentShowcase } from './pages/ComponentShowcase';
import { RepoFunctions } from './pages/RepoFunctions';

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
  const [activeTab, setActiveTab] = useState('home');
  const [theme, setTheme] = useState<Theme>('light');
  const tick = useTick(2500);
  const colors = theme === 'light' ? COLORS : COLORS_DARK;

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
            {pages[activeTab] || <PlaceholderPage title="Unknown Page" />}
          </div>
        </div>
      </div>
    </ThemeContext.Provider>
  );
}

export default App;

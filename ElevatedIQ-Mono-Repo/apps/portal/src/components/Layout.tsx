import React from 'react';
import { COLORS } from '../theme';
import { Pill, GlowDot } from './UI';

/**
 * Navigation items for sidebar
 */
type NavItem = { id: string; icon: string; label: string; badge?: string };

export const NAV_ITEMS: NavItem[] = [
  { id: 'home', icon: '⚡', label: 'Dashboard' },
  { id: 'agents', icon: '🧠', label: 'Agent Studio', badge: 'NEW' },
  { id: 'deploy', icon: '🚀', label: 'Deploy Mode' },
  { id: 'runners', icon: '🖥', label: 'Runners' },
  { id: 'oracle', icon: '🔮', label: 'AI Oracle' },
  { id: 'cache', icon: '💾', label: 'LiveMirror Cache' },
  { id: 'security', icon: '🛡', label: 'Security Layer' },
  { id: 'windows', icon: '🪟', label: 'Windows Runners', badge: 'BETA' },
  { id: 'billing', icon: '💳', label: 'Billing & TCO' },
  { id: 'settings', icon: '⚙', label: 'Settings' },
];

/**
 * Sidebar - Main navigation component
 */
interface SidebarProps {
  active: string;
  setActive: (id: string) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ active, setActive }) => {
  return (
    <div
      style={{
        width: 210,
        background: COLORS.surface,
        borderRight: `1px solid ${COLORS.border}`,
        display: 'flex',
        flexDirection: 'column',
        flexShrink: 0,
        overflow: 'hidden',
      }}
    >
      {/* Header */}
      <div
        style={{
          padding: '16px 16px 10px',
          borderBottom: `1px solid ${COLORS.border}`,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: 7,
              background: `linear-gradient(135deg, ${COLORS.accent}, ${COLORS.purple})`,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 14,
              boxShadow: `0 0 14px ${COLORS.accentGlow}`,
            }}
          >
            ⚡
          export const NAV_ITEMS = [
                color: COLORS.text,
                letterSpacing: '-0.01em',
              }}
            >
              RunnerCloud
            </div>
            <div
              style={{
                fontSize: 9,
                color: COLORS.muted,
          ];
              }}
            >
              acme-corp · BYOC + Managed
            </div>
          </div>
        </div>
        <div style={{ marginTop: 10, display: 'flex', gap: 6 }}>
          <Pill color="green">● Live</Pill>
          <Pill color="purple">AI Active</Pill>
        </div>
      </div>

      {/* Nav Items */}
      <div
        style={{
          flex: 1,
          overflowY: 'auto',
          padding: '8px 0',
        }}
      >
        {NAV_ITEMS.map((item) => (
          <button
            key={item.id}
            onClick={() => setActive(item.id)}
            style={{
              width: '100%',
              background:
                active === item.id ? COLORS.accent + '18' : 'transparent',
              border: 'none',
              borderLeft:
                active === item.id
                  ? `2px solid ${COLORS.accent}`
                  : '2px solid transparent',
              color: active === item.id ? COLORS.accent : COLORS.textDim,
              padding: '9px 14px',
              textAlign: 'left',
              cursor: 'pointer',
              fontSize: 12,
              fontWeight: active === item.id ? 700 : 400,
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              transition: 'all 0.2s ease',
            }}
          >
            <span style={{ fontSize: 13 }}>{item.icon}</span>
            <span style={{ flex: 1 }}>{item.label}</span>
            {item.badge && (
              <span
                style={{
                  fontSize: 8,
                  background:
                    item.badge === 'BETA' ? COLORS.yellow + '33' : COLORS.green + '33',
                  color: item.badge === 'BETA' ? COLORS.yellow : COLORS.green,
                  border: `1px solid ${
                    item.badge === 'BETA' ? COLORS.yellow : COLORS.green
                  }44`,
                  borderRadius: 3,
                  padding: '1px 4px',
                  fontWeight: 800,
                  letterSpacing: '0.05em',
                }}
              >
                {item.badge}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Cost Widget */}
      <div
        style={{
          padding: '12px 14px',
          borderTop: `1px solid ${COLORS.border}`,
        }}
      >
        <div
          style={{
            background: COLORS.green + '11',
            border: `1px solid ${COLORS.green}33`,
            borderRadius: 6,
            padding: '8px 10px',
          }}
        >
          <div
            style={{
              fontSize: 9,
              color: COLORS.green,
              fontWeight: 700,
              letterSpacing: '0.07em',
            }}
          >
            THIS MONTH
          </div>
          <div
            style={{
              fontSize: 15,
              fontWeight: 800,
              color: COLORS.text,
              marginTop: 2,
            }}
          >
            $847.20
          </div>
          <div
            style={{
              fontSize: 9,
              color: COLORS.muted,
              marginTop: 1,
            }}
          >
            ↓ 79% vs GitHub hosted
          </div>
        </div>
      </div>
    </div>
  );
};

/**
 * StatusBar - Top bar with live status
 */
interface StatusBarProps {
  agentsActive?: number;
  runners?: number;
  status?: 'nominal' | 'warning' | 'critical';
}

export const StatusBar: React.FC<StatusBarProps> = ({
  agentsActive = 4,
  runners = 482,
  status = 'nominal',
}) => {
  const statusColor = {
    nominal: COLORS.green,
    warning: COLORS.yellow,
    critical: COLORS.red,
  }[status];

  return (
    <div
      style={{
        height: 40,
        background: COLORS.surface,
        borderBottom: `1px solid ${COLORS.border}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 20px',
        flexShrink: 0,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <GlowDot color={statusColor} size={6} />
        <span
          style={{
            fontSize: 11,
            color: COLORS.muted,
          }}
        >
          Live · 2.5s refresh
        </span>
      </div>
      <div
        style={{
          display: 'flex',
          gap: 16,
          fontSize: 11,
          color: COLORS.muted,
        }}
      >
        <span>{agentsActive} agents active</span>
        <span>{runners} runners</span>
        <span style={{ color: statusColor }}>
          {status === 'nominal'
            ? 'All systems nominal'
            : status === 'warning'
            ? 'Systems warming'
            : 'Critical issues'}
        </span>
      </div>
    </div>
  );
};

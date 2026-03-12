import React, { useState, useEffect } from 'react'
import './styles.css'

// Define colors for better organization
const COLORS = {
  primary: '#6366f1',
  success: '#22c55e',
  danger: '#ef4444',
  warning: '#f59e0b',
  background: '#0f172a',
  surface: '#1a1f35',
  text: '#e2e8f0',
  textSecond: '#94a3b8'
}

interface NavItem {
  id: string
  label: string
  icon: string
  sub?: string[]
}

interface Stat {
  label: string
  value: string
  delta: string
  icon: string
  color: string
}

interface PipelineStatus {
  id: string
  name: string
  version: string
  environment: string
  status: 'success' | 'running' | 'failed'
  timestamp: string
}

interface Deployment {
  id: string
  name: string
  version: string
  environment: string
  status: 'healthy' | 'degraded' | 'offline'
  uptime: string
}

interface Secret {
  id: string
  name: string
  type: string
  status: 'active' | 'rotating' | 'expired'
  expiresIn: string
  lastRotated: string
}

const NAV_ITEMS: NavItem[] = [
  { id: 'dashboard', label: 'Dashboard', icon: '◎' },
  { id: 'deployments', label: 'Deployments', icon: '⬆' },
  { id: 'pipelines', label: 'Pipelines', icon: '⟳' },
  { id: 'secrets', label: 'Secrets', icon: '🔑' },
  { id: 'observability', label: 'Observability', icon: '📊' },
  { id: 'diagrams', label: 'Diagrams', icon: '🎨', sub: ['Architecture', 'Troubleshooting'] },
  { id: 'infrastructure', label: 'Infrastructure', icon: '🏗️' },
  { id: 'settings', label: 'Settings', icon: '⚙️' }
]

const STATS: Stat[] = [
  { label: 'Healthy Services', value: '24', delta: '+2 this week', icon: '✓', color: COLORS.success },
  { label: 'Pipelines', value: '156', delta: '12 running', icon: '⟳', color: COLORS.primary },
  { label: 'Secrets', value: '87', delta: '3 expiring soon', icon: '🔑', color: COLORS.warning },
  { label: 'Uptime', value: '99.98%', delta: 'Last 30 days', icon: '◎', color: COLORS.success }
]

const PIPELINES: PipelineStatus[] = [
  { id: '1', name: 'Backend Service', version: 'v1.2.3', environment: 'prod', status: 'success', timestamp: '3h ago' },
  { id: '2', name: 'Frontend App', version: 'v2.1.0', environment: 'staging', status: 'running', timestamp: '12m ago' },
  { id: '3', name: 'API Gateway', version: 'v0.9.1', environment: 'dev', status: 'failed', timestamp: '2h ago' }
]

const DEPLOYMENTS: Deployment[] = [
  { id: '1', name: 'production', version: 'v4.12.1', environment: 'prod', status: 'healthy', uptime: '99.98%' },
  { id: '2', name: 'staging', version: 'v4.13.0-rc2', environment: 'staging', status: 'healthy', uptime: '99.95%' },
  { id: '3', name: 'review/feat-oidc', version: 'v4.13.0-dev', environment: 'dev', status: 'degraded', uptime: '95.2%' }
]

const SECRETS: Secret[] = [
  { id: '1', name: 'primary-db-credentials', type: 'database', status: 'active', expiresIn: '70d', lastRotated: '20d ago' },
  { id: '2', name: 'github-token', type: 'api-key', status: 'rotating', expiresIn: '25d', lastRotated: '5d ago' },
  { id: '3', name: 'tls-certificate', type: 'certificate', status: 'active', expiresIn: '180d', lastRotated: '60d ago' }
]

function Portal() {
  const [activeNav, setActiveNav] = useState('dashboard')
  const [expandedNav, setExpandedNav] = useState<string | null>(null)
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [stats, setStats] = useState<Stat[]>(STATS)
  const [pipelines, setPipelines] = useState<PipelineStatus[]>(PIPELINES)

  useEffect(() => {
    // Initialize
    console.log('Portal initialized')
  }, [])

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'success':
      case 'healthy':
      case 'active':
        return COLORS.success
      case 'running':
      case 'rotating':
        return COLORS.primary
      case 'failed':
      case 'offline':
      case 'expired':
        return COLORS.danger
      case 'degraded':
      case 'warning':
        return COLORS.warning
      default:
        return COLORS.textSecond
    }
  }

  const renderDashboardContent = () => (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
      {/* Stats Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: 16 }}>
        {stats.map(stat => (
          <div
            key={stat.label}
            style={{
              padding: 20,
              borderRadius: 8,
              background: COLORS.surface,
              border: `1px solid ${COLORS.textSecond}20`
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div>
                <div style={{ fontSize: 12, color: COLORS.textSecond, marginBottom: 8 }}>{stat.label}</div>
                <div style={{ fontSize: 32, fontWeight: 600, color: stat.color }}>{stat.value}</div>
                <div style={{ fontSize: 12, color: COLORS.textSecond, marginTop: 8 }}>{stat.delta}</div>
              </div>
              <div style={{ fontSize: 32, color: stat.color }}>{stat.icon}</div>
            </div>
          </div>
        ))}
      </div>

      {/* Recent Pipelines */}
      <div style={{ padding: 20, borderRadius: 8, background: COLORS.surface, border: `1px solid ${COLORS.textSecond}20` }}>
        <h3 style={{ color: COLORS.text, marginBottom: 16, margin: '0 0 16px 0' }}>Recent Pipelines</h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {pipelines.map(p => (
            <div
              key={p.id}
              style={{
                padding: 12,
                borderRadius: 6,
                background: COLORS.background,
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center'
              }}
            >
              <div>
                <div style={{ fontWeight: 500, color: COLORS.text }}>{p.name}</div>
                <div style={{ fontSize: 12, color: COLORS.textSecond }}>{p.version} · {p.environment}</div>
              </div>
              <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                <span style={{ color: getStatusColor(p.status), fontWeight: 600 }}>
                  {p.status === 'success' ? '✓' : p.status === 'running' ? '⟳' : '✕'} {p.status}
                </span>
                <span style={{ fontSize: 12, color: COLORS.textSecond }}>{p.timestamp}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )

  const renderDeploymentsContent = () => (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {DEPLOYMENTS.map(dep => (
        <div
          key={dep.id}
          style={{
            padding: 16,
            borderRadius: 8,
            background: COLORS.surface,
            border: `1px solid ${COLORS.textSecond}20`
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start' }}>
            <div>
              <h3 style={{ color: COLORS.text, margin: 0 }}>{dep.name}</h3>
              <p style={{ color: COLORS.textSecond, margin: '8px 0 0 0', fontSize: 14 }}>
                Version: {dep.version} | Environment: {dep.environment}
              </p>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ color: getStatusColor(dep.status), fontWeight: 600, marginBottom: 4 }}>
                {dep.status === 'healthy' ? '✓' : '✕'} {dep.status.toUpperCase()}
              </div>
              <div style={{ color: COLORS.textSecond, fontSize: 12 }}>Uptime: {dep.uptime}</div>
            </div>
          </div>
        </div>
      ))}
    </div>
  )

  const renderSecretsContent = () => (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {SECRETS.map(secret => (
        <div
          key={secret.id}
          style={{
            padding: 16,
            borderRadius: 8,
            background: COLORS.surface,
            border: `1px solid ${COLORS.textSecond}20`
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start' }}>
            <div style={{ flex: 1 }}>
              <h3 style={{ color: COLORS.text, margin: 0 }}>{secret.name}</h3>
              <p style={{ color: COLORS.textSecond, margin: '8px 0 0 0', fontSize: 14 }}>
                Type: {secret.type} | Last rotated: {secret.lastRotated}
              </p>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ color: getStatusColor(secret.status), fontWeight: 600, marginBottom: 4 }}>
                {secret.status.toUpperCase()}
              </div>
              <div style={{ color: COLORS.textSecond, fontSize: 12 }}>Expires: {secret.expiresIn}</div>
            </div>
          </div>
        </div>
      ))}
    </div>
  )

  return (
    <div style={{ display: 'flex', height: '100vh', background: COLORS.background }}>
      {/* Sidebar */}
      <div
        style={{
          width: sidebarCollapsed ? 80 : 260,
          background: COLORS.surface,
          borderRight: `1px solid ${COLORS.textSecond}20`,
          padding: '16px',
          display: 'flex',
          flexDirection: 'column',
          transition: 'width 0.2s'
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 24 }}>
          <div
            style={{
              width: 36,
              height: 36,
              borderRadius: 6,
              background: COLORS.primary,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#fff',
              fontWeight: 600
            }}
          >
            ◈
          </div>
          {!sidebarCollapsed && (
            <div>
              <div style={{ fontWeight: 600, color: COLORS.text }}>Nexus</div>
              <div style={{ fontSize: 11, color: COLORS.textSecond }}>Control Plane</div>
            </div>
          )}
        </div>

        <nav style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6 }}>
          {NAV_ITEMS.map(item => (
            <div key={item.id}>
              <div
                onClick={() => {
                  setActiveNav(item.id)
                  if (item.sub) {
                    setExpandedNav(expandedNav === item.id ? null : item.id)
                  }
                }}
                style={{
                  padding: sidebarCollapsed ? '8px' : '10px 12px',
                  borderRadius: 6,
                  cursor: 'pointer',
                  background: activeNav === item.id ? COLORS.primary : 'transparent',
                  color: activeNav === item.id ? '#fff' : COLORS.textSecond,
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10,
                  fontSize: 14,
                  transition: 'all 0.2s'
                }}
              >
                <span>{item.icon}</span>
                {!sidebarCollapsed && (
                  <>
                    <span>{item.label}</span>
                    {item.sub && <span style={{ marginLeft: 'auto' }}>{expandedNav === item.id ? '▼' : '▶'}</span>}
                  </>
                )}
              </div>

              {!sidebarCollapsed && item.sub && expandedNav === item.id && (
                <div style={{ paddingLeft: 20, display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                  {item.sub.map(sub => (
                    <div
                      key={sub}
                      style={{
                        padding: '6px 8px',
                        borderRadius: 4,
                        cursor: 'pointer',
                        color: COLORS.textSecond,
                        fontSize: 13,
                        transition: 'all 0.2s',
                        ':hover': { color: COLORS.text }
                      }}
                    >
                      {sub}
                    </div>
                  ))}
                </div>
              )}
            </div>
          ))}
        </nav>

        <button
          onClick={() => setSidebarCollapsed(!sidebarCollapsed)}
          style={{
            padding: '8px',
            borderRadius: 6,
            border: 'none',
            background: COLORS.primary,
            color: '#fff',
            cursor: 'pointer',
            marginTop: 'auto',
            fontSize: 16
          }}
        >
          {sidebarCollapsed ? '▶' : '◀'}
        </button>
      </div>

      {/* Main Content */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* Top Bar */}
        <div
          style={{
            padding: '16px 24px',
            borderBottom: `1px solid ${COLORS.textSecond}20`,
            display: 'flex',
            gap: 16,
            alignItems: 'center'
          }}
        >
          <input
            type="text"
            placeholder="Search..."
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            style={{
              flex: 1,
              padding: '8px 12px',
              borderRadius: 6,
              border: `1px solid ${COLORS.textSecond}20`,
              background: COLORS.background,
              color: COLORS.text,
              fontSize: 14
            }}
          />
          <div style={{ display: 'flex', gap: 12, color: COLORS.textSecond }}>
            <button style={{ background: 'none', border: 'none', color: COLORS.textSecond, cursor: 'pointer', fontSize: 18 }}>🔔</button>
            <button style={{ background: 'none', border: 'none', color: COLORS.textSecond, cursor: 'pointer', fontSize: 18 }}>👤</button>
          </div>
        </div>

        {/* Content Area */}
        <div style={{ flex: 1, overflow: 'auto', padding: '24px' }}>
          <h1 style={{ color: COLORS.text, marginBottom: 24, margin: '0 0 24px 0' }}>
            {NAV_ITEMS.find(n => n.id === activeNav)?.label || 'Dashboard'}
          </h1>

          {activeNav === 'dashboard' && renderDashboardContent()}
          {activeNav === 'deployments' && renderDeploymentsContent()}
          {activeNav === 'secrets' && renderSecretsContent()}

          {!['dashboard', 'deployments', 'secrets'].includes(activeNav) && (
            <div
              style={{
                padding: 48,
                textAlign: 'center',
                color: COLORS.textSecond
              }}
            >
              <div style={{ fontSize: 48, marginBottom: 16 }}>
                {NAV_ITEMS.find(n => n.id === activeNav)?.icon}
              </div>
              <p>
                {activeNav === 'diagrams'
                  ? 'Draw.io diagram builder coming soon...'
                  : activeNav === 'pipelines'
                    ? 'Pipeline view coming soon...'
                    : activeNav === 'observability'
                      ? 'Observability dashboard coming soon...'
                      : activeNav === 'infrastructure'
                        ? 'Infrastructure management coming soon...'
                        : 'Settings page coming soon...'}
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export default Portal

import React, { useState } from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader, Pill, Button } from '../components/UI';

/**
 * Settings Page
 */
export const Settings: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'profile' | 'notifications' | 'api' | 'team' | 'billing'>('profile');
  const [theme, setTheme] = useState<'auto' | 'light' | 'dark'>('auto');
  const [emailNotif, setEmailNotif] = useState(true);
  const [slackNotif, setSlackNotif] = useState(true);

  const tabs: Array<{ id: 'profile' | 'notifications' | 'api' | 'team' | 'billing'; label: string; icon: string }> = [
    { id: 'profile', label: 'Profile', icon: '👤' },
    { id: 'notifications', label: 'Notifications', icon: '🔔' },
    { id: 'api', label: 'API & Tokens', icon: '🔑' },
    { id: 'team', label: 'Team', icon: '👥' },
    { id: 'billing', label: 'Billing', icon: '💳' },
  ];

  return (
    <div style={{ flex: 1, padding: 20, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 800, color: COLORS.text, marginBottom: 4 }}>
          Settings
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          Account preferences, notifications, API management, team & billing
        </div>
      </div>

      {/* Tab Navigation */}
      <div style={{ display: 'flex', gap: 8, borderBottom: `1px solid ${COLORS.border}`, marginBottom: 12, overflowX: 'auto' }}>
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            style={{
              background: 'transparent',
              border: 'none',
              borderBottom: activeTab === tab.id ? `2px solid ${COLORS.accent}` : '2px solid transparent',
              color: activeTab === tab.id ? COLORS.accent : COLORS.textDim,
              padding: '8px 12px',
              fontSize: 11,
              fontWeight: activeTab === tab.id ? 700 : 400,
              cursor: 'pointer',
              whiteSpace: 'nowrap',
              transition: 'all 0.2s ease',
            }}
          >
            {tab.icon} {tab.label}
          </button>
        ))}
      </div>

      {/* Profile Tab */}
      {activeTab === 'profile' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <Panel>
            <PanelHeader icon="👤" title="Profile Information" color={COLORS.cyan} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
              {[
                { label: 'Full Name', value: 'Alex Kumar' },
                { label: 'Email', value: 'alex@elevatediq.com' },
                { label: 'Organization', value: 'ElevatedIQ Inc.' },
                { label: 'Role', value: 'Platform Engineer' },
              ].map((field) => (
                <div key={field.label}>
                  <label style={{ fontSize: 10, color: COLORS.muted, textTransform: 'uppercase', letterSpacing: '0.08em', display: 'block', marginBottom: 4 }}>
                    {field.label}
                  </label>
                  <input
                    type="text"
                    defaultValue={field.value}
                    style={{
                      width: '100%',
                      background: COLORS.bg,
                      border: `1px solid ${COLORS.border}`,
                      borderRadius: 4,
                      padding: '6px 10px',
                      color: COLORS.text,
                      fontSize: 11,
                      outline: 'none',
                    }}
                  />
                </div>
              ))}
            </div>
          </Panel>

          <Panel>
            <PanelHeader icon="🎨" title="Display Preferences" color={COLORS.purple} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div>
                <label style={{ fontSize: 10, color: COLORS.muted, textTransform: 'uppercase', letterSpacing: '0.08em', display: 'block', marginBottom: 6 }}>
                  Theme
                </label>
                <div style={{ display: 'flex', gap: 8 }}>
                  {(['auto', 'light', 'dark'] as const).map((t) => (
                    <button
                      key={t}
                      onClick={() => setTheme(t)}
                      style={{
                        background: theme === t ? COLORS.accent + '22' : COLORS.border,
                        border: theme === t ? `1px solid ${COLORS.accent}` : '1px solid transparent',
                        color: theme === t ? COLORS.accent : COLORS.textDim,
                        borderRadius: 4,
                        padding: '6px 12px',
                        fontSize: 10,
                        cursor: 'pointer',
                        fontWeight: theme === t ? 700 : 400,
                        textTransform: 'capitalize',
                      }}
                    >
                      {t}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label style={{ fontSize: 10, color: COLORS.muted, marginBottom: 4, display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                  <input type="checkbox" defaultChecked style={{ width: 16, height: 16 }} />
                  <span>Compact view</span>
                </label>
              </div>
              <div>
                <label style={{ fontSize: 10, color: COLORS.muted, marginBottom: 4, display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                  <input type="checkbox" defaultChecked style={{ width: 16, height: 16 }} />
                  <span>Show tooltips</span>
                </label>
              </div>
            </div>
          </Panel>

          <Panel>
            <PanelHeader icon="🔐" title="Security" color={COLORS.red} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
              <button
                style={{
                  background: COLORS.red + '22',
                  border: `1px solid ${COLORS.red}`,
                  color: COLORS.red,
                  borderRadius: 4,
                  padding: '8px 12px',
                  fontSize: 11,
                  fontWeight: 700,
                  cursor: 'pointer',
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em',
                }}
              >
                Change Password
              </button>
              <button
                style={{
                  background: COLORS.red + '22',
                  border: `1px solid ${COLORS.red}`,
                  color: COLORS.red,
                  borderRadius: 4,
                  padding: '8px 12px',
                  fontSize: 11,
                  fontWeight: 700,
                  cursor: 'pointer',
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em',
                }}
              >
                Setup Two-Factor Authentication
              </button>
            </div>
          </Panel>
        </div>
      )}

      {/* Notifications Tab */}
      {activeTab === 'notifications' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <Panel>
            <PanelHeader icon="📧" title="Email Notifications" color={COLORS.yellow} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[
                { label: 'Job Failures', desc: 'Get notified on failed jobs' },
                { label: 'Security Alerts', desc: 'Critical security findings' },
                { label: 'Billing Alerts', desc: 'When usage exceeds threshold' },
                { label: 'Weekly Digest', desc: 'Summary every Monday' },
              ].map((item) => (
                <label
                  key={item.label}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 8,
                    padding: '8px 0',
                    borderBottom: `1px solid ${COLORS.border}`,
                    cursor: 'pointer',
                  }}
                >
                  <input
                    type="checkbox"
                    defaultChecked={emailNotif}
                    onChange={(e) => setEmailNotif(e.target.checked)}
                    style={{ width: 18, height: 18 }}
                  />
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                      {item.label}
                    </div>
                    <div style={{ fontSize: 9, color: COLORS.muted }}>
                      {item.desc}
                    </div>
                  </div>
                </label>
              ))}
            </div>
          </Panel>

          <Panel>
            <PanelHeader icon="💬" title="Slack Integration" color={COLORS.blue} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700, marginBottom: 2 }}>
                    Connected Workspace
                  </div>
                  <div style={{ fontSize: 10, color: COLORS.muted }}>
                    elevatediq.slack.com
                  </div>
                </div>
                <Pill color="green" sm>
                  ✓ Connected
                </Pill>
              </div>

              <div style={{ borderTop: `1px solid ${COLORS.border}`, paddingTop: 8 }}>
                <label
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 8,
                    cursor: 'pointer',
                  }}
                >
                  <input
                    type="checkbox"
                    defaultChecked={slackNotif}
                    onChange={(e) => setSlackNotif(e.target.checked)}
                    style={{ width: 18, height: 18 }}
                  />
                  <span style={{ fontSize: 11, color: COLORS.text }}>
                    Send alerts to #ci-notifications
                  </span>
                </label>
              </div>

              <button
                style={{
                  background: COLORS.red + '22',
                  border: `1px solid ${COLORS.red}`,
                  color: COLORS.red,
                  borderRadius: 4,
                  padding: '6px 12px',
                  fontSize: 10,
                  fontWeight: 700,
                  cursor: 'pointer',
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em',
                  marginTop: 8,
                }}
              >
                Disconnect Workspace
              </button>
            </div>
          </Panel>
        </div>
      )}

      {/* API & Tokens Tab */}
      {activeTab === 'api' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <Panel>
            <PanelHeader icon="🔑" title="API Tokens" color={COLORS.cyan} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[
                { name: 'github-runner-token', created: '2025-01-15', lastUsed: '2 minutes ago', status: 'active' },
                { name: 'deployment-webhook', created: '2024-12-01', lastUsed: '5 days ago', status: 'active' },
                { name: 'backup-api-key', created: '2024-11-20', lastUsed: 'Never', status: 'inactive' },
              ].map((token) => (
                <div
                  key={token.name}
                  style={{
                    background: COLORS.border,
                    borderRadius: 6,
                    padding: '10px',
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                  }}
                >
                  <div>
                    <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700, fontFamily: 'monospace', marginBottom: 4 }}>
                      {token.name}
                    </div>
                    <div style={{ fontSize: 9, color: COLORS.muted }}>
                      Created: {token.created} | Last used: {token.lastUsed}
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 6 }}>
                    <Pill color={token.status === 'active' ? 'green' : 'red'} sm>
                      {token.status}
                    </Pill>
                    <button
                      style={{
                        background: 'transparent',
                        border: `1px solid ${COLORS.red}`,
                        color: COLORS.red,
                        borderRadius: 4,
                        padding: '4px 8px',
                        fontSize: 9,
                        cursor: 'pointer',
                        fontWeight: 700,
                      }}
                    >
                      Revoke
                    </button>
                  </div>
                </div>
              ))}
              <button
                style={{
                  background: COLORS.accent,
                  color: '#000',
                  border: 'none',
                  borderRadius: 4,
                  padding: '8px 12px',
                  fontSize: 11,
                  fontWeight: 700,
                  cursor: 'pointer',
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em',
                  marginTop: 8,
                }}
              >
                Generate New Token
              </button>
            </div>
          </Panel>

          <Panel>
            <PanelHeader icon="📚" title="API Documentation" color={COLORS.green} />
            <div style={{ padding: '12px 14px' }}>
              <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 8 }}>
                Base URL
              </div>
              <div
                style={{
                  background: '#000',
                  border: `1px solid ${COLORS.border}`,
                  borderRadius: 4,
                  padding: '8px 10px',
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: COLORS.cyan,
                  marginBottom: 12,
                  wordBreak: 'break-all',
                }}
              >
                https://api.elevatediq.com/v1
              </div>
              <a
                href="#"
                style={{
                  color: COLORS.cyan,
                  textDecoration: 'none',
                  fontSize: 11,
                  fontWeight: 700,
                  display: 'inline-block',
                  marginBottom: 8,
                }}
              >
                View Full API Documentation →
              </a>
            </div>
          </Panel>
        </div>
      )}

      {/* Team Tab */}
      {activeTab === 'team' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <Panel>
            <PanelHeader icon="👥" title="Team Members" color={COLORS.green} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[
                { name: 'Alex Kumar', role: 'Admin', email: 'alex@elevatediq.com', joined: '3 months ago' },
                { name: 'Jordan Smith', role: 'Engineer', email: 'jordan@elevatediq.com', joined: '1 month ago' },
                { name: 'Casey Lee', role: 'Viewer', email: 'casey@elevatediq.com', joined: '2 weeks ago' },
              ].map((member) => (
                <div
                  key={member.email}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    padding: '8px 0',
                    borderBottom: `1px solid ${COLORS.border}`,
                  }}
                >
                  <div>
                    <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                      {member.name}
                    </div>
                    <div style={{ fontSize: 9, color: COLORS.muted }}>
                      {member.email} · Joined {member.joined}
                    </div>
                  </div>
                  <Pill color="blue" sm>
                    {member.role}
                  </Pill>
                </div>
              ))}
              <button
                style={{
                  background: COLORS.green,
                  color: '#000',
                  border: 'none',
                  borderRadius: 4,
                  padding: '8px 12px',
                  fontSize: 11,
                  fontWeight: 700,
                  cursor: 'pointer',
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em',
                  marginTop: 8,
                }}
              >
                Invite Team Member
              </button>
            </div>
          </Panel>
        </div>
      )}

      {/* Billing Tab */}
      {activeTab === 'billing' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <Panel>
            <PanelHeader icon="💳" title="Billing Information" color={COLORS.green} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
              {[
                { label: 'Current Plan', value: 'Professional ($1,299/month)' },
                { label: 'Billing Cycle', value: 'Monthly on the 1st' },
                { label: 'Next Invoice', value: 'April 1, 2025' },
                { label: 'Payment Method', value: '•••• •••• •••• 4242' },
              ].map((field) => (
                <div key={field.label}>
                  <label style={{ fontSize: 10, color: COLORS.muted, textTransform: 'uppercase', letterSpacing: '0.08em', display: 'block', marginBottom: 4 }}>
                    {field.label}
                  </label>
                  <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                    {field.value}
                  </div>
                </div>
              ))}
            </div>
          </Panel>

          <Panel>
            <PanelHeader icon="📜" title="Recent Invoices" color={COLORS.yellow} />
            <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
              {[
                { date: 'March 1, 2025', amount: '$1,299.00', status: 'Paid' },
                { date: 'February 1, 2025', amount: '$1,299.00', status: 'Paid' },
                { date: 'January 1, 2025', amount: '$1,299.00', status: 'Paid' },
              ].map((invoice) => (
                <div
                  key={invoice.date}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    padding: '8px 0',
                    borderBottom: `1px solid ${COLORS.border}`,
                  }}
                >
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                      {invoice.date}
                    </div>
                    <div style={{ fontSize: 9, color: COLORS.muted }}>
                      Invoice #{Math.random().toString(36).substr(2, 9).toUpperCase()}
                    </div>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.text }}>
                      {invoice.amount}
                    </div>
                    <Pill color="green" sm>
                      {invoice.status}
                    </Pill>
                  </div>
                </div>
              ))}
            </div>
          </Panel>
        </div>
      )}
    </div>
  );
};

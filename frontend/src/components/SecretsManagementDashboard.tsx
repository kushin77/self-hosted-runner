import React, { useEffect, useState, useCallback } from 'react';
import {
  BarChart, Bar, LineChart, Line, AreaChart, Area,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  PieChart, Pie, Cell
} from 'recharts';

/**
 * NexusShield Portal - Canonical Secrets Management UI
 * Features:
 * - Vault-primary provider hierarchy visualization
 * - Multi-provider health monitoring
 * - Credential migration interface
 * - Canonical sync management
 * - Immutable audit trail
 */

const SecretsManagementDashboard = ({ token }) => {
  const [activeTab, setActiveTab] = useState('overview');
  const [providers, setProviders] = useState([]);
  const [credentials, setCredentials] = useState([]);
  const [migrations, setMigrations] = useState([]);
  const [auditTrail, setAuditTrail] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selectedProvider, setSelectedProvider] = useState(null);

  // ========================================================================
  // DATA FETCHING
  // ========================================================================

  const fetchProvidersHealth = useCallback(async () => {
    try {
      const response = await fetch('/api/v1/secrets/health/all', {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await response.json();
      setProviders(data.providers || []);
      return data.providers || [];
    } catch (err) {
      console.error('Failed to fetch provider health:', err);
      setError(err.message);
      return [];
    }
  }, [token]);

  const fetchCredentials = useCallback(async () => {
    try {
      const response = await fetch('/api/v1/secrets/credentials', {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await response.json();
      setCredentials(data || []);
    } catch (err) {
      console.error('Failed to fetch credentials:', err);
    }
  }, [token]);

  const fetchMigrations = useCallback(async () => {
    try {
      const response = await fetch('/api/v1/secrets/migrations?limit=20', {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await response.json();
      setMigrations(data || []);
    } catch (err) {
      console.error('Failed to fetch migrations:', err);
    }
  }, [token]);

  const fetchAudit = useCallback(async () => {
    try {
      const response = await fetch('/api/v1/secrets/audit?limit=50', {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await response.json();
      setAuditTrail(data || []);
    } catch (err) {
      console.error('Failed to fetch audit trail:', err);
    }
  }, [token]);

  useEffect(() => {
    const loadData = async () => {
      setLoading(true);
      await Promise.all([
        fetchProvidersHealth(),
        fetchCredentials(),
        fetchMigrations(),
        fetchAudit()
      ]);
      setLoading(false);
    };

    loadData();
    const interval = setInterval(loadData, 30000); // Refresh every 30s
    return () => clearInterval(interval);
  }, [fetchProvidersHealth, fetchCredentials, fetchMigrations, fetchAudit]);

  // ========================================================================
  // EVENT HANDLERS
  // ========================================================================

  const handleStartMigration = async (sourceProvider) => {
    try {
      const response = await fetch('/api/v1/secrets/migrations/start', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          source_provider: sourceProvider,
          target_provider: 'vault',
          dry_run: false,
          parallel_jobs: 4
        })
      });
      const result = await response.json();
      alert(`✅ Migration started: ${result.migration_id}`);
      fetchMigrations();
    } catch (err) {
      alert(`❌ Migration failed: ${err.message}`);
    }
  };

  const handleRotateCredential = async (credentialId) => {
    try {
      const response = await fetch(`/api/v1/secrets/credentials/${credentialId}/rotate`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const result = await response.json();
      alert(`✅ Credential rotated: ${result.rotated_at}`);
      fetchCredentials();
    } catch (err) {
      alert(`❌ Rotation failed: ${err.message}`);
    }
  };

  const handleVerifyIntegrity = async () => {
    try {
      const response = await fetch('/api/v1/secrets/audit/verify', {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const result = await response.json();
      alert(`✅ Audit integrity verified: ${result.total_entries} entries`);
    } catch (err) {
      alert(`❌ Verification failed: ${err.message}`);
    }
  };

  // ========================================================================
  // RENDER FUNCTIONS
  // ========================================================================

  const ProviderHierarchyDisplay = () => (
    <div className="card" style={{ marginBottom: '2rem' }}>
      <h3 style={{ marginBottom: '1rem' }}>🏛️ Provider Hierarchy</h3>
      <p style={{ fontSize: '0.9rem', color: '#666', marginBottom: '1rem' }}>
        Vault-primary with automatic failover chain
      </p>
      
      <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '1rem' }}>
        {['vault', 'gsm', 'aws', 'azure'].map((providerName, idx) => {
          const providerData = providers.find(p => p.provider === providerName);
          const isHealthy = providerData?.healthy;
          const isPrimary = idx === 0;
          
          return (
            <div key={providerName} style={{ display: 'flex', alignItems: 'center' }}>
              <div
                style={{
                  padding: '8px 16px',
                  backgroundColor: isHealthy ? '#10b981' : '#ef4444',
                  color: 'white',
                  borderRadius: '4px',
                  fontWeight: 'bold',
                  textAlign: 'center',
                  minWidth: '100px',
                  border: isPrimary ? '3px solid #fbbf24' : 'none'
                }}
              >
                {providerName.toUpperCase()}
                <div style={{ fontSize: '0.75rem', marginTop: '2px' }}>
                  {isPrimary ? '⭐ PRIMARY' : `FALLBACK ${idx}`}
                </div>
              </div>
              {idx < 3 && <div style={{ margin: '0 10px' }}>→</div>}
            </div>
          );
        })}
      </div>
    </div>
  );

  const ProviderHealthCards = () => (
    <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: '1rem', marginBottom: '2rem' }}>
      {providers.map((provider) => (
        <div
          key={provider.provider}
          className="card"
          style={{
            cursor: 'pointer',
            border: selectedProvider?.provider === provider.provider ? '2px solid #3b82f6' : '1px solid #ddd',
            backgroundColor: selectedProvider?.provider === provider.provider ? '#f0f9ff' : 'white'
          }}
          onClick={() => setSelectedProvider(provider)}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start', marginBottom: '1rem' }}>
            <div>
              <h4 style={{ margin: 0, marginBottom: '0.5rem' }}>
                {provider.provider.toUpperCase()}
              </h4>
              <p style={{ margin: 0, fontSize: '0.9rem', color: '#666' }}>
                {['vault', 'gsm', 'aws', 'azure'].indexOf(provider.provider) === 0 ? '⭐ Primary' : 'Fallback'}
              </p>
            </div>
            <div
              style={{
                display: 'inline-block',
                width: '16px',
                height: '16px',
                borderRadius: '50%',
                backgroundColor: provider.healthy ? '#10b981' : '#ef4444'
              }}
            />
          </div>

          <div style={{ backgroundColor: '#f3f4f6', padding: '0.75rem', borderRadius: '4px', marginBottom: '1rem' }}>
            <div style={{ fontSize: '0.85rem', marginBottom: '0.25rem' }}>
              Status: <strong>{provider.status}</strong>
            </div>
            {provider.latency_ms && (
              <div style={{ fontSize: '0.85rem' }}>
                Latency: <strong>{provider.latency_ms.toFixed(2)}ms</strong>
              </div>
            )}
          </div>

          {provider.error && (
            <div style={{ fontSize: '0.75rem', color: '#ef4444', marginBottom: '0.5rem' }}>
              Error: {provider.error}
            </div>
          )}

          <button
            style={{
              width: '100%',
              padding: '6px 12px',
              backgroundColor: '#3b82f6',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              fontSize: '0.875rem'
            }}
            onClick={() => handleStartMigration(provider.provider)}
          >
            Migrate From {provider.provider.toUpperCase()}
          </button>
        </div>
      ))}
    </div>
  );

  const CredentialsTab = () => (
    <div>
      <div style={{ marginBottom: '1.5rem' }}>
        <h3>🔐 Credentials Registry</h3>
        <p style={{ color: '#666', marginBottom: '1rem' }}>
          All credentials are ephemeral and stored in Vault with automatic failover to GSM, AWS, and Azure
        </p>
      </div>

      {credentials.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '2rem' }}>
          <p>No credentials found</p>
        </div>
      ) : (
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse'}}>
            <thead>
              <tr style={{ backgroundColor: '#f3f4f6', borderBottom: '1px solid #ddd' }}>
                <th style={{ padding: '0.75rem', textAlign: 'left' }}>Name</th>
                <th style={{ padding: '0.75rem', textAlign: 'left' }}>Primary Provider</th>
                <th style={{ padding: '0.75rem', textAlign: 'left' }}>Status</th>
                <th style={{ padding: '0.75rem', textAlign: 'left' }}>Created</th>
                <th style={{ padding: '0.75rem', textAlign: 'left' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {credentials.map((cred) => (
                <tr key={cred.id} style={{ borderBottom: '1px solid #ddd' }}>
                  <td style={{ padding: '0.75rem' }}>{cred.name}</td>
                  <td style={{ padding: '0.75rem' }}>
                    <span style={{
                      display: 'inline-block',
                      padding: '0.25rem 0.75rem',
                      backgroundColor: '#dbeafe',
                      color: '#1e40af',
                      borderRadius: '4px',
                      fontSize: '0.85rem',
                      fontWeight: 'bold'
                    }}>
                      {cred.type.toUpperCase()}
                    </span>
                  </td>
                  <td style={{ padding: '0.75rem' }}>
                    {cred.migrated_to_primary ? (
                      <span style={{ color: '#10b981' }}>✅ Synced</span>
                    ) : (
                      <span style={{ color: '#f59e0b' }}>⚠️ Pending</span>
                    )}
                  </td>
                  <td style={{ padding: '0.75rem', fontSize: '0.85rem', color: '#666' }}>
                    {new Date(cred.created_at).toLocaleDateString()}
                  </td>
                  <td style={{ padding: '0.75rem' }}>
                    <button
                      style={{
                        padding: '4px 8px',
                        backgroundColor: '#f59e0b',
                        color: 'white',
                        border: 'none',
                        borderRadius: '4px',
                        cursor: 'pointer',
                        fontSize: '0.75rem'
                      }}
                      onClick={() => handleRotateCredential(cred.id)}
                    >
                      Rotate
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );

  const MigrationsTab = () => (
    <div>
      <div style={{ marginBottom: '1.5rem' }}>
        <h3>📦 Secret Migrations</h3>
        <p style={{ color: '#666', marginBottom: '1rem' }}>
          Canonical migration of secrets from GSM/AWS/Azure to Vault
        </p>
      </div>

      {migrations.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '2rem' }}>
          <p>No migrations found</p>
        </div>
      ) : (
        <div style={{ display: 'grid', gap: '1rem' }}>
          {migrations.map((migration) => (
            <div key={migration.migration_id} className="card" style={{ padding: '1rem' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start', marginBottom: '1rem' }}>
                <div>
                  <h4 style={{ margin: 0, marginBottom: '0.5rem' }}>
                    {migration.source_provider.toUpperCase()} → VAULT
                  </h4>
                  <p style={{ margin: 0, fontSize: '0.85rem', color: '#666' }}>
                    ID: {migration.migration_id}
                  </p>
                </div>
                <span
                  style={{
                    display: 'inline-block',
                    padding: '0.25rem 0.75rem',
                    backgroundColor: migration.status === 'completed' ? '#d1fae5' : '#fef3c7',
                    color: migration.status === 'completed' ? '#065f46' : '#92400e',
                    borderRadius: '4px',
                    fontSize: '0.85rem',
                    fontWeight: 'bold'
                  }}
                >
                  {migration.status.toUpperCase()}
                </span>
              </div>

              <div style={{ backgroundColor: '#f3f4f6', padding: '0.75rem', borderRadius: '4px', marginBottom: '1rem' }}>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '0.5rem', fontSize: '0.85rem' }}>
                  <div>
                    <div style={{ color: '#666' }}>Discovered</div>
                    <div style={{ fontWeight: 'bold' }}>{migration.secrets_discovered}</div>
                  </div>
                  <div>
                    <div style={{ color: '#666' }}>Migrated</div>
                    <div style={{ fontWeight: 'bold', color: '#10b981' }}>{migration.secrets_migrated}</div>
                  </div>
                  <div>
                    <div style={{ color: '#666' }}>Failed</div>
                    <div style={{ fontWeight: 'bold', color: '#ef4444' }}>{migration.secrets_failed}</div>
                  </div>
                  <div>
                    <div style={{ color: '#666' }}>Progress</div>
                    <div style={{ fontWeight: 'bold' }}>{migration.progress_percent.toFixed(0)}%</div>
                  </div>
                </div>
              </div>

              <div style={{ width: '100%', backgroundColor: '#e5e7eb', borderRadius: '4px', height: '8px', overflow: 'hidden' }}>
                <div
                  style={{
                    height: '100%',
                    backgroundColor: migration.status === 'completed' ? '#10b981' : '#f59e0b',
                    width: `${migration.progress_percent}%`,
                    transition: 'width 0.3s ease'
                  }}
                />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  const AuditTab = () => (
    <div>
      <div style={{ marginBottom: '1.5rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h3 style={{ margin: 0, marginBottom: '0.5rem' }}>📋 Immutable Audit Trail</h3>
          <p style={{ margin: 0, color: '#666', fontSize: '0.9rem' }}>
            Append-only hash-chain verified logs of all operations
          </p>
        </div>
        <button
          style={{
            padding: '8px 16px',
            backgroundColor: '#10b981',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer'
          }}
          onClick={handleVerifyIntegrity}
        >
          🔐 Verify Integrity
        </button>
      </div>

      {auditTrail.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '2rem' }}>
          <p>No audit entries found</p>
        </div>
      ) : (
        <div style={{ backgroundColor: 'white', borderRadius: '4px', overflow: 'hidden', border: '1px solid #ddd' }}>
          <div style={{ maxHeight: '500px', overflowY: 'auto' }}>
            {auditTrail.slice().reverse().map((entry) => (
              <div
                key={entry.id}
                style={{
                  padding: '1rem',
                  borderBottom: '1px solid #ddd',
                  '&:last-child': { borderBottom: 'none' }
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start', marginBottom: '0.5rem' }}>
                  <div>
                    <div style={{ fontSize: '0.85rem', color: '#666' }}>
                      {new Date(entry.timestamp).toLocaleString()}
                    </div>
                    <div style={{ fontWeight: 'bold', marginTop: '0.25rem' }}>
                      {entry.event_type.replace(/_/g, ' ')}
                    </div>
                  </div>
                  <span
                    style={{
                      display: 'inline-block',
                      padding: '0.25rem 0.75rem',
                      backgroundColor: entry.status === 'success' ? '#d1fae5' : '#fee2e2',
                      color: entry.status === 'success' ? '#065f46' : '#991b1b',
                      borderRadius: '4px',
                      fontSize: '0.75rem',
                      fontWeight: 'bold'
                    }}
                  >
                    {entry.status === 'success' ? '✅' : '❌'} {entry.status.toUpperCase()}
                  </span>
                </div>
                <div style={{ fontSize: '0.85rem', color: '#666' }}>
                  {entry.resource_type}: <span style={{ fontFamily: 'monospace' }}>{entry.resource_id}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );

  if (loading) {
    return (
      <div style={{ textAlign: 'center', padding: '2rem' }}>
        <div>Loading secrets management...</div>
      </div>
    );
  }

  return (
    <div style={{ padding: '2rem' }}>
      <h2 style={{ marginBottom: '1rem' }}>🔐 Canonical Secrets Management</h2>
      <p style={{ color: '#666', marginBottom: '2rem' }}>
        Vault-primary architecture with multi-provider synchronization and immutable audit trails
      </p>

      {error && (
        <div style={{
          backgroundColor: '#fee2e2',
          color: '#991b1b',
          padding: '1rem',
          borderRadius: '4px',
          marginBottom: '1rem'
        }}>
          {error}
        </div>
      )}

      <ProviderHierarchyDisplay />
      <ProviderHealthCards />

      <div style={{ marginBottom: '1.5rem', borderBottom: '1px solid #ddd' }}>
        <div style={{ display: 'flex', gap: '1rem' }}>
          {['overview', 'credentials', 'migrations', 'audit'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              style={{
                padding: '0.75rem 1rem',
                backgroundColor: activeTab === tab ? '#3b82f6' : 'transparent',
                color: activeTab === tab ? 'white' : '#666',
                border: 'none',
                borderBottom: activeTab === tab ? '3px solid #3b82f6' : 'none',
                cursor: 'pointer',
                fontWeight: activeTab === tab ? 'bold' : 'normal'
              }}
            >
              {tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {activeTab === 'overview' && <div>Check provider health cards above</div>}
      {activeTab === 'credentials' && <CredentialsTab />}
      {activeTab === 'migrations' && <MigrationsTab />}
      {activeTab === 'audit' && <AuditTab />}
    </div>
  );
};

export default SecretsManagementDashboard;

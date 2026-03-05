import React from 'react';
import { COLORS, COLORS_DARK } from '../theme';
import { Panel, Pill, Button } from '../components/UI';
import { useTheme } from '../App';

export const LandingPage: React.FC = () => {
  const { theme } = useTheme();
  const colors = theme === 'light' ? COLORS : COLORS_DARK;

  const FeatureCard = ({ icon, title, desc }: { icon: string; title: string; desc: string }) => (
    <Panel
      style={{
        padding: 24,
        display: 'flex',
        flexDirection: 'column',
        gap: 12,
        transition: 'transform 0.2s ease',
        cursor: 'pointer',
      }}
    >
      <div style={{ fontSize: 32 }}>{icon}</div>
      <div style={{ fontWeight: 700, fontSize: 18 }}>{title}</div>
      <div style={{ color: colors.muted, fontSize: 14, lineHeight: 1.5 }}>{desc}</div>
    </Panel>
  );

  return (
    <div
      style={{
        flex: 1,
        overflowY: 'auto',
        background: colors.bg,
        padding: '60px 20px',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
      }}
    >
      {/* Hero Section */}
      <div style={{ maxWidth: 800, textAlign: 'center', marginBottom: 60 }}>
        <Pill color="blue" sm>PREVIEW RELEASE v2.4</Pill>
        <h1 style={{ fontSize: 48, fontWeight: 900, marginBottom: 20, letterSpacing: '-0.02em' }}>
          ElevatedIQ Runner Portal
        </h1>
        <p style={{ fontSize: 20, color: colors.muted, lineHeight: 1.6, marginBottom: 32 }}>
          Master your GitHub Actions infrastructure with a unified control plane. 
          Provision, monitor, and scale self-hosted runners with enterprise-grade security.
        </p>
        <div style={{ display: 'flex', gap: 16, justifyContent: 'center' }}>
          <Button style={{ padding: '12px 24px', fontSize: 16, fontWeight: 600 }}>
            Get Started
          </Button>
          <Button
            style={{
              padding: '12px 24px',
              fontSize: 16,
              fontWeight: 600,
              background: 'transparent',
              color: colors.text,
              border: `1px solid ${colors.border}`,
            }}
          >
            Read Documentation
          </Button>
        </div>
      </div>

      {/* Features Grid */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
          gap: 24,
          maxWidth: 1200,
          width: '100%',
        }}
      >
        <FeatureCard
          icon="🚀"
          title="Instant Provisioning"
          desc="Deploy new runner pools across AWS, Azure, and GCP in seconds with pre-cached images."
        />
        <FeatureCard
          icon="📊"
          title="Live Observability"
          desc="Real-time metrics, logs, and trace data for every job execution and runner lifecycle event."
        />
        <FeatureCard
          icon="🛡️"
          title="Zero-Trust Security"
          desc="Vault-integrated secret management and workload identity for secure cloud resource access."
        />
        <FeatureCard
          icon="📉"
          title="Cost Optimization"
          desc="Auto-scaling based on queue depth and spot instance management to reduce infrastructure spend."
        />
        <FeatureCard
          icon="🏗️"
          title="Modular Infrastructure"
          desc="Terraform-first architecture allows you to customize every aspect of your runner fleet."
        />
        <FeatureCard
          icon="🤖"
          title="AI-Powered Insights"
          desc="Automatically detect bottlenecks and failure patterns using the built-in AI Oracle."
        />
      </div>

      {/* Footer */}
      <div style={{ marginTop: 80, borderTop: `1px solid ${colors.border}`, paddingTop: 40, width: '100%', maxWidth: 1200, textAlign: 'center' }}>
        <div style={{ color: colors.muted, fontSize: 14 }}>
          © 2026 ElevatedIQ Platform Team. All rights reserved.
        </div>
      </div>
    </div>
  );
};

import React, { useState } from 'react';
import { COLORS } from '../theme';
import { Panel, Button } from '../components/UI';

/**
 * Deploy Mode Wizard Interface
 */
interface DeployStep {
  number: number;
  title: string;
  description: string;
  command?: string;
  details: string[];
}

interface DeployMode {
  id: 'managed' | 'byoc' | 'onprem';
  name: string;
  icon: string;
  color: string;
  description: string;
  steps: DeployStep[];
  benefits: string[];
  estimatedTime: string;
}

/**
 * Deploy Modes Configuration
 */
const DEPLOY_MODES: DeployMode[] = [
  {
    id: 'managed',
    name: 'Managed',
    icon: '☁️',
    color: COLORS.cyan,
    description: 'ElevatedIQ Cloud: We manage infrastructure, you manage jobs',
    benefits: [
      'Zero infrastructure setup',
      'Auto-scaling runners',
      'Built-in monitoring & alerts',
      'Managed SBOM & compliance',
      'Global edge endpoints',
    ],
    estimatedTime: '5 minutes',
    steps: [
      {
        number: 1,
        title: 'Create Organization Account',
        description: 'Sign up and create your ElevatedIQ organization',
        command: 'curl -X POST https://api.elevatediq.com/orgs',
        details: [
          'Visit https://portal.elevatediq.com/signup',
          'Enter organization name and billing email',
          'Verify email and set up 2FA',
        ],
      },
      {
        number: 2,
        title: 'Generate API Token',
        description: 'Create token for GitHub Actions integration',
        command: 'elevatediq token create --name github-runner-token',
        details: [
          'Go to Settings → API Tokens',
          'Click "Generate New Token"',
          'Copy token (shown only once)',
        ],
      },
      {
        number: 3,
        title: 'Add GitHub Secret',
        description: 'Store API token in GitHub for authentication',
        command: 'gh secret set ELEVATEDIQ_RUNNER_TOKEN --body "<token>"',
        details: [
          'In GitHub repo: Settings → Secrets → New Repository Secret',
          'Name: ELEVATEDIQ_RUNNER_TOKEN',
          'Value: Paste your API token',
        ],
      },
    ],
  },
  {
    id: 'byoc',
    name: 'BYOC (Bring Your Own Cloud)',
    icon: '🏢',
    color: COLORS.green,
    description: 'Your AWS/GCP/Azure account: ElevatedIQ optimizes, you control',
    benefits: [
      'Full infrastructure control',
      'Custom VPC/network policies',
      'Compliance with your policies',
      'Cost visibility & attribution',
      'eBPF security enforcement',
    ],
    estimatedTime: '30 minutes',
    steps: [
      {
        number: 1,
        title: 'Prepare Cloud Environment',
        description: 'Set up VPC, subnets, and security groups',
        command: 'terraform apply -var="org_id=myorg"',
        details: [
          'Create VPC with CIDR 10.0.0.0/16',
          'Create private subnet 10.0.1.0/24 for runners',
          'Configure NAT gateway for outbound traffic',
          'Create security group allowing 443 outbound to npm/docker registries',
        ],
      },
      {
        number: 2,
        title: 'Install BYOC Sidecar',
        description: 'Deploy ElevatedIQ control plane in your account',
        command: 'aws cloudformation create-stack --template-body file://byoc-stack.yaml --parameters ParameterKey=OrgId,ParameterValue=myorg',
        details: [
          'Download CloudFormation template from portal',
          'Deploy ElevatedIQ Control Plane (ECS cluster)',
          'Configure service IAM role with EC2/ECS permissions',
          'Set log group retention to 30 days',
        ],
      },
      {
        number: 3,
        title: 'Configure Network Allowlist',
        description: 'Lock down external endpoints',
        command: 'elevatediq network-policy add npm --endpoint registry.npmjs.org --port 443',
        details: [
          'Add registry.npmjs.org (NPM packages)',
          'Add ghcr.io (Docker images)',
          'Add github.com (Git clone)',
          'Validate connectivity from private subnet',
        ],
      },
      {
        number: 4,
        title: 'Register Runners',
        description: 'Connect GitHub to your ElevatedIQ deployment',
        command: 'gh secret set ELEVATEDIQ_SIDECAR_URL --body "https://sidecar.myorg.elevatediq.internal"',
        details: [
          'Get sidecar endpoint from CloudFormation outputs',
          'Add to GitHub Organization Secrets',
          'Register repository runners through web UI',
          'Validate runner health in dashboard',
        ],
      },
      {
        number: 5,
        title: 'Enable eBPF Monitoring',
        description: 'Deploy kernel-level security enforcement',
        command: 'elevatediq ebpf enable --mode strict',
        details: [
          'Select eBPF enforcement level (permissive, strict, audit-only)',
          'Configure allowlist for syscalls and network',
          'Enable SBOM generation on every job',
          'Set up alerts for policy violations',
        ],
      },
    ],
  },
  {
    id: 'onprem',
    name: 'On-Premise',
    icon: '🖥️',
    color: COLORS.yellow,
    description: 'Your physical infrastructure: Maximum control & compliance',
    benefits: [
      'Air-gapped deployment',
      'Zero cloud dependencies',
      'Custom hardware requirements',
      'Full data residency control',
      'On-site support available',
    ],
    estimatedTime: '2-4 hours',
    steps: [
      {
        number: 1,
        title: 'Provision Physical Servers',
        description: 'Set up bare-metal runner nodes',
        command: 'packer build runner-image.pkr.hcl',
        details: [
          'Min spec: 16 vCPU, 32GB RAM, 500GB SSD per runner node',
          'Install Ubuntu 22.04 LTS or RHEL 8.8+',
          'Configure static networking (no DHCP)',
          'Network mode: "host" for performance',
        ],
      },
      {
        number: 2,
        title: 'Install ElevatedIQ Runtime',
        description: 'Deploy control plane and agents',
        command: 'curl https://repo.elevatediq.com/install-onprem.sh | sudo bash',
        details: [
          'Install container runtime (containerd recommended)',
          'Deploy control plane (Kubernetes or standalone)',
          'Configure persistent storage for SBOM/metrics',
          'Set up logging aggregation (syslog/Filebeat)',
        ],
      },
      {
        number: 3,
        title: 'Configure Air-Gapped Registry',
        description: 'Mirror container dependencies',
        command: 'elevatediq registry mirror --source ghcr.io --local-registry registry.internal:5000',
        details: [
          'Set up private Docker registry (2TB+ storage)',
          'Mirror base images, tools, SDKs offline',
          'Configure runners to use internal registry only',
          'Schedule weekly registry sync from approved sources',
        ],
      },
      {
        number: 4,
        title: 'Deploy Security Enforcement',
        description: 'Kernel-level policy enforcement',
        command: 'elevatediq security deploy --mode air-gapped',
        details: [
          'Deploy Falco + Tetragon for eBPF monitoring',
          'Load security policies from offline bundle',
          'Configure SELinux/AppArmor for process isolation',
          'Enable TPM-based attestation (if available)',
        ],
      },
    ],
  },
];

/**
 * Deploy Mode Wizard Page
 */
export const DeployMode: React.FC = () => {
  const [selectedMode, setSelectedMode] = useState<'managed' | 'byoc' | 'onprem' | null>(null);
  const [expandedStep, setExpandedStep] = useState<number | null>(null);

  const mode = DEPLOY_MODES.find((m) => m.id === selectedMode);

  return (
    <div style={{ flex: 1, padding: 20, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 800, color: COLORS.text, marginBottom: 4 }}>
          {selectedMode ? `${mode?.name} Setup Wizard` : 'Choose Deploy Mode'}
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          {selectedMode
            ? `Estimated time: ${mode?.estimatedTime}`
            : 'Select how you want to run ElevatedIQ runners'}
        </div>
      </div>

      {!selectedMode ? (
        <>
          {/* Mode Selection Cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
            {DEPLOY_MODES.map((m) => (
              <Panel
                key={m.id}
                style={{
                  padding: '16px 14px',
                  cursor: 'pointer',
                  transition: 'all 0.2s ease',
                  border: `2px solid transparent`,
                }}
                glowColor={m.color}
              >
                <div
                  onClick={() => setSelectedMode(m.id)}
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 12,
                  }}
                >
                  <div>
                    <div style={{ fontSize: 32, marginBottom: 6 }}>{m.icon}</div>
                    <div style={{ fontSize: 14, fontWeight: 800, color: COLORS.text }}>
                      {m.name}
                    </div>
                  </div>
                  <div style={{ fontSize: 11, color: COLORS.textDim }}>
                    {m.description}
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    {m.benefits.slice(0, 2).map((b, i) => (
                      <div key={i} style={{ fontSize: 10, color: COLORS.muted }}>
                        ✓ {b}
                      </div>
                    ))}
                    <div style={{ fontSize: 10, color: COLORS.muted }}>
                      ✓ +{m.benefits.length - 2} more
                    </div>
                  </div>
                  <button
                    style={{
                      marginTop: 8,
                      background: m.color,
                      color: '#000',
                      border: 'none',
                      borderRadius: 4,
                      padding: '6px 12px',
                      fontSize: 11,
                      fontWeight: 700,
                      cursor: 'pointer',
                      textTransform: 'uppercase',
                      letterSpacing: '0.05em',
                    }}
                  >
                    Setup {m.name}
                  </button>
                </div>
              </Panel>
            ))}
          </div>

          {/* Quick Comparison */}
          <Panel>
            <div style={{ padding: '12px 14px' }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: COLORS.text, marginBottom: 8 }}>
                Quick Comparison
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8, fontSize: 10 }}>
                {[
                  { aspect: 'Setup Time', managed: '5 min', byoc: '30 min', onprem: '2-4 hr' },
                  { aspect: 'Monthly Cost', managed: '$499-2999', byoc: '$800-1500', onprem: '$5000+' },
                  { aspect: 'Control Level', managed: 'Low', byoc: 'Medium', onprem: 'Maximum' },
                  { aspect: 'Maintenance', managed: 'Zero', byoc: 'Shared', onprem: 'Full' },
                ].map((row) => (
                  <div key={row.aspect}>
                    <div style={{ color: COLORS.muted, marginBottom: 4 }}>
                      {row.aspect}
                    </div>
                    <div
                      style={{
                        display: 'flex',
                        flexDirection: 'column',
                        gap: 2,
                        color: COLORS.textDim,
                      }}
                    >
                      <span style={{ fontSize: 9 }}>M: {row.managed}</span>
                      <span style={{ fontSize: 9 }}>B: {row.byoc}</span>
                      <span style={{ fontSize: 9 }}>O: {row.onprem}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </Panel>
        </>
      ) : (
        <>
          {/* Wizard Steps */}
          <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
            <button
              onClick={() => setSelectedMode(null)}
              style={{
                background: 'transparent',
                border: `1px solid ${COLORS.border}`,
                color: COLORS.text,
                borderRadius: 4,
                padding: '6px 12px',
                fontSize: 11,
                cursor: 'pointer',
              }}
            >
              ← Back
            </button>
            <div style={{ display: 'flex', gap: 6, flex: 1 }}>
              {mode?.steps.map((step) => (
                <div
                  key={step.number}
                  style={{
                    flex: 1,
                    height: 4,
                    borderRadius: 2,
                    background: step.number <= (expandedStep ?? 0) ? mode.color : COLORS.border,
                  }}
                />
              ))}
            </div>
          </div>

          {/* Steps List */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {mode?.steps.map((step) => (
              <Panel
                key={step.number}
                style={{
                  padding: 0,
                  cursor: 'pointer',
                  border: expandedStep === step.number ? `2px solid ${mode.color}` : '1px solid' + COLORS.border,
                  transition: 'all 0.2s ease',
                }}
              >
                <div
                  onClick={() => setExpandedStep(expandedStep === step.number ? null : step.number)}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 12,
                    padding: '12px 14px',
                  }}
                >
                  <div
                    style={{
                      width: 32,
                      height: 32,
                      borderRadius: '50%',
                      background: mode.color + '22',
                      border: `2px solid ${mode.color}`,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: 14,
                      fontWeight: 800,
                      color: mode.color,
                      flexShrink: 0,
                    }}
                  >
                    {step.number}
                  </div>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 12, fontWeight: 700, color: COLORS.text }}>
                      {step.title}
                    </div>
                    <div style={{ fontSize: 10, color: COLORS.muted, marginTop: 2 }}>
                      {step.description}
                    </div>
                  </div>
                  <span style={{ fontSize: 14, color: COLORS.textDim }}>
                    {expandedStep === step.number ? '▲' : '▼'}
                  </span>
                </div>

                {/* Expanded Details */}
                {expandedStep === step.number && (
                  <div style={{ borderTop: `1px solid ${COLORS.border}`, padding: '12px 14px' }}>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                      {/* Command */}
                      {step.command && (
                        <div>
                          <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 4, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                            Command
                          </div>
                          <div
                            style={{
                              background: '#000',
                              border: `1px solid ${COLORS.border}`,
                              borderRadius: 4,
                              padding: '8px 10px',
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: COLORS.green,
                              wordBreak: 'break-all',
                              position: 'relative',
                            }}
                          >
                            {step.command}
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                navigator.clipboard.writeText(step.command!);
                              }}
                              style={{
                                position: 'absolute',
                                top: 6,
                                right: 6,
                                background: COLORS.accent,
                                color: '#000',
                                border: 'none',
                                borderRadius: 2,
                                padding: '2px 6px',
                                fontSize: 9,
                                fontWeight: 700,
                                cursor: 'pointer',
                              }}
                            >
                              COPY
                            </button>
                          </div>
                        </div>
                      )}

                      {/* Details */}
                      <div>
                        <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 4, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                          Details
                        </div>
                        <ul style={{ margin: 0, paddingLeft: 16 }}>
                          {step.details.map((detail, i) => (
                            <li
                              key={i}
                              style={{
                                fontSize: 10,
                                color: COLORS.textDim,
                                marginBottom: 4,
                              }}
                            >
                              {detail}
                            </li>
                          ))}
                        </ul>
                      </div>
                    </div>
                  </div>
                )}
              </Panel>
            ))}
          </div>

          {/* Submit Button */}
          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <Button
              onClick={() => setSelectedMode(null)}
              style={{
                background: COLORS.border,
                color: COLORS.text,
                flex: 1,
              }}
            >
              Cancel
            </Button>
            <Button
              onClick={() => {
                console.log(`Deploy mode ${selectedMode} selected`);
              }}
              style={{
                background: mode?.color,
                color: '#000',
                flex: 1,
              }}
            >
              Continue with {mode?.name}
            </Button>
          </div>
        </>
      )}
    </div>
  );
};

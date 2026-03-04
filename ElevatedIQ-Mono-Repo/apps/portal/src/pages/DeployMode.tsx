import React, { useState } from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader, Button, Pill } from '../components/UI';

type DeployMode = 'managed' | 'byoc' | 'onprem' | null;
type StepIndex = 0 | 1 | 2 | 3;

/**
 * Deploy Mode Wizard - Setup flows for all deployment modes
 * Managed (3-step), BYOC (5-step), On-Premise (4-step)
 */
export const DeployMode: React.FC = () => {
  const [selectedMode, setSelectedMode] = useState<DeployMode>(null);
  const [currentStep, setCurrentStep] = useState<StepIndex>(0);
  const [copied, setCopied] = useState<string | null>(null);

  const resetWizard = () => {
    setSelectedMode(null);
    setCurrentStep(0);
  };

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopied(id);
    setTimeout(() => setCopied(null), 2000);
  };

  // ===== MODE DEFINITIONS =====

  const modes = {
    managed: {
      icon: '☁️',
      title: 'Managed',
      subtitle: 'SaaS runners in RunnerCloud fleet',
      description: 'Pre-warmed, auto-scaling runners hosted by RunnerCloud. Fastest setup, zero infrastructure.',
      color: COLORS.accent,
      steps: [
        {
          title: 'GitHub App Authorization',
          description: 'Authorize RunnerCloud to manage runners in your organization',
          action: 'Click "Authorize" button to sign in with GitHub',
          codeBlocks: [],
          validation: 'OAuth flow initiated',
        },
        {
          title: 'Configure Runner Pool',
          description: 'Set runner specs (CPU, memory, labels)',
          action: 'Choose instance type and auto-scaling settings',
          codeBlocks: [
            {
              label: 'Pool Configuration',
              code: `{
  "pool": "production",
  "minRunners": 2,
  "maxRunners": 10,
  "instanceType": "medium",
  "labels": ["ubuntu-latest", "x64"],
  "billingModel": "per-second"
}`,
            },
          ],
          validation: 'Pool created successfully',
        },
        {
          title: 'Deploy & Verify',
          description: 'Deploy runners and test with GitHub Actions workflow',
          action: 'Runners deployed automatically in < 30s',
          codeBlocks: [
            {
              label: 'Test Workflow',
              code: `name: Test RunnerCloud Managed
on: [push]
jobs:
  build:
    runs-on: runnercloud-ubuntu-latest
    steps:
      - run: echo "Running on RunnerCloud managed runner!"`,
            },
          ],
          validation: 'First job executed successfully',
        },
      ],
    },
    byoc: {
      icon: '🔒',
      title: 'BYOC',
      subtitle: 'Bring Your Own Cloud (AWS/GCP/Azure)',
      description: 'RunnerCloud control plane in your VPC. Full compliance: SOC 2, HIPAA, FedRAMP ready.',
      color: COLORS.purple,
      steps: [
        {
          title: 'Create GitHub App',
          description: 'Register OAuth app in your GitHub organization',
          action: 'Create app at: GitHub Org Settings → Developer Settings → New GitHub App',
          codeBlocks: [],
          validation: 'GitHub App registered',
        },
        {
          title: 'Add AWS Credentials',
          description: 'Configure AWS account access for RunnerCloud',
          action: 'Store AWS credentials (or use OIDC federation)',
          codeBlocks: [
            {
              label: 'IAM Policy (minimal)',
              code: `{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DescribeInstances",
      "karpenter:*"
    ],
    "Resource": "*"
  }]
}`,
            },
          ],
          validation: 'AWS credentials verified',
        },
        {
          title: 'Deploy via Terraform',
          description: 'Generate and apply Terraform configuration',
          action: 'Generate Terraform module for your environment',
          codeBlocks: [
            {
              label: 'Terraform Apply',
              code: `terraform init
terraform plan
terraform apply

# Deploys:
# - ARC in your EKS cluster
# - Karpenter for auto-scaling
# - RunnerCloud control plane integration`,
            },
          ],
          validation: 'Terraform apply completed',
        },
        {
          title: 'Configure Networking',
          description: 'Set up network policies and security groups',
          action: 'Configure inbound rules and OIDC federation',
          codeBlocks: [
            {
              label: 'Network Policy',
              code: `# Only allow traffic from:
# - GitHub Actions webhooks (github.com)
# - Cloud provider APIs (EC2, GKE, AKS)
# - Internal Kubernetes services

kubectl apply -f network-policy.yaml`,
            },
          ],
          validation: 'Network policies applied',
        },
        {
          title: 'Deploy & Verify',
          description: 'Test runners in your VPC',
          action: 'Deploy test runners and validate connectivity',
          codeBlocks: [
            {
              label: 'Test Workflow',
              code: `name: Test BYOC Runners
on: [push]
jobs:
  build:
    runs-on: runnercloud-byoc-ubuntu
    steps:
      - run: echo "Running in my VPC!"`,
            },
          ],
          validation: 'BYOC runners executing jobs',
        },
      ],
    },
    onprem: {
      icon: '🏢',
      title: 'On-Premise',
      subtitle: 'Bare metal or VM self-hosted',
      description: 'Single binary deployment. No Kubernetes required. Scale via systemd or snapshots.',
      color: COLORS.orange,
      steps: [
        {
          title: 'Download Binary',
          description: 'Get RunnerCloud On-Prem binary',
          action: 'Download for your OS (Linux/Windows)',
          codeBlocks: [
            {
              label: 'Download',
              code: `# Linux
curl -LO https://releases.runnercloud.io/runnercloud-onprem-linux-x64
chmod +x runnercloud-onprem-linux-x64

# Windows
Invoke-WebRequest https://releases.runnercloud.io/runnercloud-onprem-windows-x64.exe`,
            },
          ],
          validation: 'Binary downloaded and verified',
        },
        {
          title: 'Create Configuration',
          description: 'Configure runner token and pool settings',
          action: 'Create YAML config file',
          codeBlocks: [
            {
              label: '/etc/runnercloud/config.yaml',
              code: `token: ghp_xxxxx_runner_token
runnerGroup: default
poolSize: 5
runnerLabels:
  - ubuntu-latest
  - x64
scalingPolicy:
  minRunners: 2
  maxRunners: 10
  scaleUpThreshold: 3
  scaleDownThreshold: 1`,
            },
          ],
          validation: 'Configuration validated',
        },
        {
          title: 'Install Service',
          description: 'Register as systemd service',
          action: 'Enable auto-start on boot',
          codeBlocks: [
            {
              label: 'Install systemd service',
              code: `sudo tee /etc/systemd/system/runnercloud.service > /dev/null <<EOF
[Unit]
Description=RunnerCloud On-Prem Runner
After=network.target

[Service]
Type=simple
User=runnercloud
ExecStart=/usr/local/bin/runnercloud-onprem-linux-x64 \\
  --config=/etc/runnercloud/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable runnercloud`,
            },
          ],
          validation: 'Service installed',
        },
        {
          title: 'Deploy & Verify',
          description: 'Start service and test runners',
          action: 'Boot runners and execute first job',
          codeBlocks: [
            {
              label: 'Start service',
              code: `sudo systemctl start runnercloud
sudo systemctl status runnercloud

# Check logs
journalctl -u runnercloud -f`,
            },
          ],
          validation: 'First on-prem job executed',
        },
      ],
    },
  };

  // ===== MODE CARDS =====

  const ModeCard: React.FC<{
    mode: DeployMode;
    data: typeof modes[keyof typeof modes];
  }> = ({ mode, data }) => (
    <Panel
      glowColor={selectedMode === mode ? data.color : undefined}
      style={{
        padding: 16,
        cursor: 'pointer',
        border: `1px solid ${selectedMode === mode ? data.color + '66' : COLORS.border}`,
        transition: 'all 0.2s',
        opacity: selectedMode && selectedMode !== mode ? 0.5 : 1,
      }}
    >
      <div
        onClick={() => {
          setSelectedMode(mode as DeployMode);
          setCurrentStep(0);
        }}
      >
        <div style={{ fontSize: 24, marginBottom: 8 }}>{data.icon}</div>
        <div style={{ fontSize: 13, fontWeight: 700, color: data.color, marginBottom: 4 }}>
          {data.title}
        </div>
        <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 8 }}>
          {data.subtitle}
        </div>
        <div style={{ fontSize: 10, color: COLORS.textDim, lineHeight: '1.4' }}>
          {data.description}
        </div>
        <div style={{ marginTop: 12 }}>
          <Pill color={mode === 'managed' ? 'blue' : mode === 'byoc' ? 'purple' : 'orange'}>
            {data.steps.length} steps
          </Pill>
        </div>
      </div>
    </Panel>
  );

  // ===== WIZARD STEPS =====

  const currentModeData = selectedMode ? modes[selectedMode] : null;
  const currentStepData = currentModeData ? currentModeData.steps[currentStep] : null;

  return (
    <div
      style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        gap: 16,
        padding: 16,
        overflow: 'auto',
      }}
    >
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 700, color: COLORS.text, marginBottom: 4 }}>
          Deploy Mode Wizard
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          Choose your deployment architecture and follow the setup flow
        </div>
      </div>

      {!selectedMode ? (
        // Mode Selection View
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
            gap: 12,
          }}
        >
          {Object.entries(modes).map(([key, data]) => (
            <ModeCard key={key} mode={key as DeployMode} data={data} />
          ))}
        </div>
      ) : currentModeData && currentStepData ? (
        // Wizard Flow View
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {/* Progress */}
          <Panel style={{ padding: 12 }}>
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                marginBottom: 8,
              }}
            >
              <div style={{ fontSize: 11, fontWeight: 700, color: currentModeData.color }}>
                {currentModeData.title.toUpperCase()} MODE
              </div>
              <div style={{ fontSize: 10, color: COLORS.muted }}>
                Step {currentStep + 1} of {currentModeData.steps.length}
              </div>
            </div>
            <div
              style={{
                width: '100%',
                height: 4,
                background: COLORS.border,
                borderRadius: 2,
                overflow: 'hidden',
              }}
            >
              <div
                style={{
                  width: `${((currentStep + 1) / currentModeData.steps.length) * 100}%`,
                  height: '100%',
                  background: currentModeData.color,
                  transition: 'width 0.3s',
                }}
              />
            </div>
          </Panel>

          {/* Current Step */}
          <Panel style={{ padding: 16 }}>
            <div style={{ marginBottom: 12 }}>
              <div style={{ fontSize: 14, fontWeight: 700, color: COLORS.text, marginBottom: 4 }}>
                {currentStepData.title}
              </div>
              <div style={{ fontSize: 11, color: COLORS.muted, marginBottom: 8 }}>
                {currentStepData.description}
              </div>
            </div>

            {/* Action */}
            <Panel
              style={{
                padding: 12,
                background: currentModeData.color + '08',
                border: `1px solid ${currentModeData.color}22`,
                marginBottom: 12,
              }}
            >
              <div style={{ fontSize: 10, color: COLORS.text }}>{currentStepData.action}</div>
            </Panel>

            {/* Code Blocks */}
            {currentStepData.codeBlocks.length > 0 && (
              <div style={{ marginBottom: 12 }}>
                {currentStepData.codeBlocks.map((block, idx) => (
                  <div key={idx}>
                    <div
                      style={{
                        fontSize: 9,
                        fontWeight: 700,
                        color: COLORS.muted,
                        textTransform: 'uppercase',
                        marginBottom: 4,
                      }}
                    >
                      {block.label}
                    </div>
                    <Panel
                      style={{
                        padding: 10,
                        background: COLORS.surfaceHigh,
                        border: `1px solid ${COLORS.borderBright}`,
                        marginBottom: 12,
                        position: 'relative',
                      }}
                    >
                      <pre
                        style={{
                          margin: 0,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: COLORS.cyan,
                          lineHeight: '1.4',
                          whiteSpace: 'pre-wrap',
                          wordBreak: 'break-word',
                        }}
                      >
                        {block.code}
                      </pre>
                      <Button
                        sm
                        color={COLORS.cyan}
                        onClick={() => copyToClipboard(block.code, block.label)}
                        style={{
                          position: 'absolute',
                          top: 8,
                          right: 8,
                          fontSize: 9,
                        }}
                      >
                        {copied === block.label ? '✓ Copied' : 'Copy'}
                      </Button>
                    </Panel>
                  </div>
                ))}
              </div>
            )}

            {/* Validation */}
            <Panel
              style={{
                padding: 10,
                background: COLORS.green + '08',
                border: `1px solid ${COLORS.green}22`,
              }}
            >
              <div style={{ fontSize: 10, color: COLORS.green }}>
                ✓ {currentStepData.validation}
              </div>
            </Panel>
          </Panel>

          {/* Navigation */}
          <div
            style={{
              display: 'flex',
              gap: 8,
              justifyContent: 'space-between',
            }}
          >
            <div style={{ display: 'flex', gap: 8 }}>
              <Button
                color={COLORS.muted}
                onClick={resetWizard}
              >
                ← Back to Modes
              </Button>
              {currentStep > 0 && (
                <Button
                  color={COLORS.muted}
                  onClick={() => setCurrentStep((currentStep - 1) as StepIndex)}
                >
                  Previous
                </Button>
              )}
            </div>

            <Button
              color={currentModeData.color}
              onClick={() => {
                if (currentStep < currentModeData.steps.length - 1) {
                  setCurrentStep((currentStep + 1) as StepIndex);
                } else {
                  alert('Deployment wizard completed! Check dashboard for active runners.');
                  resetWizard();
                }
              }}
            >
              {currentStep === currentModeData.steps.length - 1 ? 'Complete' : 'Next →'}
            </Button>
          </div>
        </div>
      ) : null}
    </div>
  );
};

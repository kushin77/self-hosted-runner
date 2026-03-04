import React, { useState } from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader, Pill, GlowDot, Button } from '../components/UI';

/**
 * Agent Persona Definition
 */
export interface AgentPersona {
  id: string;
  icon: string;
  name: string;
  color: string;
  status: 'active' | 'idle' | 'warning' | 'error';
  runs: number;
  desc: string;
  tags: string[];
  config: Record<string, string | number | boolean>;
}

/**
 * Predefined Agent Personas
 */
export const AGENT_PERSONAS: AgentPersona[] = [
  {
    id: 'oracle',
    icon: '🔮',
    name: 'Failure Oracle',
    color: COLORS.purple,
    status: 'active',
    runs: 847,
    desc: 'Streams job logs on failure → root-cause analysis → opens fix PR at >90% confidence. Powered by Claude API or self-hosted Llama.',
    tags: ['log streaming', 'PR comments', 'auto-retry'],
    config: { model: 'claude-sonnet-4-20250514', confidence: 90, autoFix: true },
  },
  {
    id: 'perf',
    icon: '⚡',
    name: 'Perf Profiler',
    color: COLORS.yellow,
    status: 'active',
    runs: 312,
    desc: 'Attaches to every job, profiles step duration, flags regressions vs. 7-day baseline, suggests matrix collapse opportunities.',
    tags: ['step timing', 'baseline diff', 'matrix opt'],
    config: { threshold: '15%', notify: 'slack', baselineWindow: 7 },
  },
  {
    id: 'security',
    icon: '🛡',
    name: 'Security Auditor',
    color: COLORS.red,
    status: 'active',
    runs: 1204,
    desc: 'Scans every npm/pip/apt install in real-time via eBPF sidecar. Blocks unknown registries. Posts SBOM to PR.',
    tags: ['eBPF', 'SBOM', 'supply chain'],
    config: { blockUnknown: true, sbomFormat: 'SPDX', scanLevel: 'strict' },
  },
  {
    id: 'cache',
    icon: '💾',
    name: 'Cache Oracle',
    color: COLORS.cyan,
    status: 'active',
    runs: 2891,
    desc: 'Content-addressable cache with ML-driven invalidation prediction. Cross-repo sharing via your GitHub App. Post-job warm suggestions.',
    tags: ['predictive', 'cross-repo', 'NVMe'],
    config: { strategy: 'predictive', crossRepo: true, warmupEnabled: true },
  },
  {
    id: 'review',
    icon: '👁',
    name: 'Code Review Agent',
    color: COLORS.accent,
    status: 'idle',
    runs: 89,
    desc: 'On PR open: reviews diff for anti-patterns, security issues, and style violations. Posts inline comments. Respects your CODEOWNERS.',
    tags: ['PR review', 'inline comments', 'CODEOWNERS'],
    config: { model: 'claude-sonnet-4-20250514', scope: 'diff-only', respectCODEOWNERS: true },
  },
  {
    id: 'deploy',
    icon: '🚢',
    name: 'Deploy Guardian',
    color: COLORS.green,
    status: 'idle',
    runs: 204,
    desc: 'Validates deploy PRs against infra policy, checks blast radius, requires human approval for high-risk changes, auto-approves low-risk.',
    tags: ['policy check', 'blast radius', 'auto-approve'],
    config: { riskThreshold: 'medium', requireHuman: true, autoApprove: false },
  },
];

/**
 * Agent Roster - Left panel listing agents
 */
interface AgentRosterProps {
  agents: AgentPersona[];
  selected: string | null;
  onSelect: (id: string) => void;
}

const AgentRoster: React.FC<AgentRosterProps> = ({ agents, selected, onSelect }) => (
  <div
    style={{
      width: 260,
      borderRight: `1px solid ${COLORS.border}`,
      display: 'flex',
      flexDirection: 'column',
      overflow: 'hidden',
      background: COLORS.surface,
    }}
  >
    <div style={{ padding: '16px', borderBottom: `1px solid ${COLORS.border}` }}>
      <div style={{ fontSize: 15, fontWeight: 800, color: COLORS.text }}>Agent Studio</div>
      <div style={{ fontSize: 11, color: COLORS.muted, marginTop: 2 }}>
        Sidecar agents running in every pod
      </div>
    </div>
    <div style={{ flex: 1, overflowY: 'auto', padding: '8px 0' }}>
      {agents.map((agent) => (
        <div
          key={agent.id}
          onClick={() => onSelect(agent.id)}
          style={{
            padding: '10px 14px',
            cursor: 'pointer',
            background: selected === agent.id ? agent.color + '14' : 'transparent',
            borderLeft: selected === agent.id ? `2px solid ${agent.color}` : '2px solid transparent',
            borderBottom: `1px solid ${COLORS.border}`,
            transition: 'all 0.2s ease',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: 18 }}>{agent.icon}</span>
            <div style={{ flex: 1 }}>
              <div
                style={{
                  fontSize: 12,
                  fontWeight: 700,
                  color: selected === agent.id ? agent.color : COLORS.text,
                }}
              >
                {agent.name}
              </div>
              <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 1 }}>
                {agent.runs.toLocaleString()} runs
              </div>
            </div>
            <GlowDot
              color={
                agent.status === 'active'
                  ? COLORS.green
                  : agent.status === 'warning'
                  ? COLORS.yellow
                  : agent.status === 'error'
                  ? COLORS.red
                  : COLORS.muted
              }
              size={6}
            />
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 3, marginTop: 6 }}>
            {agent.tags.map((t) => (
              <span
                key={t}
                style={{
                  fontSize: 8,
                  background: agent.color + '18',
                  color: agent.color,
                  border: `1px solid ${agent.color}33`,
                  borderRadius: 2,
                  padding: '1px 4px',
                  fontWeight: 600,
                }}
              >
                {t}
              </span>
            ))}
          </div>
        </div>
      ))}
    </div>
    <div style={{ padding: 12, borderTop: `1px solid ${COLORS.border}` }}>
      <Button color={COLORS.green} style={{ width: '100%', textAlign: 'center' }}>
        + New Agent
      </Button>
    </div>
  </div>
);

/**
 * Agent Detail - Right panel with agent information
 */
interface AgentDetailProps {
  agent: AgentPersona;
  onEdit: () => void;
  onDisable: () => void;
}

const AgentDetail: React.FC<AgentDetailProps> = ({ agent, onEdit, onDisable }) => (
  <div style={{ flex: 1, overflowY: 'auto', padding: 20 }}>
    {/* Header */}
    <div
      style={{
        display: 'flex',
        alignItems: 'flex-start',
        justifyContent: 'space-between',
        marginBottom: 16,
      }}
    >
      <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
        <div
          style={{
            width: 48,
            height: 48,
            borderRadius: 12,
            background: agent.color + '22',
            border: `1px solid ${agent.color}44`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 24,
            boxShadow: `0 0 20px ${agent.color}22`,
          }}
        >
          {agent.icon}
        </div>
        <div>
          <div style={{ fontSize: 18, fontWeight: 800, color: agent.color }}>
            {agent.name}
          </div>
          <div style={{ display: 'flex', gap: 6, marginTop: 4 }}>
            <Pill
              color={
                agent.status === 'active'
                  ? 'green'
                  : agent.status === 'warning'
                  ? 'yellow'
                  : 'red'
              }
            >
              {agent.status}
            </Pill>
            <Pill color="blue" sm>
              {agent.runs.toLocaleString()} runs
            </Pill>
          </div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 8 }}>
        <Button color={agent.color} sm onClick={onEdit}>
          Edit Config
        </Button>
        <Button color={COLORS.red} sm onClick={onDisable}>
          Disable
        </Button>
      </div>
    </div>

    {/* Description */}
    <Panel style={{ padding: 16, marginBottom: 14 }}>
      <div style={{ fontSize: 13, color: COLORS.textDim, lineHeight: 1.7 }}>
        {agent.desc}
      </div>
    </Panel>

    {/* Sidecar Manifest */}
    <Panel style={{ marginBottom: 14 }}>
      <PanelHeader
        icon="📄"
        title="Sidecar Manifest"
        color={agent.color}
        right={
          <Button color={agent.color} sm>
            Copy YAML
          </Button>
        }
      />
      <div
        style={{
          padding: 14,
          fontFamily: 'monospace',
          fontSize: 11,
          lineHeight: 1.9,
          background: '#000',
          borderRadius: '0 0 10px 10px',
          color: COLORS.textDim,
          overflow: 'auto',
          maxHeight: 280,
        }}
      >
        <div style={{ color: COLORS.muted }}># Injected into values-2030.yaml automatically</div>
        <div>
          <span style={{ color: COLORS.cyan }}>- name: </span>
          <span style={{ color: COLORS.green }}>{agent.id}-agent</span>
        </div>
        <div style={{ paddingLeft: 16 }}>
          <span style={{ color: COLORS.cyan }}>image: </span>
          <span style={{ color: COLORS.text }}>ghcr.io/runnercloud/{agent.id}-agent:v2</span>
        </div>
        <div style={{ paddingLeft: 16 }}>
          <span style={{ color: COLORS.cyan }}>resources:</span>
        </div>
        <div style={{ paddingLeft: 32 }}>
          <span style={{ color: COLORS.cyan }}>requests: </span>
          <span style={{ color: COLORS.yellow }}>{'{ cpu: 100m, memory: 256Mi }'}</span>
        </div>
        <div style={{ paddingLeft: 16 }}>
          <span style={{ color: COLORS.cyan }}>env:</span>
        </div>
        {Object.entries(agent.config).map(([k, v]) => (
          <div key={k} style={{ paddingLeft: 32 }}>
            <span style={{ color: COLORS.purple }}>- {k}: </span>
            <span style={{ color: COLORS.orange }}>{String(v)}</span>
          </div>
        ))}
      </div>
    </Panel>

    {/* Live Activity */}
    <Panel>
      <PanelHeader icon="📡" title="Live Activity" color={agent.color} />
      <div style={{ padding: '10px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        {[
          {
            time: '2s ago',
            msg: `${agent.name} triggered on runner rc-byoc-c1d4e`,
            type: 'info' as const,
          },
          { time: '14s ago', msg: 'Analysis complete — confidence 94% — fix PR opened', type: 'success' as const },
          {
            time: '1m ago',
            msg: `${agent.name} triggered on runner rc-managed-a3f9b`,
            type: 'info' as const,
          },
          {
            time: '3m ago',
            msg: 'Low confidence (62%) — posted suggestion only, no auto-fix',
            type: 'warn' as const,
          },
        ].map((a, i) => (
          <div
            key={i}
            style={{
              display: 'flex',
              gap: 10,
              alignItems: 'flex-start',
              padding: '6px 8px',
              background: '#ffffff03',
              borderRadius: 5,
            }}
          >
            <span
              style={{
                fontSize: 10,
                color:
                  a.type === 'info'
                    ? COLORS.accent
                    : a.type === 'success'
                    ? COLORS.green
                    : COLORS.yellow,
                marginTop: 1,
              }}
            >
              ●
            </span>
            <span style={{ fontSize: 11, color: COLORS.textDim, flex: 1 }}>
              {a.msg}
            </span>
            <span style={{ fontSize: 9, color: COLORS.muted, whiteSpace: 'nowrap' }}>
              {a.time}
            </span>
          </div>
        ))}
      </div>
    </Panel>
  </div>
);

/**
 * Intent Editor - Alternative tab for markdown-based agent config
 */
const IntentEditor: React.FC = () => {
  const [intent, setIntent] = useState(`# My CI Agent
Goal: Run tests and build on every push to main

## Rules
- If PR label is "experimental": use lighter matrix
- If changes only in /docs: skip tests entirely  
- If test failure: retry once, then post debug summary
- Always: post carbon score in PR comment
- Never: deploy to production without human approval

## Tools
- slack: post summary to #deploys
- jira: create ticket on repeated failures`);

  return (
    <div style={{ padding: 20, flex: 1, overflowY: 'auto' }}>
      <div style={{ fontSize: 15, fontWeight: 800, color: COLORS.text, marginBottom: 4 }}>
        Intent Editor
      </div>
      <div style={{ fontSize: 11, color: COLORS.muted, marginBottom: 14 }}>
        Write CI logic in plain Markdown. RunnerCloud compiles it to a workflow + agent config.
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
        <Panel>
          <PanelHeader icon="📝" title="Intent (Markdown)" color={COLORS.accent} />
          <textarea
            value={intent}
            onChange={(e) => setIntent(e.target.value)}
            style={{
              width: '100%',
              background: '#000',
              border: 'none',
              color: COLORS.text,
              fontFamily: 'monospace',
              fontSize: 11,
              lineHeight: 1.8,
              padding: 14,
              borderRadius: '0 0 10px 10px',
              resize: 'vertical',
              minHeight: 280,
              boxSizing: 'border-box',
              outline: 'none',
            }}
          />
        </Panel>
        <Panel>
          <PanelHeader
            icon="⚙"
            title="Compiled Output"
            color={COLORS.green}
            right={<Button color={COLORS.green} sm>Deploy</Button>}
          />
          <div
            style={{
              padding: 14,
              fontFamily: 'monospace',
              fontSize: 10,
              lineHeight: 1.9,
              color: COLORS.textDim,
              background: '#000',
              borderRadius: '0 0 10px 10px',
              minHeight: 280,
              overflow: 'auto',
            }}
          >
            <div style={{ color: COLORS.muted }}># Auto-generated — do not edit</div>
            <div>
              <span style={{ color: COLORS.cyan }}>on:</span> [push, pull_request]
            </div>
            <div>
              <span style={{ color: COLORS.cyan }}>jobs:</span>
            </div>
            <div style={{ paddingLeft: 16 }}>
              <span style={{ color: COLORS.green }}>agentic-ci:</span>
            </div>
            <div style={{ paddingLeft: 32 }}>
              <span style={{ color: COLORS.cyan }}>runs-on:</span> runnercloud-ubuntu-latest
            </div>
            <div style={{ paddingLeft: 32 }}>
              <span style={{ color: COLORS.cyan }}>steps:</span>
            </div>
            <div style={{ paddingLeft: 48, color: COLORS.purple }}>
              - uses: runnercloud/agent-runner@v2
            </div>
            <div style={{ paddingLeft: 56 }}>
              <span style={{ color: COLORS.cyan }}>with:</span>
            </div>
            <div style={{ paddingLeft: 64 }}>
              <span style={{ color: COLORS.cyan }}>intent:</span> .github/agents/ci-intent.md
            </div>
            <div style={{ paddingLeft: 64 }}>
              <span style={{ color: COLORS.cyan }}>agents:</span> [oracle, perf, security]
            </div>
            <div style={{ marginTop: 8, color: COLORS.green }}>✓ Docs-only path: test skip injected</div>
            <div style={{ color: COLORS.green }}>✓ Retry policy: 1x on failure</div>
            <div style={{ color: COLORS.green }}>✓ Carbon score action: appended</div>
            <div style={{ color: COLORS.yellow }}>⚠ Production deploy: manual approval gate added</div>
          </div>
        </Panel>
      </div>
    </div>
  );
};

/**
 * Agent Studio - Main component
 */
export const AgentStudio: React.FC = () => {
  const [selectedAgent, setSelectedAgent] = useState<string>('oracle');
  const [activeTab, setActiveTab] = useState<'roster' | 'intent'>('roster');

  const selected = AGENT_PERSONAS.find((a) => a.id === selectedAgent);

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      {/* Tab Navigation */}
      <div
        style={{
          display: 'flex',
          gap: 0,
          borderBottom: `1px solid ${COLORS.border}`,
          background: COLORS.surface,
          padding: '0 20px',
        }}
      >
        {[
          { id: 'roster', label: 'Agent Roster' },
          { id: 'intent', label: 'Intent Editor' },
        ].map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id as 'roster' | 'intent')}
            style={{
              background: 'transparent',
              border: 'none',
              borderBottom:
                activeTab === tab.id ? `2px solid ${COLORS.purple}` : '2px solid transparent',
              color: activeTab === tab.id ? COLORS.purple : COLORS.textDim,
              padding: '10px 16px',
              fontSize: 12,
              fontWeight: activeTab === tab.id ? 700 : 400,
              cursor: 'pointer',
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Content */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {activeTab === 'roster' && selected ? (
          <>
            <AgentRoster
              agents={AGENT_PERSONAS}
              selected={selectedAgent}
              onSelect={setSelectedAgent}
            />
            <AgentDetail
              agent={selected}
              onEdit={() => console.log('edit config')}
              onDisable={() => console.log('disable agent')}
            />
          </>
        ) : (
          <IntentEditor />
        )}
      </div>
    </div>
  );
};

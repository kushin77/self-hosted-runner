import React, { useState, useEffect } from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader, Pill } from '../components/UI';
import { api, subscribeToEventStream } from '../api';

/**
 * Security Event Interface
 */
export interface SecurityEvent {
  time: string;
  type: 'blocked' | 'allowed' | 'sbom' | 'vulnerability';
  severity: 'info' | 'warn' | 'high' | 'critical';
  msg: string;
  details?: string;
}

const EMPTY_EVENTS: SecurityEvent[] = [];

/**
 * Supply Chain Facts
 */
const SUPPLY_CHAIN_FACTS = [
  { label: 'Blocked Today', val: '3', color: COLORS.red },
  { label: 'SBOM Generated', val: '47', color: COLORS.cyan },
  { label: 'CVEs Flagged', val: '2 LOW', color: COLORS.yellow },
  { label: 'Approved Registries', val: '6', color: COLORS.green },
];

/**
 * Security Layer - eBPF Monitoring Page
 */
export const Security: React.FC = () => {
  const [expandedEvent, setExpandedEvent] = useState<number | null>(null);
  const [filter, setFilter] = useState<'all' | 'blocked' | 'sbom' | 'vulnerability'>('all');
  const [events, setEvents] = useState<SecurityEvent[]>(EMPTY_EVENTS);

  useEffect(() => {
    let mounted = true;
    api.getEvents()
      .then((evs: any[]) => {
        if (!mounted) return;
        const mapped: SecurityEvent[] = evs.map((e) => ({
          time: e.time || new Date(e.timestamp).toLocaleString(),
          type: e.type,
          severity: e.severity === 'warn' ? 'warn' : e.severity, // normalize
          msg: (e.message as string) || (e.msg as string) || '',
          details: e.details || (e.metadata ? JSON.stringify(e.metadata, null, 2) : undefined),
        }));
        setEvents(mapped);
      })
      .catch(() => setEvents([]));

    // subscribe to live stream and prepend events
    const sub = subscribeToEventStream((ev: any) => {
      if (!mounted || !ev) return;
      const mapped: SecurityEvent = {
        time: ev.time || new Date(ev.timestamp).toLocaleString(),
        type: ev.type === 'job_failed' || ev.type === 'runner_failed' ? 'blocked' : (ev.type as any) || 'allowed',
        severity: ev.severity === 'error' ? 'high' : ev.severity === 'warning' ? 'warn' : 'info',
        msg: ev.message || ev.msg || `${ev.type} on ${ev.runnerId || 'unknown'}`,
        details: ev.details || (ev.metadata ? JSON.stringify(ev.metadata, null, 2) : undefined),
      };
      setEvents((prev) => [mapped, ...prev].slice(0, 200));
    }, (err) => {
      // ignore for now
    });

    return () => {
      mounted = false;
      try { sub.close(); } catch (_) {}
    };
  }, []);

  const filteredEvents = events.filter((e) => {
    if (filter === 'all') return true;
    return e.type === filter;
  });

  const sevColorMap = {
    info: COLORS.green,
    warn: COLORS.yellow,
    high: COLORS.red,
    critical: COLORS.red,
  };

  const typeIconMap = {
    blocked: '🚫',
    allowed: '✅',
    sbom: '📋',
    vulnerability: '☠️',
  };

  return (
    <div style={{ flex: 1, padding: 20, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 800, color: COLORS.text, marginBottom: 4 }}>
          Security Layer
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          eBPF sidecar (Falco + Tetragon) · SBOM generation · Network allowlisting · Supply chain
          verification
        </div>
      </div>

      {/* Supply Chain Stats */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {SUPPLY_CHAIN_FACTS.map((s) => (
          <Panel key={s.label} style={{ padding: '12px 14px' }}>
            <div
              style={{
                fontSize: 9,
                color: COLORS.muted,
                textTransform: 'uppercase',
                letterSpacing: '0.08em',
                marginBottom: 4,
              }}
            >
              {s.label}
            </div>
            <div
              style={{
                fontSize: 20,
                fontWeight: 800,
                color: s.color,
                textShadow: `0 0 12px ${s.color}55`,
              }}
            >
              {s.val}
            </div>
          </Panel>
        ))}
      </div>

      {/* Filters */}
      <div style={{ display: 'flex', gap: 8 }}>
        {['all', 'blocked', 'sbom', 'vulnerability'].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f as any)}
            style={{
              background: filter === f ? COLORS.accent + '22' : COLORS.border,
              border: filter === f ? `1px solid ${COLORS.accent}` : '1px solid transparent',
              color: filter === f ? COLORS.accent : COLORS.textDim,
              borderRadius: 4,
              padding: '4px 12px',
              fontSize: 11,
              cursor: 'pointer',
              fontWeight: filter === f ? 700 : 400,
              textTransform: 'capitalize',
            }}
          >
            {f}
          </button>
        ))}
      </div>

      {/* eBPF Event Stream */}
      <Panel glowColor={COLORS.red}>
        <PanelHeader icon="🛡" title="eBPF Event Stream" color={COLORS.red} />
        <div style={{ padding: '10px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
          {filteredEvents.map((e, i) => (
            <div
              key={i}
              onClick={() => setExpandedEvent(expandedEvent === i ? null : i)}
              style={{
                background:
                  e.severity === 'high' || e.severity === 'critical'
                    ? COLORS.red + '08'
                    : e.severity === 'warn'
                    ? COLORS.yellow + '08'
                    : '#ffffff03',
                border: `1px solid ${
                  e.severity === 'high' || e.severity === 'critical'
                    ? COLORS.red
                    : e.severity === 'warn'
                    ? COLORS.yellow
                    : COLORS.border
                }22`,
                borderRadius: 6,
                padding: '8px 10px',
                display: 'flex',
                gap: 10,
                alignItems: 'flex-start',
                cursor: 'pointer',
                transition: 'all 0.2s ease',
              }}
            >
              <span style={{ fontSize: 12, marginTop: 1 }}>
                {typeIconMap[e.type]}
              </span>
              <span style={{ fontSize: 11, color: COLORS.textDim, flex: 1 }}>
                {e.msg}
              </span>
              <span style={{ fontSize: 9, color: COLORS.muted, whiteSpace: 'nowrap' }}>
                {e.time}
              </span>
              <span style={{ fontSize: 10, color: sevColorMap[e.severity] }}>
                {expandedEvent === i ? '▲' : '▼'}
              </span>
            </div>
          ))}
          {filteredEvents.length === 0 && (
            <div style={{ padding: 16, textAlign: 'center', color: COLORS.muted }}>
              <div style={{ fontSize: 12 }}>No events found</div>
            </div>
          )}

          {/* Expanded Details */}
          {expandedEvent !== null && filteredEvents[expandedEvent]?.details && (
            <div
              style={{
                marginTop: 4,
                padding: 12,
                background: '#000',
                borderRadius: 6,
                borderLeft: `3px solid ${sevColorMap[filteredEvents[expandedEvent].severity]}`,
                fontFamily: 'monospace',
                fontSize: 10,
                lineHeight: 1.6,
                color: COLORS.textDim,
              }}
            >
              <div style={{ marginBottom: 4, color: COLORS.muted }}>Details:</div>
              {filteredEvents[expandedEvent].details}
            </div>
          )}
        </div>
      </Panel>

      {/* Network Policy */}
      <Panel>
        <PanelHeader icon="🌐" title="Network Allowlist" color={COLORS.cyan} />
        <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { endpoint: 'registry.npmjs.org', status: 'active', ports: '443 (HTTPS)' },
            { endpoint: 'ghcr.io', status: 'active', ports: '443 (HTTPS)' },
            { endpoint: 'github.com', status: 'active', ports: '443 (HTTPS)' },
            { endpoint: '*.sigstore.dev', status: 'active', ports: '443 (HTTPS)' },
            { endpoint: 'api.electricitymap.org', status: 'active', ports: '443 (HTTPS)' },
            { endpoint: 'slack.com', status: 'active', ports: '443 (HTTPS)' },
          ].map((item, i) => (
            <div
              key={i}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                padding: '7px 0',
                borderBottom: i < 5 ? `1px solid ${COLORS.border}` : 'none',
              }}
            >
              <div
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: '50%',
                  background: COLORS.green,
                  boxShadow: `0 0 8px ${COLORS.green}`,
                  flexShrink: 0,
                }}
              />
              <span style={{ fontSize: 11, color: COLORS.text, width: 140 }}>
                {item.endpoint}
              </span>
              <span style={{ fontSize: 10, color: COLORS.muted, flex: 1 }}>
                {item.ports}
              </span>
              <Pill color="green" sm>
                {item.status}
              </Pill>
            </div>
          ))}
        </div>
      </Panel>

      {/* Compliance Status */}
      <Panel glowColor={COLORS.green}>
        <PanelHeader icon="✓" title="Compliance Status" color={COLORS.green} />
        <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { check: 'SOC 2 Audit Trail', status: 'compliant', detail: 'Last audit: 2026-02-15' },
            { check: 'HIPAA Network Isolation', status: 'compliant', detail: 'eBPF enforcement active' },
            {
              check: 'SPDX SBOM Export',
              status: 'compliant',
              detail: 'Generation rate: 47/day',
            },
            { check: 'CVE Scanning', status: 'compliant', detail: 'Real-time with Grype' },
            { check: 'Air-Gap Support', status: 'compliant', detail: 'Available on BYOC' },
          ].map((item, i) => (
            <div
              key={i}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: '7px 0',
                borderBottom: i < 4 ? `1px solid ${COLORS.border}` : 'none',
              }}
            >
              <div>
                <div style={{ fontSize: 11, color: COLORS.text }}>{item.check}</div>
                <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 2 }}>
                  {item.detail}
                </div>
              </div>
              <Pill color="green" sm>
                ✓ {item.status}
              </Pill>
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
};

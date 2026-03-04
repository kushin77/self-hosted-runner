import React, { useEffect, useState, useRef } from 'react';
import { apiClient } from '../api/client';
import { Panel } from '../components/UI';
import { COLORS } from '../theme';

interface LiveEvent {
  id: string;
  type: string;
  timestamp: number;
  message?: string;
  runnerId?: string;
  [k: string]: any;
}

export const LiveEvents: React.FC<{ onCountChange?: (n: number) => void }> = ({ onCountChange }) => {
  const [events, setEvents] = useState<LiveEvent[]>([]);
  const [running, setRunning] = useState(true);
  const bufferRef = useRef<LiveEvent[]>([]);
  const maxEvents = 200;
  const [filterText, setFilterText] = useState('');
  const [filterType, setFilterType] = useState('');

  useEffect(() => {
    if (!running) return;

    const sub = apiClient.subscribeToEventStream((ev) => {
      const e: LiveEvent = {
        ...ev,
        id: ev.id ?? `evt-${Date.now()}`,
        type: ev.type ?? 'event',
        timestamp: ev.timestamp ?? Date.now(),
        message: ev.message ?? JSON.stringify(ev),
      } as LiveEvent;

      bufferRef.current.unshift(e);
      if (bufferRef.current.length >= 10) {
        setEvents(prev => {
          const merged = [...bufferRef.current, ...prev].slice(0, maxEvents);
          bufferRef.current = [];
          return merged;
        });
      }
    });

    const flush = setInterval(() => {
      if (bufferRef.current.length === 0) return;
      setEvents(prev => {
        const merged = [...bufferRef.current, ...prev].slice(0, maxEvents);
        bufferRef.current = [];
        return merged;
      });
    }, 1000);

    return () => {
      if (sub && typeof sub.close === 'function') sub.close();
      clearInterval(flush);
    };
  }, [running]);

  useEffect(() => {
    if (onCountChange) onCountChange(events.length);
  }, [events.length, onCountChange]);

  const filtered = events.filter(ev => {
    if (filterType && ev.type !== filterType) return false;
    if (filterText) {
      const s = `${ev.type} ${ev.message} ${ev.runnerId ?? ''}`.toLowerCase();
      if (!s.includes(filterText.toLowerCase())) return false;
    }
    return true;
  });

  return (
    <Panel style={{ padding: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ fontWeight: 800, fontSize: 14 }}>Live Events</div>
        <div style={{ display: 'flex', gap: 8 }}>
          <input placeholder="Filter text" value={filterText} onChange={e => setFilterText(e.target.value)} style={{ padding: '6px 8px', borderRadius: 6, border: `1px solid ${COLORS.border}` }} />
          <input placeholder="Type (e.g. job_completed)" value={filterType} onChange={e => setFilterType(e.target.value)} style={{ padding: '6px 8px', borderRadius: 6, border: `1px solid ${COLORS.border}` }} />
          <button
            onClick={() => setEvents([])}
            style={{ background: 'transparent', border: `1px solid ${COLORS.border}`, padding: '6px 10px', borderRadius: 6 }}
          >
            Clear
          </button>
          <button
            onClick={() => setRunning(r => !r)}
            style={{ background: running ? COLORS.red : COLORS.green, color: '#fff', border: 'none', padding: '6px 10px', borderRadius: 6 }}
          >
            {running ? 'Pause' : 'Resume'}
          </button>
        </div>
      </div>

      <div style={{ marginTop: 10, maxHeight: 'calc(100vh - 200px)', overflowY: 'auto' }}>
        {filtered.length === 0 && <div style={{ color: COLORS.muted, padding: 12 }}>No events match filters.</div>}
        {filtered.map(ev => (
          <div key={ev.id} style={{ padding: 10, borderBottom: `1px solid ${COLORS.border}`, display: 'flex', gap: 12 }}>
            <div style={{ minWidth: 96, fontSize: 11, color: COLORS.muted }}>{new Date(ev.timestamp).toLocaleTimeString()}</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 700 }}>{ev.type}</div>
              <div style={{ fontSize: 12, color: COLORS.text }}>{ev.message}</div>
              {ev.runnerId && <div style={{ fontSize: 11, color: COLORS.muted, marginTop: 6 }}>Runner: {ev.runnerId}</div>}
            </div>
          </div>
        ))}
      </div>
    </Panel>
  );
};

export default LiveEvents;

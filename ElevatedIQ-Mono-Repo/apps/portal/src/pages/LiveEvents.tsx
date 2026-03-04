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

export const LiveEvents: React.FC = () => {
  const [events, setEvents] = useState<LiveEvent[]>([]);
  const [running, setRunning] = useState(true);
  const bufferRef = useRef<LiveEvent[]>([]);
  const maxEvents = 200;

  useEffect(() => {
    if (!running) return;

    const sub = apiClient.subscribeToEventStream((ev) => {
      const e: LiveEvent = {
        id: ev.id || `evt-${Date.now()}`,
        type: ev.type || 'event',
        timestamp: ev.timestamp || Date.now(),
        message: ev.message || JSON.stringify(ev),
        runnerId: ev.runnerId,
        ...ev,
      } as LiveEvent;

      // simple buffering to avoid excessive re-renders
      bufferRef.current.unshift(e);
      if (bufferRef.current.length >= 10) {
        setEvents(prev => {
          const merged = [...bufferRef.current, ...prev].slice(0, maxEvents);
          bufferRef.current = [];
          return merged;
        });
      }
    });

    // flush buffer periodically
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

  return (
    <Panel style={{ padding: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ fontWeight: 800, fontSize: 14 }}>Live Events</div>
        <div style={{ display: 'flex', gap: 8 }}>
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
        {events.length === 0 && <div style={{ color: COLORS.muted, padding: 12 }}>No events yet.</div>}
        {events.map(ev => (
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

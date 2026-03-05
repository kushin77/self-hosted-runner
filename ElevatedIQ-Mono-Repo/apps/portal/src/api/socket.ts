import { io, Socket } from 'socket.io-client';
import { useEffect, useRef } from 'react';
import type { ServerToClientEvents, ClientToServerEvents } from './socket.types';
import { useStore } from './store';

export function createSocket(url = 'http://localhost:9090') {
  return io<ClientToServerEvents, ServerToClientEvents>(url, {
    path: '/socket.io',
    autoConnect: false,
    transports: ['websocket', 'polling'],
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 1000,
    reconnectionDelayMax: 60000,
    timeout: 20000,
  });
}

export function useSocket(opts?: { url?: string; autoConnect?: boolean }) {
  const ref = useRef<Socket<ClientToServerEvents, ServerToClientEvents> | null>(null);

  useEffect(() => {
    const url = opts?.url ?? 'http://localhost:9090';
    const sock = createSocket(url);
    ref.current = sock;

    const onConnect = () => {
      console.debug('[portal-socket] connected', sock.id);
      useStore.getState().setSocketConnected(true);
    };
    const onConnectError = (err: any) => {
      console.warn('[portal-socket] connect_error', err);
    };

    sock.on('connect', onConnect);
    sock.on('connect_error', onConnectError);

    sock.on('metrics:update', (payload) => {
      useStore.getState().setMetrics(payload);
    });

    sock.on('job:event', (event) => {
      const currentJobs = useStore.getState().jobs;
      const updatedJobs = currentJobs.some((j) => j.id === event.id)
        ? currentJobs.map((j) => (j.id === event.id ? event : j))
        : [event, ...currentJobs].slice(0, 100);
      useStore.getState().setJobs(updatedJobs);
    });

    sock.on('alert:new', (alert) => {
      useStore.getState().addAlert(alert);
    });

    if (opts?.autoConnect ?? true) sock.connect();

    sock.on('disconnect', () => {
      useStore.getState().setSocketConnected(false);
    });

    return () => {
      sock.off('connect', onConnect);
      sock.off('connect_error', onConnectError);
      sock.off('disconnect');
      sock.disconnect();
      ref.current = null;
    };
  }, [opts?.url]);

  return ref;
}

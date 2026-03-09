import { io, Socket } from 'socket.io-client'
import { useEffect, useRef } from 'react'
import type { ServerToClientEvents, ClientToServerEvents } from './socket.types'
import { useStore } from './store'

// Simple typed socket factory and React hook for Phase 2 WebSocket migration.
// Usage: const socketRef = useSocket({ url: 'http://localhost:9090' })

export function createSocket(url = 'http://192.168.168.42:9090') {
  return io<ClientToServerEvents, ServerToClientEvents>(url, {
    path: '/socket.io',
    autoConnect: false,
    transports: ['websocket', 'polling'],
    reconnection: true,
    reconnectionAttempts: 10,
    reconnectionDelay: 2000,
    reconnectionDelayMax: 10000,
    randomizationFactor: 0.5,
    timeout: 20000,
  })
}

export function useSocket(opts?: { url?: string; autoConnect?: boolean }) {
  const ref = useRef<Socket<ClientToServerEvents, ServerToClientEvents> | null>(null)

  useEffect(() => {
    const url = opts?.url ?? 'http://192.168.168.42:9090'
    const sock = createSocket(url)
    ref.current = sock

    function onConnect() {
      /* eslint-disable no-console */
      console.info('[socket] connected successfully:', sock.id)
    }

    function onConnectError(err: Error) {
      console.error('[socket] connection error:', err.message)
    }

    function onDisconnect(reason: string) {
      console.warn('[socket] disconnected:', reason)
      if (reason === 'io server disconnect') {
        // the disconnection was initiated by the server, you need to reconnect manually
        sock.connect()
      }
    }

    function onReconnect(attempt: number) {
      console.info('[socket] reconnected after', attempt, 'attempts')
    }

    function onReconnectError(err: Error) {
      console.error('[socket] reconnection error:', err.message)
    }

    sock.on('connect', onConnect)
    sock.on('connect_error', onConnectError)
    sock.on('disconnect', onDisconnect)
    sock.on('reconnect', onReconnect)
    sock.on('reconnect_error', onReconnectError)

    // Example listeners - replace with real handlers that update Zustand store
    sock.on('metrics:update', (payload) => {
      console.debug('[socket] metrics:update', payload)
      useStore.getState().setMetrics(payload)
    })

    sock.on('job:event', (event) => {
      console.debug('[socket] job:event', event)
      const currentJobs = useStore.getState().jobs;
      const updatedJobs = currentJobs.some(j => j.id === event.id)
        ? currentJobs.map(j => j.id === event.id ? event : j)
        : [event, ...currentJobs].slice(0, 100);
      useStore.getState().setJobs(updatedJobs);
    })

    sock.on('alert:new', (alert) => {
      console.debug('[socket] alert:new', alert)
      useStore.getState().addAlert(alert);
    })

    if (opts?.autoConnect ?? true) sock.connect()

    return () => {
      sock.off('connect', onConnect)
      sock.disconnect()
      ref.current = null
    }
  }, [opts?.url])

  return ref
}

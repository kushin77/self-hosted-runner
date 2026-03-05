import { io, Socket } from 'socket.io-client'
import { useEffect, useRef } from 'react'
import type { ServerToClientEvents, ClientToServerEvents } from './socket.types'

// Simple typed socket factory and React hook for Phase 2 WebSocket migration.
// Usage: const socketRef = useSocket({ url: 'http://localhost:9090' })

export function createSocket(url = 'http://localhost:9090') {
  return io<ClientToServerEvents, ServerToClientEvents>(url, {
    path: '/socket.io',
    autoConnect: false,
    transports: ['websocket', 'polling'],
  })
}

export function useSocket(opts?: { url?: string; autoConnect?: boolean }) {
  const ref = useRef<Socket<ClientToServerEvents, ServerToClientEvents> | null>(null)

  useEffect(() => {
    const url = opts?.url ?? 'http://localhost:9090'
    const sock = createSocket(url)
    ref.current = sock

    function onConnect() {
      /* eslint-disable no-console */
      console.debug('[socket] connected', sock.id)
    }

    sock.on('connect', onConnect)

    // Example listeners - replace with real handlers that update Zustand store
    sock.on('metrics:update', (payload) => {
      console.debug('[socket] metrics:update', payload)
      // TODO: push to store e.g. useStore.getState().setMetrics(payload)
    })

    sock.on('job:event', (event) => {
      console.debug('[socket] job:event', event)
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

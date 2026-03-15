import React, { Suspense, lazy } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const Dashboard = lazy(() => import('./components/Dashboard'))

const container = document.getElementById('root')!
const root = createRoot(container)

root.render(
  <React.StrictMode>
    <Suspense fallback={<div style={{ padding: '1rem' }}>Loading portal...</div>}>
      <Dashboard />
    </Suspense>
  </React.StrictMode>
)

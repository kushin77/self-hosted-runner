import React from 'react'
import { createRoot } from 'react-dom/client'
import GitPeakPortal from '../GitPeak'
import '../GitPeak.module.css'

const rootEl = document.getElementById('root')
if (!rootEl) throw new Error('Root element not found')

createRoot(rootEl).render(
  <React.StrictMode>
    <GitPeakPortal />
  </React.StrictMode>
)

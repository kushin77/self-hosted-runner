import React from 'react'
import ReactDOM from 'react-dom/client'
import Portal from './Portal'

const root = document.getElementById('root')
if (root) {
  ReactDOM.createRoot(root).render(
    <React.StrictMode>
      <Portal />
    </React.StrictMode>
  )
}

import React, { useState } from 'react'
import './App.css'
import Dashboard from './pages/Dashboard'
import Jobs from './pages/Jobs'
import JobDetails from './pages/JobDetails'
import Metrics from './pages/Metrics'
import { clearAdminKey } from './api'

export default function App() {
  const [currentPage, setCurrentPage] = useState('dashboard')
  const [selectedJobId, setSelectedJobId] = useState(null)

  const handleSelectJob = (jobId) => {
    setSelectedJobId(jobId)
    setCurrentPage('details')
  }

  const handleLogout = () => {
    clearAdminKey()
    window.location.reload()
  }

  const renderPage = () => {
    switch (currentPage) {
      case 'dashboard':
        return <Dashboard onNavigate={setCurrentPage} />
      case 'jobs':
        return <Jobs onSelectJob={handleSelectJob} />
      case 'details':
        return <JobDetails jobId={selectedJobId} onBack={() => setCurrentPage('jobs')} />
      case 'metrics':
        return <Metrics />
      default:
        return <Dashboard onNavigate={setCurrentPage} />
    }
  }

  return (
    <div className="app">
      <header className="navbar">
        <div className="navbar-brand">
          <h1>NexusShield Migration Dashboard</h1>
        </div>
        <nav className="navbar-nav">
          <button
            className={`nav-btn ${currentPage === 'dashboard' ? 'active' : ''}`}
            onClick={() => setCurrentPage('dashboard')}
          >
            Dashboard
          </button>
          <button
            className={`nav-btn ${currentPage === 'jobs' ? 'active' : ''}`}
            onClick={() => setCurrentPage('jobs')}
          >
            Jobs
          </button>
          <button
            className={`nav-btn ${currentPage === 'metrics' ? 'active' : ''}`}
            onClick={() => setCurrentPage('metrics')}
          >
            Metrics
          </button>
          <button className="nav-btn logout-btn" onClick={handleLogout}>
            Logout
          </button>
        </nav>
      </header>

      <main className="main-content">
        {renderPage()}
      </main>

      <footer className="footer">
        <p>NexusShield v1.0 | Immutable Audit Trail | GSM/Vault/KMS Credentials</p>
      </footer>
    </div>
  )
}

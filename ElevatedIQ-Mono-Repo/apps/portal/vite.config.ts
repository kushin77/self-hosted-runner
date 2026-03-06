import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    // Aggressive code splitting to prevent single-bundle renderer hangs
    rollupOptions: {
      output: {
        manualChunks: {
          // Vendor chunks
          'vendor-react': ['react', 'react-dom'],
          'vendor-charts': ['recharts'],
          'vendor-socket': ['socket.io-client'],
          'vendor-ui': ['lucide-react'],
          'vendor-state': ['zustand'],
          
          // Page chunks - each page lazy-loaded separately
          'page-dashboard': ['./src/pages/Dashboard.tsx'],
          'page-agents': ['./src/pages/AgentStudio.tsx'],
          'page-deploy': ['./src/pages/DeployMode.tsx'],
          'page-runners': ['./src/pages/Runners.tsx'],
          'page-oracle': ['./src/pages/AIOracleContent.tsx'],
          'page-cache': ['./src/pages/LiveMirrorCache.tsx'],
          'page-security': ['./src/pages/Security.tsx'],
          'page-windows': ['./src/pages/WindowsRunners.tsx'],
          'page-billing': ['./src/pages/Billing.tsx'],
          'page-settings': ['./src/pages/Settings.tsx'],
          'page-observability': ['./src/pages/Observability.tsx'],
          'page-showcase': ['./src/pages/ComponentShowcase.tsx'],
          'page-functions': ['./src/pages/RepoFunctions.tsx'],
          'page-landing': ['./src/pages/LandingPage.tsx'],
          
          // Common components
          'common': ['./src/components/Layout.tsx', './src/components/UI.tsx'],
        },
      },
    },
    // Chunk size warning thresholds
    chunkSizeWarningLimit: 300,
  },
  server: {
    // expose on all interfaces so remote hosts can connect (required for
    // `192.168.168.42:3919` visibility). allow overriding via PORT env var
    host: '0.0.0.0',
    port: process.env.PORT ? parseInt(process.env.PORT, 10) : 3919,
    open: true,
  },
})

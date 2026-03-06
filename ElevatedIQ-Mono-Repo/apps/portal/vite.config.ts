import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

/**
 * Plugin to remove modulepreload hints for lazy-loaded page chunks.
 * This prevents the browser from eagerly downloading all pages at startup.
 */
function filterPagePreloads() {
  return {
    name: 'filter-page-preloads',
    transformIndexHtml(html) {
      // Remove modulepreload links for page-* chunks (they are lazy-loaded)
      return html.replace(
        /<link rel="modulepreload"[^>]*href="\/assets\/page-[^"]*"[^>]*>/g,
        ''
      )
    },
  }
}

export default defineConfig({
  plugins: [react(), filterPagePreloads()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    // Force Vite to generate separate chunks for dynamic imports
    rollupOptions: {
      output: {
        // Just split vendor libs, let dynamic imports create per-page chunks
        manualChunks: (id) => {
          // Avoid circular dependencies by being very specific with paths
          if (id.includes('node_modules/recharts')) return 'vendor-charts'
          if (id.includes('node_modules/socket.io')) return 'vendor-socket'
          if (id.includes('node_modules/lucide-react')) return 'vendor-ui'
          if (id.includes('node_modules/zustand')) return 'vendor-state'
          if (id.includes('node_modules/react')) return 'vendor-react'
          // Let other dependencies split naturally
          return undefined
        },
      },
    },
    // High threshold to avoid warnings with many chunks
    chunkSizeWarningLimit: 2000,
  },
  server: {
    // expose on all interfaces so remote hosts can connect (required for
    // `192.168.168.42:3919` visibility). allow overriding via PORT env var
    host: '0.0.0.0',
    port: process.env.PORT ? parseInt(process.env.PORT, 10) : 3919,
    open: true,
  },
})

import { defineConfig, splitVendorChunkPlugin } from 'vite';
import react from '@vitejs/plugin-react';

// Build optimization for lower client CPU on first load via deterministic chunking.
export default defineConfig({
  plugins: [react(), splitVendorChunkPlugin()],
  build: {
    sourcemap: false,
    target: 'es2020',
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) {
            return;
          }

          if (id.includes('recharts')) {
            return 'vendor-recharts';
          }

          if (id.includes('@reduxjs') || id.includes('react-redux') || id.includes('redux')) {
            return 'vendor-state';
          }

          if (id.includes('axios')) {
            return 'vendor-axios';
          }

          return;
        },
      },
    },
    chunkSizeWarningLimit: 450,
  },
});

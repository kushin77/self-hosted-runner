import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3919;
const DIST_DIR = path.join(__dirname, 'dist');
// Serve static files from dist
app.use(express.static(DIST_DIR, {
    maxAge: '1h',
    etag: true,
    setHeaders: (res, path) => {
        // Cache assets with content hash for long-term caching
        if (path.match(/\.[a-f0-9]{8}\.(js|css)$/)) {
            res.set('Cache-Control', 'public, max-age=31536000, immutable');
        }
        // Cache index.html for shorter duration to allow updates
        else if (path.endsWith('index.html')) {
            res.set('Cache-Control', 'public, max-age=3600, must-revalidate');
        }
    },
}));
// SPA fallback: serve index.html for all non-asset routes
app.use((req, res) => {
    res.sendFile(path.join(DIST_DIR, 'index.html'), (err) => {
        if (err) {
            res.status(404).send('Not Found');
        }
    });
});
app.listen(PORT, '0.0.0.0', () => {
    console.log(`✓ Portal running at http://0.0.0.0:${PORT}`);
});

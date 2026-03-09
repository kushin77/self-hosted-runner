# NexusShield Portal — Frontend Dashboard

**Status:** MVP Implementation Starting | **Language:** TypeScript/React | **Styling:** Tailwind CSS

## Quick Start

```bash
cd frontend
npm install
npm run dev  # Development server (hot-reload, http://localhost:3000)
```

## Project Structure

```
frontend/
├── src/
│   ├── App.tsx             # Root component
│   ├── main.tsx            # Entry point
│   ├── pages/
│   │   ├── Dashboard.tsx    # Main dashboard
│   │   ├── Credentials.tsx  # Credentials tab
│   │   ├── Deployments.tsx  # Deployments tab
│   │   ├── Compliance.tsx   # Compliance tab
│   │   └── Settings.tsx     # Settings tab
│   ├── components/
│   │   ├── Layout/
│   │   │   ├── Sidebar.tsx
│   │   │   ├── TopNav.tsx
│   │   │   └── Footer.tsx
│   │   ├── Cards/
│   │   │   ├── ComplianceCard.tsx
│   │   │   ├── CredentialCard.tsx
│   │   │   └── DeploymentCard.tsx
│   │   ├── Forms/
│   │   │   ├── RotateCredentialForm.tsx
│   │   │   └── TriggerDeploymentForm.tsx
│   │   └── Charts/
│   │       ├── ComplianceTrend.tsx
│   │       ├── DeploymentTimeline.tsx
│   │       └── CostAttribution.tsx
│   ├── hooks/
│   │   ├── useAuth.ts       # Auth context
│   │   ├── useCredentials.ts # Credential data
│   │   ├── useWebSocket.ts   # Real-time updates
│   │   └── useCompliance.ts  # Compliance checks
│   ├── context/
│   │   ├── AuthContext.tsx
│   │   ├── ThemeContext.tsx
│   │   └── NotificationContext.tsx
│   ├── services/
│   │   ├── api.ts           # HTTP client
│   │   ├── auth.ts          # OAuth 2.0 flow
│   │   └── websocket.ts     # WebSocket connection
│   ├── utils/
│   │   ├── formatters.ts    # Date, currency formatting
│   │   ├── validators.ts    # Form validation
│   │   └── constants.ts     # App-wide constants
│   └── styles/
│       └── globals.css      # Tailwind configuration
├── tests/
├── public/
│   ├── favicon.ico
│   └── nexusshield-logo.svg
├── Dockerfile
├── package.json
├── tsconfig.json
└── README.md
```

## Key Features

### 1. Real-Time Dashboard
- Compliance status (6/6 checks ✅)
- Credential health monitoring
- Deployment execution tracking
- Audit log viewer (immutable)

### 2. Credentials Tab
- OIDC Pool status + rotation controls
- AppRole management + secret rotation
- KMS keys + auto-rotation status
- GSM secrets + access logs

### 3. Deployments Tab
- Phase timeline (1-6 status visualization)
- Execution history + duration tracking
- Manual workflow dispatch buttons
- Rollback UI + confirmation dialogs

### 4. Compliance Tab
- 6-point verification dashboard
- Compliance score trend (7d, 30d, YTD)
- Violations timeline
- Regulatory mapping (SOC2, ISO27001, HIPAA)
- Export compliance reports (PDF, CSV)

### 5. Settings Tab
- Team member management
- API key generation
- Webhook configuration
- Billing + subscription management
- Dark mode + accessibility options

## Tech Stack

**Framework & UI:**
- React 18+ with Concurrent Features
- TypeScript 5+ for type safety
- React Router v6 for navigation
- TailwindCSS for styling
- shadcn/ui for component library

**State Management:**
- Redux Toolkit for global state
- React Query for server state
- Zustand for lightweight stores

**Real-Time Updates:**
- WebSocket (ws://) for 100ms updates
- Server-Sent Events (SSE) fallback

**Charts & Visualizations:**
- Recharts (line, bar, area charts)
- D3.js for complex visualizations

**Forms & Validation:**
- React Hook Form for performance
- Zod for schema validation

**Testing:**
- Vitest for unit tests
- React Testing Library for component tests
- Playwright for E2E tests
- Percy.io for visual regression

**Dev Tools:**
- Vite for ultra-fast HMR
- Storybook for component library
- ESLint + Prettier for code quality
- Husky for pre-commit hooks

## Environment Variables

```bash
# API Configuration
VITE_API_URL=http://localhost:3000/api
VITE_API_TIMEOUT=30000

# Auth (GitHub OAuth)
VITE_GITHUB_CLIENT_ID=xxx
VITE_GITHUB_REDIRECT_URI=http://localhost:3000/auth/callback

# WebSocket
VITE_WS_URL=ws://localhost:3000
VITE_WS_RECONNECT_INTERVAL=5000

# Monitoring
VITE_SENTRY_DSN=https://xxx@sentry.io/xxx
VITE_DATADOG_RUM_TOKEN=xxx

# Feature Flags
VITE_FEATURE_THREAT_DETECTION=false
VITE_FEATURE_WHITE_LABEL=false
```

## Running Locally

```bash
# Install dependencies
npm install

# Start dev server (with hot-reload)
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview

# Run tests
npm run test
npm run test:coverage

# Run E2E tests
npm run test:e2e

# Build Storybook
npm run storybook:build
```

## API Integration

All API calls go through the authenticated client:

```typescript
import { apiClient } from "@/services/api";

// Get credential status
const status = await apiClient.get("/api/v1/credentials/status");

// Trigger credential rotation
const result = await apiClient.post("/api/v1/credentials/rotate", {
  credentialId: "cred_approle_123"
});

// Real-time compliance check
const compliance = await apiClient.get("/api/v1/compliance/dashboard");
```

## Real-Time Updates (WebSocket)

```typescript
import { useWebSocket } from "@/hooks/useWebSocket";

function Dashboard() {
  const { data: compliance, isConnected } = useWebSocket(
    "compliance.dashboard"
  );
  
  return (
    <div>
      {isConnected && <span className="text-green-500">●</span>}
      {compliance && <ComplianceCard {...compliance} />}
    </div>
  );
}
```

## Deployment

**Automated via GitHub Actions:**
1. Push to main
2. \`portal-frontend-build.yml\` runs:
   - ESLint + Prettier checks
   - TypeScript type checking
   - Unit tests (90%+ coverage)
   - Build SPA
   - Accessibility audit
   - Lighthouse performance audit
   - Upload build artifacts
3. Staging deployed to CDN
4. Production deployment via manual approval (blue-green)

```bash
# Manual build & deploy
npm run build
gsutil -m rsync -r dist gs://nexusshield-portal-staging/
```

## Accessibility

- WCAG 2.1 AA compliance target
- Keyboard navigation support (Tab, Arrow keys)
- Screen reader support (ARIA labels)
- Dark mode for low-light environments
- Color contrast ratios >4.5:1

## Performance

- Lighthouse score target: 90+
- Core Web Vitals optimized
- Code splitting per route
- Image optimization + lazy loading
- Service Worker for offline support

## Browser Support

- Chrome/Edge: Latest 2 versions
- Firefox: Latest 2 versions
- Safari: Latest 2 versions
- Mobile: iOS 14+, Android 8+

## Support

For issues, questions, or feature requests:
- GitHub Issues: https://github.com/kushin77/self-hosted-runner/issues
- Slack: #nexusshield-frontend
- Email: frontend@nexusshield.cloud

---

*This is a production application. All PR changes require code review and pass CI/CD checks.*

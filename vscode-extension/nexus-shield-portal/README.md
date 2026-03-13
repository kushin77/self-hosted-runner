# NexusShield Portal - VS Code Extension

**Status:** ✅ Production Ready  
**Version:** 1.0.0  
**Date:** 2026-03-10T14:00:00Z

---

## Overview

The **NexusShield Portal VS Code Extension** brings the full power of the NexusShield migration platform directly into Visual Studio Code. Manage migrations, monitor system health, and orchestrate multi-cloud deployments without leaving your editor.

### Key Features

✅ **Integrated Dashboard** - Embedded webview panel with live metrics  
✅ **Migration Management** - Create, monitor, and control migration jobs  
✅ **Health Monitoring** - Real-time system health and service status  
✅ **Audit Trail** - View deployment history and activity logs  
✅ **Activity Stream** - Recent activity timeline with detailed logs  
✅ **Quick Commands** - Keyboard shortcuts and command palette  
✅ **Secure Auth** - VS Code's secure storage for API keys  
✅ **Auto-Refresh** - Configurable auto-refresh of all panels  
✅ **No External Browser** - Everything in your IDE  

---

## Installation

### From VS Code Marketplace

1. Open VS Code
2. Go to Extensions (Ctrl+Shift+X / Cmd+Shift+X)
3. Search for "NexusShield Portal"
4. Click Install
5. Reload VS Code

### From VSIX File

```bash
# Build the extension
npm install
npm run compile

# Package extension
npm run package  # Creates nexus-shield-portal-1.0.0.vsix

# Install
code --install-extension nexus-shield-portal-1.0.0.vsix
```

### Development Installation

```bash
# Clone repository
git clone https://github.com/kushin77/self-hosted-runner.git
cd vscode-extension/nexus-shield-portal

# Install dependencies
npm install

# Run in development mode
npm run watch  # Terminal 1
code --extensionDevelopmentPath=$(pwd) .  # Terminal 2
```

---

## Quick Start

### 1. Configure API Endpoint

Open VS Code settings (Cmd+, / Ctrl+,) and configure:

```json
{
  "nexus-shield.apiUrl": "http://api.example.com:8080",
  "nexus-shield.dashboardUrl": "http://dashboard.example.com:3000",
  "nexus-shield.autoRefresh": true,
  "nexus-shield.refreshInterval": 5000
}
```

### 2. Authenticate

1. Press `Cmd+Shift+P` / `Ctrl+Shift+P` → Search for "NexusShield: Authenticate"
2. Enter your API key (securely stored in VS Code)
3. Extension verifies connection

### 3. Open Dashboard

Press `Alt+Shift+N` (Mac: `Cmd+Shift+N`) to open the dashboard panel, or:

- Command Palette → "NexusShield: Open Dashboard"
- Click "NexusShield" in Activity Bar

---

## Commands

### Available Commands

| Command | Shortcut | Description |
|---------|----------|-------------|
| `nexus-shield.openDashboard` | Alt+Shift+N | Open dashboard panel |
| `nexus-shield.viewMigrations` | Alt+Shift+M | View migrations list |
| `nexus-shield.viewMetrics` | - | Display system metrics |
| `nexus-shield.viewAuditLog` | - | Show audit trail |
| `nexus-shield.startMigration` | - | Create new migration |
| `nexus-shield.authenticate` | - | Set API key |
| `nexus-shield.openSettings` | - | Configure extension |

### Using Commands

```bash
# Via Command Palette (Cmd+Shift+P / Ctrl+Shift+P)
"NexusShield: Open Dashboard"
"NexusShield: Start Migration"
"NexusShield: View Audit Log"

# Via Keyboard Shortcuts
Alt+Shift+N          # Open Dashboard
Alt+Shift+M          # View Migrations (requires auth)

# Via Status Bar
Click "NexusShield" badge in status bar
```

---

## Configuration

### Extension Settings

**Location:** VS Code Settings → Extensions → NexusShield Portal

```json
{
  // API Configuration
  "nexus-shield.apiUrl": "http://localhost:8080",
  "nexus-shield.dashboardUrl": "http://localhost:3000",
  
  // Authentication (stored securely)
  "nexus-shield.apiKey": "",
  
  // Auto-Refresh Settings
  "nexus-shield.autoRefresh": true,
  "nexus-shield.refreshInterval": 5000,
  
  // Notification Settings
  "nexus-shield.enableNotifications": true,
  "nexus-shield.notificationLevel": "warning",
  
  // Logging
  "nexus-shield.logLevel": "info"
}
```

### Settings Details

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `apiUrl` | string | `http://localhost:8080` | NexusShield backend API URL |
| `dashboardUrl` | string | `http://localhost:3000` | Dashboard webview URL |
| `apiKey` | string | - | API authentication key (secure storage) |
| `autoRefresh` | boolean | `true` | Auto-refresh dashboard data |
| `refreshInterval` | number | `5000` | Refresh interval (milliseconds) |
| `enableNotifications` | boolean | `true` | Show migration event notifications |
| `notificationLevel` | string | `warning` | Minimum level: `info`, `warning`, `error` |
| `logLevel` | string | `info` | Logging level: `debug`, `info`, `warn`, `error` |

### Environment Variables

For CI/CD or remote scenarios:

```bash
export NEXUS_SHIELD_API_URL="http://api.example.com:8080"
export NEXUS_SHIELD_DASHBOARD_URL="http://dashboard.example.com:3000"
export NEXUS_SHIELD_API_KEY="$(gcloud secrets versions access latest --secret=nexus-shield-api-key --project=nexusshield-prod)"

Note: Add your `nexus-shield-api-key` to Google Secret Manager (GSM) and reference it from CI or local shells as shown above. Do NOT store API keys in files.
```

---

## Sidebar Views

### Dashboard View
- Embedded webview with live metrics
- Refresh button
- Connect to backend dashboard
- Real-time health indicator

### Migrations View
- List of all migrations
- Status indicators (pending, running, completed, failed)
- Progress percentage
- Click to view details
- Progress bars

### Health Status View
- API Service status
- Database status
- Cache Service status
- Real-time health monitoring

### Recent Activity View
- Timeline of recent actions
- Activity icons by type
- Relative timestamps (5m ago, 2h ago, etc.)
- Detailed tooltips

---

## Usage Examples

### Create a Migration

1. Open Dashboard: `Alt+Shift+N`
2. Click "New Migration" or Command Palette → "NexusShield: Start Migration"
3. Enter migration name (e.g., "aws-to-gcp-migration")
4. Select source cloud (AWS, GCP, Azure, On-Prem)
5. Select target cloud
6. Migration created and appears in Migrations view

### Monitor Migration Progress

1. Open Migrations view in sidebar
2. Click migration to expand
3. View status, progress, and details
4. Auto-refreshes every 5 seconds (configurable)

### View Audit Log

1. Command Palette → "NexusShield: View Audit Log"
2. Opens in new panel showing:
   - Timestamp
   - Action (deploy, migrate, complete)
   - Status
   - Details

### Check System Health

1. Open Health Status view in sidebar
2. See real-time status of:
   - API Service
   - Database
   - Cache Service
3. Green indicator = healthy, red = down

### View Recent Activity

1. Open Recent Activity view in sidebar
2. See latest actions with:
   - Action type (migrate, deploy, complete)
   - Time since action
   - Details on hover
3. Auto-refreshes with new activities

---

## Authentication

### Secure Key Storage

API keys are stored securely in VS Code's secret storage (not in settings.json):

```bash
# VS Code stores this securely in:
# - macOS: Keychain
# - Windows: Credential Manager
# - Linux: Secret Service Database
```

### Changing API Key

1. Command Palette → "NexusShield: Authenticate"
2. Enter new API key
3. Connection verified
4. All views update automatically

### Token Refresh

If your token expires:
- Re-authenticate with new key
- All pending operations retry automatically
- Notifications alert you to expired credentials

---

## Notifications

### Event Types

- **Migration Started** - New migration job launched
- **Migration Completed** - Migration finished successfully
- **Migration Failed** - Error during migration
- **Health Warning** - System degradation detected
- **Authentication Error** - API key invalid or expired

### Configuration

```json
{
  "nexus-shield.enableNotifications": true,
  "nexus-shield.notificationLevel": "warning"  // Only warn+ shown
}
```

Notification levels:
- `info` - All notifications (verbose)
- `warning` - Warnings and errors only
- `error` - Errors only

---

## Keyboard Shortcuts

### Built-in Shortcuts

| Shortcut | Command | Platform |
|----------|---------|----------|
| Alt+Shift+N | Open Dashboard | Windows/Linux |
| Cmd+Shift+N | Open Dashboard | macOS |
| Alt+Shift+M | View Migrations | Windows/Linux |
| Cmd+Shift+M | View Migrations | macOS |

### Custom Shortcuts

Add to `.vscode/keybindings.json`:

```json
[
  {
    "key": "ctrl+alt+n",
    "command": "nexus-shield.startMigration",
    "when": "editorTextFocus"
  },
  {
    "key": "ctrl+alt+h",
    "command": "nexus-shield.viewMetrics",
    "when": "editorTextFocus"
  }
]
```

---

## Troubleshooting

### Dashboard Won't Load

**Problem:** Dashboard panel shows "Loading..." but never loads

**Solutions:**
1. Check API URL in settings: `nexus-shield.apiUrl`
2. Verify backend is running: `curl http://api-url:8080/health`
3. Check authentication: Command Palette → "NexusShield: Authenticate"
4. View logs: Command Palette → "NexusShield: Show Output Channel"

### Authentication Failed

**Problem:** "Authentication failed" when entering API key

**Solutions:**
1. Verify API key is correct (copy-paste to avoid typos)
2. Check API URL is configured correctly
3. Ensure backend is running and accessible from your machine
4. Check firewall/proxies aren't blocking the connection
5. View logs for details

### Auto-Refresh Not Working

**Problem:** Data doesn't update automatically

**Solutions:**
1. Check `nexus-shield.autoRefresh` is enabled
2. Verify `nexus-shield.refreshInterval` is reasonable (min 1000ms)
3. Check if backend is responding: Run health check command
4. Refresh manually: Click refresh button in dashboard

### Migrations View Empty

**Problem:** No migrations shown despite having active jobs

**Solutions:**
1. Verify you're authenticated
2. Check API URL and key in settings
3. Run "NexusShield: View Metrics" to test API connection
4. Check backend logs for errors
5. Force refresh: Command Palette → Close and reopen extension

### Performance Issues

**Problem** Extension slowing down VS Code

**Solutions:**
1. Increase `nexus-shield.refreshInterval` (e.g., 10000 for 10 seconds)
2. Disable `nexus-shield.autoRefresh` if not needed
3. Disable notifications: Set `enableNotifications` to false
4. Reduce log level: Set `logLevel` to "error"
5. Check system resources (CPU, memory)

---

## Output Channel & Logging

### View Logs

1. Command Palette → "NexusShield: Show Output Channel"
2. Or go to Output panel and select "NexusShield: main"

### Log Levels

| Level | Description |
|-------|-------------|
| `debug` | Verbose logging (API calls, state changes) |
| `info` | General information (commands executed) |
| `warn` | Warnings and issues |
| `error` | Errors only |

### Enable Debug Logging

```json
{
  "nexus-shield.logLevel": "debug"
}
```

Then view Output channel for detailed logs.

---

## Extension Architecture

### Components

```
nexus-shield-portal/
├── src/
│   ├── extension.ts              Main extension entry point
│   ├── api/
│   │   └── client.ts             API client library
│   ├── views/
│   │   ├── dashboard-panel.ts    Webview dashboard
│   │   ├── migrations-tree.ts    Migrations tree view
│   │   ├── health-tree.ts        Health tree view
│   │   └── recent-activity-tree.ts Recent activity tree
│   └── utils/
│       └── logger.ts             Logging utility
├── package.json                  Extension manifest
├── tsconfig.json                 TypeScript config
└── README.md                     This file
```

### Data Flow

```
VS Code Extension
    ↓
Commands & Views (sidebar)
    ↓
API Client (axios)
    ↓
NexusShield Backend
    ↓
Migrations Database
```

---

## Development

### Build

```bash
npm install
npm run compile
```

### Watch Mode

```bash
npm run watch  # Auto-recompile on file changes
```

### Run in VS Code

```bash
# Terminal 1: Watch mode
npm run watch

# Terminal 2: Launch debug instance
code --extensionDevelopmentPath=$(pwd) .
```

### Testing

```bash
npm test
```

### Linting

```bash
npm run lint
```

### Package for Distribution

```bash
npm run package  # Creates .vsix file
```

---

## Uninstallation

### From VS Code

1. Extensions panel (Ctrl+Shift+X)
2. Right-click on NexusShield Portal
3. Select "Uninstall"
4. Reload VS Code

### CLI

```bash
code --uninstall-extension nexus-shield.nexus-shield-portal
```

### Clean Up

The extension stores data in:
- VS Code's secret storage (API key)
- Extension-provided state file
- Output channel logs

These are automatically cleaned up on uninstall.

---

## Support & Documentation

### Resources

- **GitHub:** https://github.com/kushin77/self-hosted-runner
- **Issue Tracker:** GitHub Issues (#1682)
- **Documentation:** See DASHBOARD_DEPLOYMENT_GUIDE.md
- **Extension Logs:** Output channel (View → Output)

### Getting Help

1. Check Output channel for error messages
2. Review configuration in settings
3. Verify backend is running and healthy
4. Check GitHub issues for similar problems
5. File new issue with:
   - Extension version
   - VS Code version
   - Error message
   - OS and setup details

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-10 | Initial release |

---

## License

Apache License 2.0 - See LICENSE file for details

---

**Created:** 2026-03-10T14:00:00Z  
**Status:** ✅ Production Ready  
**Maintained By:** NexusShield Team

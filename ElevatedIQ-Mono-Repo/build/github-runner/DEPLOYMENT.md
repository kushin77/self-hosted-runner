# GitHub Actions Self-Hosted Runner Deployment

Deploy a centralized GitHub Actions runner in Docker on 192.168.168.42 for all your repos (ElevatedIQ, aetherfoge, etc).

## 🎯 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Docker Container on 192.168.168.42 (elevatediq-github-runner) │
│  └─ GitHub Actions Runner                                     │
│     └─ Listens for webhook triggers from GitHub               │
│        └─ Runs jobs from any repo in your account              │
└─────────────────────────────────────────────────────────────┘
         ⬇️
┌─────────────────────────────────────────────────────────────┐
│  Your Repos (ElevatedIQ, aetherfoge, other projects)       │
│  └─ .github/workflows/*.yml → runs-on: self-hosted          │
│     └─ Automatically routes to container runner              │
└─────────────────────────────────────────────────────────────┘
```

## 📋 Prerequisites

- Docker installed on 192.168.168.42
- GitHub personal access token (PAT) with repo + workflow scopes
- Administrator access to your personal GitHub account

## 🚀 Step 1: Generate GitHub Runner Token

1. Open https://github.com/kushin77/settings/runners/new
2. Select **Linux** platform
3. Copy the **RUNNER_TOKEN** (starts with `ghp_`)
   - Token is temporary (expires after 1 hour, so generate just before Step 4)

## 📦 Step 2: Build Docker Image

```bash
cd /home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner

# Build the self-hosted runner image
docker-compose build

# Verify image built
docker images | grep github-runner
```

## 🔧 Step 3: Start Runner Container

Option A: **One-line with token** (if token still valid):

```bash
cd /home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner

RUNNER_TOKEN=ghp_your_token_here docker-compose up -d

# Verify container is running
docker ps | grep github-runner
```

Option B: **Using .env file** (recommended):

```bash
# Create .env file with token
cat > .env << 'EOF'
RUNNER_TOKEN=ghp_your_token_here
EOF

# Start container
docker-compose up -d

# Verify
docker logs -f elevatediq-github-runner
```

Expected output:
```
✓ Configuration complete
✓ Marking as configured
🚀 Starting GitHub Actions listener...
```

## ✅ Step 4: Verify Runner is Online

```bash
# Check container status
docker ps | grep github-runner
# Should show: elevatediq-github-runner ... Up

# Check logs
docker logs elevatediq-github-runner
# Should show "Listening for Jobs"

# Verify in GitHub UI
# https://github.com/kushin77/settings/runners
# Should show: "Idle" (green status) 🟢
```

## 🎯 Step 5: Use Runner in Your Repos

### In any repo's `.github/workflows/*.yml`:

Update job definition to use self-hosted runner:

```yaml
jobs:
  test:
    runs-on: self-hosted  # ← Uses your container runner
    steps:
      - uses: actions/checkout@v4
      - run: python -m pytest
      - run: ruff check .
```

### Example: Full Workflow Using Self-Hosted Runner

```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: self-hosted  # 🚀 Runs in your Docker container!
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        run: python3 -m venv venv && source venv/bin/activate
      
      - name: Install dependencies
        run: |
          source venv/bin/activate
          pip install -r requirements.txt
      
      - name: Lint
        run: |
          source venv/bin/activate
          ruff check .
      
      - name: Run tests
        run: |
          source venv/bin/activate
          pytest
```

## 📊 Verify Runner is Being Used

1. Push to a repo or create a PR with `runs-on: self-hosted`
2. Go to **Actions** tab in that repo
3. Watch the workflow run
4. Should show workflow running on your machine (check `docker logs`)

```bash
# Real-time log of runner activity
docker logs -f elevatediq-github-runner
```

## 🛠️ Common Commands

### View logs
```bash
docker logs elevatediq-github-runner
docker logs -f elevatediq-github-runner  # Follow (tail -f)
```

### Stop runner
```bash
docker-compose down
```

### Restart runner
```bash
docker-compose restart
```

### Remove runner from GitHub
```bash
# Option 1: Via GitHub UI
# https://github.com/kushin77/settings/runners → Remove button

# Option 2: Container will auto-deregister on shutdown
docker-compose down
```

### Rebuild after Dockerfile changes
```bash
docker-compose build --no-cache
docker-compose up -d
```

### Check container resource usage
```bash
docker stats elevatediq-github-runner
```

## 🔐 Security Best Practices

- ✅ Token is only used during registration, not stored
- ✅ Container runs as unprivileged `runner` user
- ✅ Docker socket passed through securely (mounted read-write only)
- ✅ Logs are automatically rotated (max 10m per file, 3 files)
- ✅ Resource limits enforced (4 CPU, 8GB memory)

## 📈 Scaling: Multiple Runners

If you need parallel jobs, scale to multiple runners:

```yaml
# docker-compose.yml with multiple runners
version: "3.9"
services:
  runner-1:
    # ... (same config)
    container_name: elevatediq-github-runner-1
    environment:
      RUNNER_NAME: "elevatediq-runner-1"
    # ...
  
  runner-2:
    # ... (same config)
    container_name: elevatediq-github-runner-2
    environment:
      RUNNER_NAME: "elevatediq-runner-2"
    # ...
```

Then start both:
```bash
RUNNER_TOKEN=ghp_xxx docker-compose up -d
```

In workflows, use labels to target specific runners:
```yaml
runs-on: [ self-hosted, docker ]  # Runs on any self-hosted runner with both labels
```

## 🚨 Troubleshooting

### Container won't start
```bash
# Check logs
docker logs elevatediq-github-runner

# Verify token is valid
# https://github.com/kushin77/settings/tokens

# Rebuild image
docker-compose build --no-cache
```

### Runner shows "Offline" in GitHub UI
```bash
# Check container is running
docker ps | grep github-runner

# Check logs
docker logs elevatediq-github-runner

# Restart container
docker-compose restart
```

### Port conflicts (if you expose ports)
```bash
# Change port in docker-compose.yml
# ports:
#   - "8080:8080"  # Change left port to avoid conflicts
```

## 📚 Resources

- GitHub Runner Documentation: https://docs.github.com/en/actions/hosting-your-own-runners
- Self-Hosted Runner Limits: https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners
- GitHub Actions Security: https://docs.github.com/en/actions/security-guides

## ✨ Expected Workflow

1. **Push to any repo** → GitHub sends webhook
2. **Runner receives trigger** → Runs job in Docker container
3. **Job completes** → Results visible in GitHub Actions UI
4. **Zero GitHub Actions minutes consumed** ✅

---

**Status:** Ready to deploy. All ElevatedIQ and other repos can now use `runs-on: self-hosted`.

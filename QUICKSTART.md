# 🚀 QUICKSTART - 5 Minute Setup Guide

Get the full self-hosted runner development stack running in **under 5 minutes**.

---

## Prerequisites (30 seconds)

```bash
# Required:
- Docker Desktop (or Docker + Docker Compose)
- Git
- Make

# Optional (for using VS Code DevContainer):
- VS Code + Remote Containers extension
```

---

## Option 1: Docker Compose Stack (Recommended - 2 min)

Fastest way to get all services running locally.

```bash
# 1. Clone and enter repo
git clone https://github.com/kushin77/self-hosted-runner.git
cd self-hosted-runner

# 2. Start the full stack (3 min)
make dev-up

# 3. Verify everything works
make dev-verify

# 🎉 Done! Services are running at:
#   Portal UI:      http://localhost:3000
#   Provisioner:    http://localhost:8000
#   Vault UI:       http://localhost:8200/ui (token: dev-token-12345)
#   Prometheus:     http://localhost:9090
#   Grafana:        http://localhost:3001 (admin/admin)
```

**Useful commands:**

```bash
make dev-logs          # See what services are doing
make dev-shell SERVICE=vault  # Drop into container
make dev-down          # Stop everything (data preserved)
make dev-reset         # Clean slate (delete volumes)
```

---

## Option 2: VS Code DevContainer (3 min)

Isolated development environment with all tools pre-installed.

```bash
# 1. Open repo in VS Code
code .

# 2. Click the green "Dev Containers" button (bottom-left)
#    Select "Reopen in Container"

# 3. Wait for container to build (~2 min)

# 4. Inside container:
make dev-up            # Start local stack

# 5. Open http://localhost:3000 from host machine
```

**Why DevContainers?**
- ✅ No local dependencies needed (Node, Python, Terraform, etc.)
- ✅ Consistent environment (dev = CI = production)
- ✅ Automatic dependency installation
- ✅ Pre-configured VS Code extensions

---

## Option 3: Manual Setup (5 min)

For those who prefer native installation.

```bash
# 1. Install dependencies
make bootstrap

# 2. Start infrastructure services
docker-compose up -d vault redis postgres

# 3. Install Node dependencies per service
cd services/provisioner-worker && npm install
cd ../ai-oracle && npm install
cd ../../ && npm install  # Portal

# 4. Start applications (in separate terminals)
cd services/provisioner-worker && npm start
cd services/ai-oracle && npm start
cd ElevatedIQ-Mono-Repo/apps/portal && npm start

# Services now at:
#   http://localhost:3000 (Portal)
#   http://localhost:8000 (Provisioner)
```

---

##  🧪 Verify Services Are Healthy

```bash
# Quick health check
make dev-verify

# Or manually:
curl http://localhost:8200/v1/sys/health     # Vault
curl http://localhost:8000/health             # Provisioner
curl http://localhost:9090/-/healthy          # Prometheus
```

Expected responses: HTTP 200 with JSON data.

---

## 📝 Common Tasks

###  Running Tests

```bash
#Run all tests
make test

# Run specific service tests
cd services/provisioner-worker && npm test
```

### Checking Code Quality

```bash
# Full quality gate
make quality

# Auto-fix violations where possible
make quality-fix

# Run specific checks
make lint              # ESLint
make format            # Format with Prettier
```

### Viewing Logs

```bash
# All services
make dev-logs

# Specific service
make dev-logs-service SERVICE=provisioner-worker

# With filtering
docker-compose -f docker-compose.dev.yml logs provisioner-worker | grep -i error
```

### Stopping & Starting

```bash
# Pause (preserves data)
make dev-down

# Resume
make dev-up

# Full reset (⚠️ loses local data)
make dev-reset
```

---

## 🔐 Secret Management

Services use **Vault** for secrets (running in dev mode on `localhost:8200`).

```bash
# Access Vault UI
# URL:   http://localhost:8200/ui
# Token: dev-token-12345

# Set a secret (via CLI)
export VAULT_ADDR=http://localhost:8200
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
vault kv put secret/provisioner/key value=myvalue

# Services automatically read from Vault
# See: DEVELOPER_SECRETS_GUIDE.md
```

---

## 🚨 Troubleshooting

### "Port 3000 already in use"

```bash
# Find what's using it
lsof -i :3000

# Change port in .env
export PORT=3001
make dev-up
```

### "Docker permission denied"

```bash
# Add user to docker group (Linux)
sudo usermod -aG docker $USER
newgrp docker

# Or use sudo
sudo make dev-up
```

### "Out of memory / System slow"

```bash
# Reduce resource usage
docker-compose -f docker-compose.dev.yml down

# Give Docker more resources:
# Docker Desktop > Preferences > Resources
# Increase: CPUs, Memory, Disk Image Size

make dev-up
```

### "Services won't start"

```bash
# Check logs
make dev-logs

# Look for specific service
make dev-logs-service SERVICE=vault

# Restart that service
docker-compose -f docker-compose.dev.yml restart vault
```

---

## 📚 Next Steps

Once running, explore:

- **[CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md)** — Configure services
- **[AUTOMATION_RUNBOOK.md](AUTOMATION_RUNBOOK.md)** — Run automations
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — How to contribute
- **[DEVELOPER_SECRETS_GUIDE.md](DEVELOPER_SECRETS_GUIDE.md)** — Secret handling
- **[docs/README.md](docs/README.md)** — All documentation hub

---

## ⚡ Pro Tips

1. **Use `make dev-verify` regularly** — Catch issues early
2. **Read service logs** — `make dev-logs` shows everything
3. **Container shell is your friend** — `make dev-shell SERVICE=vault` 
4. **Git hooks are pre-installed** — Commits lint automatically
5. **Quality gate runs on PR** — Fix locally with `make quality-fix` before pushing

---

## 🤝 Need Help?

- **Documentation Hub** — [docs/README.md](docs/README.md)
- **Open an Issue** — [GitHub Issues](https://github.com/kushin77/self-hosted-runner/issues)
- **Check Troubleshooting** — See section above

---

## ✅ Success Checklist

After running `make dev-up`, verify:

- [ ] Portal loads at http://localhost:3000
- [ ] Vault UI accessible at http://localhost:8200/ui
- [ ] Provisioner API responds to curl (see [Verify](#-verify-services-are-healthy))
- [ ] Prometheus dashboards at http://localhost:9090
- [ ] All services show "healthy" in `make dev-verify`
- [ ] `make test` completes without errors
- [ ] `make quality` passes all checks

**You're ready to develop!** 🎉

---

*Last updated: 2026-03-08*  
*For questions, see [docs/README.md](docs/README.md)*

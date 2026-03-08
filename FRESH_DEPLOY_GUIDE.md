# 🚀 FRESH DEPLOY - NUKE & TEST 0-100 GUIDE

**Status**: Development Environment Reset Complete  
**Date**: March 8, 2026  
**Purpose**: Clean slate deployment testing

## Overview

This package contains all scripts and configuration needed to:
1. **Nuke** everything (Docker, state, cache, logs)
2. **Deploy** fresh from 0-100
3. **Test** all systems end-to-end
4. **Validate** complete system functionality

---

## 🎯 Quick Start

### Prerequisites
- Docker & docker-compose installed on target machine
- At least 10GB free disk space
- Bash shell

### One-Command Deploy

```bash
bash nuke_and_deploy.sh
```

This runs through 7 phases:
1. Stop all services
2. Clean artifacts & state
3. Terraform reset
4. Docker cleanup
5. Install dependencies
6. Build fresh containers
7. Health checks

**Estimated time**: 5-15 minutes

---

## 📋 Phase Breakdown

### Phase 1: Service Shutdown
```bash
# Stops all running containers
# Removes volumes
# Cleans dangling images
```

### Phase 2: Local Cleanup
Removes:
- ❌ Build artifacts (dist, build, .next)
- ❌ Cached files
- ❌ State files (.bootstrap-state.json, plan.txt)
- ❌ Log files
- ❌ Python caches (__pycache__)
- ❌ Terraform working directory

### Phase 3: Terraform Reset
```bash
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl
rm -f terraform/terraform.tfstate*
```

### Phase 4: Docker Image Cleanup
```bash
docker image prune -af
docker builder prune -af
```

### Phase 5: Fresh Dependencies
- **Node.js**: `npm install --prefer-offline`
- **Python**: `python3 -m venv .venv && pip install -r requirements.txt`

### Phase 6: Container Build & Start
```bash
docker-compose -f docker-compose.dev.yml build --no-cache
docker-compose -f docker-compose.dev.yml up -d
```

### Phase 7: Health Checks
Tests connectivity to all services

---

## 🧪 Testing Framework

After deployment, run the test suite:

```bash
bash test_deployment_0_to_100.sh
```

### Test Categories

#### 1. Docker Services (4 tests)
- ✅ Docker daemon accessible
- ✅ docker-compose installed
- ✅ Services running
- ✅ Container health

#### 2. Service Connectivity (5 tests)
- ✅ Vault HTTP API (port 8200)
- ✅ Redis (port 6379)
- ✅ PostgreSQL (port 5432)
- ✅ MinIO API (port 9000)
- ✅ MinIO Console (port 9001)

#### 3. Data Persistence (3 tests)
- ✅ PostgreSQL write/read
- ✅ Redis write/read
- ✅ Data consistency

#### 4. Application Setup (2 tests)
- ✅ Node dependencies
- ✅ Python virtual environment

#### 5. File System (6 tests)
- ✅ Key directories present
- ✅ No stale state files
- ✅ Terraform cleaned
- ✅ Build artifacts removed
- ✅ Cache cleaned
- ✅ Logs cleared

#### 6. Git Repository (2 tests)
- ✅ Repository initialized
- ✅ Branch status

#### 7. Security (2 tests)
- ✅ Secrets directory
- ✅ Secret rules configured

**Total**: 24 test cases

---

## 🔧 Manual Verification

After automatic tests pass, manually verify:

### Vault
```bash
# Get health status
curl http://localhost:8200/v1/sys/health

# Expected response:
# {"sealed":false,"standby":false,...}
```

### Redis
```bash
# Connect to interactive shell
redis-cli -h localhost -p 6379

# Try commands
127.0.0.1:6379> PING
PONG
127.0.0.1:6379> SET mykey "hello"
OK
127.0.0.1:6379> GET mykey
"hello"
```

### PostgreSQL
```bash
# Connect as runner user
PGPASSWORD=runner_password psql -h localhost -U runner_user -d runner_db

# Try a query
runner_db=> SELECT version();
runner_db=> \dt  # List tables
```

### MinIO
```bash
# Open in browser
# API: http://localhost:9000
# Console: http://localhost:9001
# User: minioadmin
# Password: minioadmin123

# Or use CLI
mc alias set local http://localhost:9000 minioadmin minioadmin123
mc ls local
```

---

## 📊 Service Endpoints Summary

| Service | Endpoint | Port | Type |
|---------|----------|------|------|
| **Vault** | http://localhost:8200 | 8200 | HTTP |
| **Redis** | localhost:6379 | 6379 | TCP |
| **PostgreSQL** | localhost:5432 | 5432 | TCP |
| **MinIO API** | http://localhost:9000 | 9000 | HTTP |
| **MinIO Console** | http://localhost:9001 | 9001 | HTTP |

### Credentials

**PostgreSQL**
```
User: runner_user
Password: runner_password
Database: runner_db
```

**MinIO**
```
User: minioadmin
Password: minioadmin123
```

**Vault**
```
Token: dev-token-12345
Mode: Dev mode (unsealed)
```

---

## ⚠️ Troubleshooting

### Services Not Starting

1. **Check logs**
   ```bash
   docker-compose logs -f vault
   docker-compose logs -f redis
   # etc.
   ```

2. **Verify ports are free**
   ```bash
   netstat -an | grep LISTEN | grep -E "8200|6379|5432|9000|9001"
   ```

3. **Rebuild containers**
   ```bash
   docker-compose down -v
   docker-compose build --no-cache
   docker-compose up -d
   ```

### Database Connection Issues

1. **Check PostgreSQL is running**
   ```bash
   docker-compose ps postgres
   ```

2. **Test connection**
   ```bash
   PGPASSWORD=runner_password pg_isready -h localhost -U runner_user
   ```

3. **Check logs**
   ```bash
   docker-compose logs postgres
   ```

### Memory Issues

If deployment fails with memory errors:
1. Increase Docker memory allocation
2. Run on a machine with at least 16GB RAM

---

## 🔄 Reset Without Full Deploy

If you just want to reset local state without Docker:

```bash
# Clear artifacts only
rm -rf build dist .next coverage
rm -f .bootstrap-state.json .ops-blocker-state.json
rm -rf terraform/.terraform

# Reset Terraform
cd terraform && terraform init && cd ..

# Clean Python cache
find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null
```

---

## 📝 What Gets Cleaned

### Before Deployment

```
✅ Cleaned:
├── build/
├── dist/
├── .next/
├── coverage/
├── node_modules/.cache/
├── __pycache__/
├── .bootstrap-state.json
├── .ops-blocker-state.json
├── plan.txt
├── terraform/.terraform/
├── terraform/.terraform.lock.hcl
├── terraform/terraform.tfstate*
├── logs/
└── *.log files
```

### After Deployment

```
✅ Fresh:
├── node_modules/ (rebuilt)
├── .venv/ (rebuilt)
├── Docker containers (rebuilt)
├── Volumes (fresh)
├── State (clean)
└── All services running
```

---

## 🎯 Testing Coverage

Tests cover:
- ✅ Infrastructure readiness
- ✅ Service connectivity
- ✅ Data persistence
- ✅ Application setup
- ✅ File system integrity
- ✅ Git repository status
- ✅ Security configuration

---

## 📞 Support

If issues occur:

1. **Check logs**
   ```bash
   docker-compose logs -f
   ```

2. **Run diagnostics**
   ```bash
   bash test_deployment_0_to_100.sh
   ```

3. **Full reset**
   ```bash
   bash nuke_and_deploy.sh
   ```

---

## 🎓 Next Steps After Fresh Deploy

1. ✅ Run full test suite
2. ✅ Verify all endpoints respond
3. ✅ Test data persistence (write/read cycles)
4. ✅ Run application tests
5. ✅ Execute end-to-end workflows
6. ✅ Validate all GitHub Actions
7. ✅ Confirm deployment automation

---

## 📅 Deployment Checklist

- [ ] Prerequisites installed
- [ ] Sufficient disk space (10GB+)
- [ ] ports 8200, 6379, 5432, 9000, 9001 available
- [ ] Run: `bash nuke_and_deploy.sh`
- [ ] Run: `bash test_deployment_0_to_100.sh`
- [ ] All tests passing
- [ ] Manual verification complete
- [ ] Ready for 0-100 testing

---

**Created**: March 8, 2026  
**Status**: Ready for Production Testing  
**Last Updated**: March 8, 2026

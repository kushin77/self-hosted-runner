Non-privileged validation report - 20260310T162622Z

Checking host configuration...
  WARN: DEPLOYMENT_HOST not set to 192.168.168.42 (current: <unset>)

Checking environment files...
  WARN: backend/.env missing; backend/.env.example present

Checking Node and npm...
  PASS: node v20.20.0
  PASS: npm 10.8.2

Checking required files...
  PASS: backend/Dockerfile exists
  PASS: backend/package.json exists
  PASS: backend/.env.example exists
  PASS: backend/README.md exists

Checking ports availability (local)...
  PASS: Port 3000 available or nc not present
  WARN: Port 5432 appears in use on localhost
  WARN: Port 6379 appears in use on localhost
  WARN: Port 8080 appears in use on localhost

Checking disk space (need 5GB+)...
  FAIL: Insufficient disk space: 1GB

NOTE: Docker and system-level checks are skipped by this non-privileged run. Host-admin should run full validation on the target host after system-level install.

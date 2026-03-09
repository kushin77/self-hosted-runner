# QUICKSTART: Developer Local Stack

Prereqs: Docker + Docker Compose

1. Clone repository

```bash
git clone https://github.com/kushin77/self-hosted-runner.git
cd self-hosted-runner
```

2. Start the local stack

```bash
make dev-up
```

3. View logs

```bash
make dev-logs
```

4. Tear down

```bash
make dev-down
```

5. Create a new service scaffold

```bash
make scaffold NAME=my-service
```

Notes:
- `dev-reset` removes volumes and rebuilds images
- `dev-verify` runs quick smoke checks

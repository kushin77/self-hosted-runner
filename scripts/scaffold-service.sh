#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1-}" ]; then
  echo "Usage: $0 <service-name>"
  exit 2
fi

NAME="$1"
DIR="services/${NAME}"

if [ -d "$DIR" ]; then
  echo "Service '$NAME' already exists at $DIR"
  exit 0
fi

mkdir -p "$DIR"
cat > "$DIR/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY . /app
CMD ["python", "app.py"]
EOF

cat > "$DIR/app.py" <<'EOF'
print('Hello from service: %s' % __import__('os').environ.get('SERVICE_NAME', '${NAME}'))
EOF

cat > "$DIR/README.md" <<EOF
# ${NAME}

Minimal scaffold for ${NAME} service.

Build locally:
```bash
docker build -t local/${NAME}:dev .
```
EOF

echo "Scaffolded service at $DIR"

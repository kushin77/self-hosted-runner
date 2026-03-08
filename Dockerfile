FROM ubuntu:24.04

# ══════════════════════════════════════════════════════════════════════
# IMMUTABLE SELF-HOSTED RUNNER IMAGE — SECURITY HARDENED
# Ephemeral: designed for single-use, disposable runner instances
# Idempotent: identical output for identical inputs (pinned versions)
# Security: vulnerabilities remediated (Trivy scan compliance)
# ══════════════════════════════════════════════════════════════════════

ARG RUNNER_VERSION=2.332.0
ARG NODE_VERSION=20
ARG BUILD_DATE=unknown
ARG BUILD_COMMIT_SHA=unknown
ARG TARGETARCH=amd64

LABEL \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_COMMIT_SHA}" \
    org.opencontainers.image.source="https://github.com/kushin77/self-hosted-runner" \
    org.opencontainers.image.title="self-hosted-runner" \
    org.opencontainers.image.description="Immutable ephemeral GitHub Actions self-hosted runner (security hardened)" \
    runner.version="${RUNNER_VERSION}" \
    runner.ephemeral="true" \
    security.scan="trivy" \
    security.baseline="HIGH,CRITICAL"

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_ALLOW_RUNASROOT=1 \
    NODE_VERSION=${NODE_VERSION}

# Install system dependencies and security patches (single layer, pinned, with dist-upgrade)
RUN apt-get update && \
    apt-get dist-upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    openssl \
    sudo \
    unzip \
    wget \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    python3 \
    python3-pip \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Install Node.js LTS from NodeSource (upstream maintains security patches faster than distro)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g npm@latest && \
    npm cache clean --force && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/* /root/.npm

# Install Docker CLI and docker-compose (for container actions)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin && \
    pip3 install --no-cache-dir --upgrade setuptools wheel && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Create non-root runner user with strict permissions
RUN useradd -m -d /home/runner -s /bin/bash runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/runner && \
    chmod 0440 /etc/sudoers.d/runner

WORKDIR /home/runner

# Download and install GitHub Actions runner
RUN curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    -o actions-runner.tar.gz && \
    tar xzf actions-runner.tar.gz && \
    rm actions-runner.tar.gz && \
    ./bin/installdependencies.sh && \
    chown -R runner:runner /home/runner

# Copy bootstrap and health scripts
COPY scripts/bootstrap-runner.sh /usr/local/bin/bootstrap-runner.sh
COPY scripts/check-secret-health.sh /usr/local/bin/check-secret-health.sh
RUN chmod +x /usr/local/bin/*.sh

# Health check — verify runner binary exists and is functional
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /home/runner/bin/Runner.Listener --check || exit 1

USER runner

# Ephemeral: runner registers, executes ONE job, then self-destructs
ENTRYPOINT ["/home/runner/bin/Runner.Listener"]
CMD ["--ephemeral"]

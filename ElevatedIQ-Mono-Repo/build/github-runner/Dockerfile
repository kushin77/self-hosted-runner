# GitHub Actions Self-Hosted Runner in Docker
# Runs on 192.168.168.42 as centralized runner for all repos
# Based on: https://github.com/myoung34/docker-github-actions-runner

FROM ubuntu:24.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    build-essential \
    libssl-dev \
    libffi-dev \
    libicu-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    docker.io \
    docker-compose \
    sudo \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Create runner user
RUN useradd -m -s /bin/bash runner && \
    usermod -aG docker runner && \
    usermod -aG sudo runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Download and extract GitHub Actions Runner
WORKDIR /runner

ARG RUNNER_VERSION=2.317.0
RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    rm -f actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    chown -R runner:runner /runner

# create venv to avoid PEP 668 restrictions, install tooling inside it
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir pytest ruff black mypy pip-tools

# copy entrypoint into image and make executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Switch to runner user
USER runner

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -f "Runner.Listener" || exit 1

# start via injected entrypoint
ENTRYPOINT ["/entrypoint.sh"]

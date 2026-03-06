#!/usr/bin/env bash
set -euo pipefail

# Provision a service account `svc-runner` and install the provided public key.
# Usage: provision-service-account.sh <public-key-file> [--username svc-runner]

PUBKEY_FILE="$1"
USERNAME="svc-runner"
shift || true

if [[ ! -f "$PUBKEY_FILE" ]]; then
  echo "Public key file not found: $PUBKEY_FILE"
  exit 2
fi

if ! id -u "$USERNAME" &>/dev/null; then
  echo "Creating user $USERNAME"
  sudo useradd -m -s /bin/bash "$USERNAME"
else
  echo "User $USERNAME already exists"
fi

USER_HOME="/home/$USERNAME"
sudo mkdir -p "$USER_HOME/.ssh"
sudo chown "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
sudo chmod 700 "$USER_HOME/.ssh"

sudo cp "$PUBKEY_FILE" "$USER_HOME/.ssh/authorized_keys"
sudo chown "$USERNAME:$USERNAME" "$USER_HOME/.ssh/authorized_keys"
sudo chmod 600 "$USER_HOME/.ssh/authorized_keys"

echo "Installed public key for $USERNAME"

# Add to docker group if docker group exists
if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker "$USERNAME"
  echo "Added $USERNAME to docker group"
fi

# Create limited sudoers file for the user to perform deploy operations without a password
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
sudo bash -c "cat > $SUDOERS_FILE" <<'EOF'
# Allow svc-runner limited sudo for deployment operations
svc-runner ALL=(ALL) NOPASSWD: /bin/systemctl, /usr/bin/podman, /usr/bin/docker, /bin/mv, /bin/rsync, /usr/bin/tar, /bin/ln, /usr/bin/kill, /usr/bin/chown
EOF
sudo chmod 440 "$SUDOERS_FILE"

echo "Provisioning complete for $USERNAME"
#!/usr/bin/env bash
set -euo pipefail

# Provision a service account on the remote host and install a public SSH key.
# Usage: provision-service-account.sh --host 192.168.168.42 --user akushnir --svc svc-runner --pubkey /path/to/pubkey --add-docker

HOST=192.168.168.42
ADMIN_USER=akushnir
SVC_USER=svc-runner
PUBKEY_FILE=""
ADD_DOCKER=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --user) ADMIN_USER="$2"; shift 2;;
    --svc) SVC_USER="$2"; shift 2;;
    --pubkey) PUBKEY_FILE="$2"; shift 2;;
    --add-docker) ADD_DOCKER=true; shift;;
    --help) echo "Usage: $0 --host H --user ADMIN --svc SVC --pubkey FILE [--add-docker]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [[ -z "$PUBKEY_FILE" || ! -f "$PUBKEY_FILE" ]]; then
  echo "Public key file required and must exist" >&2
  exit 2
fi

PUBKEY_CONTENT=$(cat "$PUBKEY_FILE")

echo "Provisioning service user '$SVC_USER' on $HOST as $ADMIN_USER"

ssh -o BatchMode=yes -o ConnectTimeout=10 "$ADMIN_USER@$HOST" bash <<-REMOTE
set -euo pipefail
sudo id -u $SVC_USER >/dev/null 2>&1 || sudo useradd -m -s /bin/bash $SVC_USER
sudo mkdir -p /home/$SVC_USER/.ssh
sudo chmod 700 /home/$SVC_USER/.ssh
sudo bash -c 'cat > /home/$SVC_USER/.ssh/authorized_keys' <<'KEY'
${PUBKEY_CONTENT}
KEY
sudo chmod 600 /home/$SVC_USER/.ssh/authorized_keys
sudo chown -R $SVC_USER:$SVC_USER /home/$SVC_USER/.ssh

# Add minimal sudoers for controlled operations
sudo bash -c 'cat > /etc/sudoers.d/$SVC_USER' <<'SUDO'
$SVC_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart provisioner-worker.service, /bin/systemctl stop actions-runner.service, /bin/systemctl start actions-runner.service, /bin/systemctl restart actions-runner.service, /home/$SVC_USER/runnercloud/scripts/automation/pmo/deploy-full-stack.sh
SUDO
sudo chmod 440 /etc/sudoers.d/$SVC_USER

if $ADD_DOCKER >/dev/null 2>&1; then
  sudo groupadd -f docker || true
  sudo usermod -aG docker $SVC_USER || true
fi

echo "Service user provisioned"
REMOTE

echo "Provisioning complete"
#!/usr/bin/env bash
set -euo pipefail

# Provision a service account on the target host and install a public SSH key.
# Usage: provision-service-account.sh --target HOST --user EXISTING_USER --pubkey PATH --svc SVCUSER

TARGET_HOST="192.168.168.42"
EXISTING_USER="akushnir"
PUBKEY_PATH="${PWD}/artifacts/keys/svc-runner.pub"
SVC_USER="svc-runner"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_HOST="$2"; shift 2;;
    --user) EXISTING_USER="$2"; shift 2;;
    --pubkey) PUBKEY_PATH="$2"; shift 2;;
    --svc) SVC_USER="$2"; shift 2;;
    --help) echo "Usage: $0 [--target HOST] [--user EXISTING_USER] [--pubkey PATH] [--svc SVC_USER]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [[ ! -f "$PUBKEY_PATH" ]]; then
  echo "Public key not found at $PUBKEY_PATH" >&2
  exit 3
fi

echo "Provisioning service account '$SVC_USER' on $TARGET_HOST using existing account $EXISTING_USER"

echo "Copying public key to target..."
scp "$PUBKEY_PATH" "$EXISTING_USER@$TARGET_HOST:/tmp/${SVC_USER}.pub"

echo "Running remote provisioning steps..."
ssh "$EXISTING_USER@$TARGET_HOST" sudo bash -eux -s "$SVC_USER" <<'REMOTE'
set -euo pipefail
SVC_USER="$1"
PUBTMP="/tmp/${SVC_USER}.pub"

# Create the service user if it doesn't exist
if ! id -u "${SVC_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo -U "${SVC_USER}" || true
fi

mkdir -p /home/${SVC_USER}/.ssh
cat "${PUBTMP}" > /home/${SVC_USER}/.ssh/authorized_keys
chown -R ${SVC_USER}:${SVC_USER} /home/${SVC_USER}/.ssh
chmod 700 /home/${SVC_USER}/.ssh
chmod 600 /home/${SVC_USER}/.ssh/authorized_keys

# Add to docker group if exists
if getent group docker >/dev/null 2>&1; then
  usermod -aG docker ${SVC_USER} || true
fi

# Create a sudoers file with limited NOPASSWD capabilities for service management
cat > /etc/sudoers.d/${SVC_USER} <<'SUDOEOF'
${SVC_USER} ALL=(ALL) NOPASSWD: /bin/systemctl *, /usr/bin/podman *, /bin/journalctl *
SUDOEOF
chmod 440 /etc/sudoers.d/${SVC_USER}

echo "Service account ${SVC_USER} provisioned"
rm -f "${PUBTMP}"
REMOTE

echo "Provisioning complete. Test SSH using the generated private key."

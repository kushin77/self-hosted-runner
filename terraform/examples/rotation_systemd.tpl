# Example cloud-init snippet to install auto-rotate script and enable systemd timer
cat > /usr/local/bin/auto_rotate_runners.sh <<'EOF'
${auto_rotate_script}
EOF
chmod +x /usr/local/bin/auto_rotate_runners.sh

cat > /etc/actions-runner/rotation.conf <<'EOF'
# Example entry:
# /opt/actions-runner,https://github.com/owner/repo,runner-name,secret/data/ci/self-hosted/runner-name
EOF

cat > /etc/systemd/system/auto-rotate-runners.service <<'EOF'
${rotate_service}
EOF
cat > /etc/systemd/system/auto-rotate-runners.timer <<'EOF'
${rotate_timer}
EOF

systemctl daemon-reload
systemctl enable --now auto-rotate-runners.timer

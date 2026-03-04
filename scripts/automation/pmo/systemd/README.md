Job Cancellation Handler systemd unit

Install and enable the service on target hosts:

```bash
# Copy the handler to the target location
sudo mkdir -p /opt/runner/handlers
sudo cp scripts/automation/pmo/job-cancellation-handler.sh /opt/runner/handlers/job-cancellation-handler.sh
sudo chmod +x /opt/runner/handlers/job-cancellation-handler.sh

# Install unit
sudo cp scripts/automation/pmo/systemd/job-cancellation-handler.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now job-cancellation-handler.service

# Check status
sudo systemctl status job-cancellation-handler.service
```

Customize `ExecStart` and `User` as required for your environment.

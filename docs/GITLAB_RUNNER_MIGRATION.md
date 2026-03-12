# Migrating a GitHub self-hosted runner to a GitLab Runner

This guide outlines safe steps to convert a machine currently running a GitHub self-hosted runner into a GitLab Runner without losing repository development work.

1) Preserve your repository and runner configuration
  - Ensure your repository changes are committed and pushed to your git remote.
  - Back up the runner folder you installed for GitHub (commonly the `actions-runner` directory):
    ```bash
    sudo systemctl stop actions.runner.* || true
    tar -czf ~/actions-runner-backup-$(date +%s).tgz /path/to/actions-runner || true
    ```

2) Remove/stop GitHub Actions runner service
  - If you registered the GitHub runner as a service, stop and disable it:
    ```bash
    sudo ./svc.sh stop || true
    sudo systemctl disable actions.runner.* || true
    ```

3) Install GitLab Runner
  - Follow GitLab's official docs for your OS. Example (Debian/Ubuntu):
    ```bash
    # Install GitLab Runner
    curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
    sudo chmod +x /usr/local/bin/gitlab-runner
    # Install as service
    sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash || true
    sudo gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
    sudo gitlab-runner start
    ```

4) Register the runner with your GitLab project/group
  - Obtain a registration token from Project > Settings > CI/CD (or Group level).
  - Register interactively:
    ```bash
    sudo gitlab-runner register --url "https://gitlab.com/" --registration-token "<TOKEN>"
    # Choose executor (shell, docker, docker+machine). For a self-hosted shell runner, choose 'shell'.
    ```

5) Recreate environment variables / secrets
  - In GitLab, add required CI/CD variables: `GITLAB_TOKEN` (API token with `api` scope) and any other secrets used by automation scripts.

6) Convert GitHub Actions workflows to `.gitlab-ci.yml`
  - The repo includes `.gitlab-ci.yml` and `scripts/gitlab-automation/*` to run the migrated jobs.
  - Review and tune the job images, runners, and schedules.

7) Validate
  - Run the pipeline in GitLab (manual pipeline or merge request). Use the validate job which runs `scripts/gitlab-automation/validate-automation-gitlab.sh`.

8) Clean up (optional)
  - After you confirm the GitLab runner is working, you may remove the old `actions-runner` backup.

If you want, I can perform the repository-side changes (create `.gitlab-ci.yml`, add the validator — already added) and prepare an MR. To finish host-level migration, I can provide exact host commands for your OS; tell me the runner host OS and whether you want `shell` or `docker` executor.

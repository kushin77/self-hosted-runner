# Resilience-Loader Composite Action

A GitHub Actions composite action that ensures resilience scripts are available
and provides a retry helper mechanism.

## Usage

Add this step to any workflow:

```yaml
- uses: ./.github/actions/resilience-loader
  name: Load resilience helpers
```

After this step, your workflow can use the `retry_command` helper:

```bash
source .github/scripts/resilience.sh
retry_command your-command-here
```

## What it does

- Ensures `.github/scripts/resilience.sh` exists
- Provides a `retry_command` bash function for retrying failed commands
- Sets up the environment for resilience-based operations

# CI/CD Runner Platform - Test Suite

Complete testing framework for validating the self-provisioning CI/CD runner platform across local integration, security, and cloud deployment scenarios.

## Test Suites

Note: To run cloud deployment tests non-interactively, create a `tests/cloud-creds.env` file
from `tests/cloud-creds.env.example` or run `./tests/prepare-creds.sh` (it will write
`tests/cloud-creds.env` from environment variables). The master runner will auto-load
`tests/cloud-creds.env` when present.


### 1. Integration Tests (`integration-test.sh`)

Validates the complete platform structure and configuration without requiring cloud resources.

**Coverage**:
- Bootstrap scripts (Linux/Windows verification, dependency installation)
- Pipeline executors (build, test, security, deploy)
- Security components (OPA policies, SBOM generation, artifact signing)
- Observability agents (Prometheus, Fluent Bit, OpenTelemetry)
- Self-update and healing daemons
- Lifecycle management (cleanup, destruction)
- Configuration files and documentation
- Directory structure integrity
- Code quality (bash best practices, YAML validation)

**Duration**: ~30 seconds
**Requirements**: None (local filesystem only)
**Exit codes**:
- 0: All tests passed
- 1: One or more tests failed

**Example usage**:
```bash
./tests/integration-test.sh
```

### 2. Security Tests (`security-test.sh`)

Validates security controls, isolation mechanisms, and cryptographic operations.

**Coverage**:
- Container isolation (dropped capabilities, read-only volumes, privilege escalation prevention)
- Network isolation (Docker networks, bridge controls)
- Artifact signing (Cosign configuration, keyless OIDC, SLSA attestations)
- SBOM generation (SPDX and CycloneDX formats)
- OPA policy enforcement (signing requirements, container policies, compliance)
- Secret handling (no hardcoded secrets, environment injection)
- Workspace security (secure wiping, ephemeral cleanup, environment wipe)
- Audit logging (syslog/journald integration)
- Malicious activity detection (observability integration)
- Vulnerability scanning (SBOM, image, SAST, secret scanning)

**Duration**: ~45 seconds
**Requirements**: None (local filesystem only)
**Exit codes**:
- 0: All security validations passed
- 1: Security validation failed

**Example usage**:
```bash
./tests/security-test.sh
```

### 3. Cloud Deployment Tests

#### EC2 Deployment Test (`cloud-test-ec2.sh`)

Launches actual EC2 instances, verifies bootstrap, and validates runner registration.

**Coverage**:
- AWS authentication and prerequisites
- Security group creation and firewall rules
- EC2 instance launch
- SSH connectivity
- Bootstrap script execution
- Systemd service validation
- Docker and dependency verification
- Configuration file presence
- Logging output

**Duration**: ~5-10 minutes
**Requirements**:
- AWS CLI configured
- AWS credentials with EC2, VPC, SecurityGroup, KeyPair permissions
- `AWS_REGION` environment variable set

**Environment variables**:
```bash
AWS_REGION=us-east-1              # AWS region
INSTANCE_TYPE=t3.medium            # EC2 instance type (default)
IMAGE_ID=ami-0885b1f6bd170450c    # Ubuntu 20.04 LTS AMI (US East 1)
GITHUB_TOKEN=ghr_xxxxx             # GitHub runner token
```

**Example usage**:
```bash
export AWS_REGION=us-east-1
export GITHUB_TOKEN="$(cat ~/.github/runner.token)"
./tests/cloud-test-ec2.sh
```

**Cost**: ~$0.05 per test (t3.medium for ~5 minutes)

#### GCP Deployment Test (`cloud-test-gcp.sh`)

Launches GCP Compute Engine instances, verifies bootstrap, and validates runner registration.

**Coverage**:
- GCP authentication and project validation
- Firewall rule creation
- Image selection and verification
- Compute Engine instance launch
- SSH connectivity via gcloud
- Bootstrap script execution
- Systemd service validation
- Docker and dependency verification
- Configuration file presence
- Logging output

**Duration**: ~5-10 minutes
**Requirements**:
- gcloud CLI installed and authenticated
- GCP project with Compute Engine API enabled
- `GCP_PROJECT` environment variable set
- Permissions: Compute instances, firewall, SSH

**Environment variables**:
```bash
GCP_PROJECT=my-project              # GCP project ID
GCP_ZONE=us-central1-a              # GCP zone
GCP_REGION=us-central1              # GCP region
MACHINE_TYPE=e2-medium              # GCP machine type (default)
IMAGE_FAMILY=ubuntu-2004-lts        # Image family
IMAGE_PROJECT=ubuntu-os-cloud       # Image project
```

**Example usage**:
```bash
export GCP_PROJECT="my-project"
export GITHUB_TOKEN="$(cat ~/.github/runner.token)"
./tests/cloud-test-gcp.sh
```

**Cost**: ~$0.04 per test (e2-medium for ~5 minutes)

#### Azure Deployment Test (`cloud-test-azure.sh`)

Launches Azure VMs, verifies bootstrap, and validates runner registration.

**Coverage**:
- Azure authentication and subscription validation
- Resource group creation
- Virtual network and subnet creation
- Network security group and firewall rules
- SSH key pair generation
- VM launch
- SSH connectivity
- Bootstrap script execution
- Systemd service validation
- Docker and dependency verification
- Configuration file presence
- Logging output

**Duration**: ~5-10 minutes
**Requirements**:
- Azure CLI installed and authenticated
- Azure subscription with VM creation permissions
- `AZURE_SUBSCRIPTION` environment variable set
- Permissions: VMs, Virtual Networks, Network Security Groups

**Environment variables**:
```bash
AZURE_SUBSCRIPTION=xxxxx-xxxxx      # Azure subscription ID
RESOURCE_GROUP=my-group             # Resource group name
LOCATION=eastus                     # Azure region
VM_NAME=runner-test-${RANDOM}       # VM name
IMAGE=UbuntuLTS                     # VM image
VM_SIZE=Standard_B2s                # VM size
```

**Example usage**:
```bash
export AZURE_SUBSCRIPTION="$(az account show --query id -o tsv)"
export GITHUB_TOKEN="$(cat ~/.github/runner.token)"
./tests/cloud-test-azure.sh
```

**Cost**: ~$0.03 per test (Standard_B2s for ~5 minutes)

### 4. Master Test Runner (`run-tests.sh`)

Orchestrates all test suites with flexible configuration.

**Usage**:
```bash
./tests/run-tests.sh [OPTIONS]
```

**Options**:
- `--only-integration`: Run integration tests only
- `--only-security`: Run security tests only
- `--with-ec2`: Include EC2 deployment tests
- `--with-gcp`: Include GCP deployment tests
- `--with-azure`: Include Azure deployment tests
- `--all`: Run all test suites (requires cloud credentials)
- `--help`: Show usage information

**Examples**:

```bash
# Run integration and security tests (no cloud resources)
./tests/run-tests.sh

# Run with EC2 deployment
AWS_REGION=us-east-1 ./tests/run-tests.sh --with-ec2

# Run all tests
AWS_REGION=us-east-1 \
  GCP_PROJECT=my-project \
  AZURE_SUBSCRIPTION=xxxxx \
  ./tests/run-tests.sh --all

# Run only security tests
./tests/run-tests.sh --only-security
```

## Running Tests in CI/CD

### GitHub Actions Workflow

```yaml
name: Platform Tests

on: [push, pull_request]

jobs:
  integration-security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run integration and security tests
        run: |
          chmod +x ./tests/run-tests.sh
          ./tests/run-tests.sh

  ec2-deployment:
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      
      - uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Run EC2 deployment test
        run: |
          chmod +x ./tests/cloud-test-ec2.sh
          GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }} \
            AWS_REGION=us-east-1 \
            ./tests/cloud-test-ec2.sh
```

## Test Results and Logging

All tests generate detailed logs:

| File | Purpose |
|------|---------|
| `tests/test-runner.log` | Master test runner output |
| `tests/integration-test.log` | Integration test details |
| `tests/security-test.log` | Security test details |
| `tests/cloud-test-ec2.log` | EC2 deployment test output |
| `tests/cloud-test-gcp.log` | GCP deployment test output |
| `tests/cloud-test-azure.log` | Azure deployment test output |
| `tests/test-summary.json` | JSON summary of test results |

View logs:
```bash
# Real-time output
tail -f tests/test-runner.log

# Final summary
cat tests/test-summary.json | jq .

# Search for failures
grep "✗" tests/*.log
```

## Troubleshooting

### Integration/Security Tests Fail

**Issue**: Tests fail with "file not found" or similar errors

**Solution**: Verify the platform directory structure:
```bash
ls -la cicd-runner-platform/
# Should show: bootstrap/ runner/ pipeline-executors/ security/ 
#              observability/ self-update/ scripts/ config/ docs/
```

### Cloud Tests Timeout on SSH

**Issue**: SSH connection times out during cloud tests

**Solution**:
1. Verify network connectivity to deployed instances
2. Check security group rules allow SSH (port 22)
3. Verify SSH key permissions: `chmod 600 /path/to/key.pem`
4. Increase timeout values in test scripts if needed

### Cloud Tests Fail on Bootstrap

**Issue**: Deployed instances don't have runner installed

**Solution**:
1. SSH into instance and check startup script: `tail -100 /var/log/cloud-init-output.log`
2. Verify bootstrap script is accessible
3. Check instance has internet access
4. Verify GitHub token is correctly injected

### AWS EC2 Test Fails with "InvalidGroup.NotFound"

**Issue**: Security group creation fails

**Solution**: 
1. Verify AWS credentials: `aws sts get-caller-identity`
2. Ensure IAM permissions include ec2:CreateSecurityGroup
3. Check VPC exists in specified region

### GCP Test Fails with "Project not found"

**Issue**: Test cannot access GCP project

**Solution**:
1. Verify GCP project ID: `gcloud config get-value project`
2. Ensure Compute Engine API is enabled: `gcloud services enable compute.googleapis.com`
3. Check gcloud authentication: `gcloud auth list`

### Azure Test Fails with subscription not found

**Issue**: Test cannot access Azure subscription

**Solution**:
1. Verify subscription: `az account show`
2. Set correct subscription: `az account set --subscription XXXXX`
3. Check Azure credentials: `az account list`

## Performance Benchmarks

| Test Suite | Duration | CPU | Memory | Disk I/O |
|-----------|----------|-----|--------|----------|
| Integration | ~30 sec | Low | 50 MB | Low |
| Security | ~45 sec | Low | 100 MB | Low |
| EC2 Deployment | ~5-10 min | Medium | 200 MB | Medium |
| GCP Deployment | ~5-10 min | Medium | 200 MB | Medium |
| Azure Deployment | ~5-10 min | Medium | 200 MB | Medium |
| All (no cloud) | ~75 sec | Low | 200 MB | Low |

## Support

For test failures or issues:

1. **Review logs**: Check the detailed log files for specific errors
2. **Run individually**: Run failing tests in isolation for debugging
3. **Increase verbosity**: Tests use `-u` bash flag for verbose output
4. **Check environment**: Verify all prerequisites are met
5. **Create issue**: Report persistent failures with:
   - Test suite name
   - Full log output
   - Environment details (OS, Cloud provider, etc.)

## Contributing

To add new tests:

1. Create new test script in `tests/` directory
2. Follow existing naming conventions: `test-{name}.sh`
3. Include proper logging and error handling
4. Add to master runner in `run-tests.sh`
5. Update this README with test coverage

## References

- [Integration Testing Best Practices](https://en.wikipedia.org/wiki/Integration_testing)
- [Security Testing Guidelines](https://owasp.org/www-project-testing-guide/)
- [AWS EC2 Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-best-practices.html)
- [GCP Compute Engine Best Practices](https://cloud.google.com/compute/docs/best-practices)
- [Azure VM Best Practices](https://docs.microsoft.com/azure/virtual-machines/windows/security-best-practices)

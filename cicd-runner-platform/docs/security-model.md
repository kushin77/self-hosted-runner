# Security Model for CI/CD Runners

## Threat Model

Self-hosted runners are a high-value attack target. Threats include:

1. **Malicious job execution**: Attacker forks repo, adds malicious steps
2. **Credential theft**: Secrets or tokens leaked from environment
3. **Supply chain attack**: Compromised dependency in job
4. **Network exfiltration**: Job exfiltrates data from host or network
5. **Payload persistence**: Attacker leaves backdoor for later exploitation
6. **Docker escape**: Attacker breaks out of container sandbox
7. **Host compromise**: Runner host becomes beachhead for lateral movement

## Defense Layers

### Layer 1: Job Isolation (Sandbox)

**Goal**: Prevent job from accessing host resources

**Mechanisms**:
- **Docker container**: Primary isolation layer
  - `--cap-drop=ALL`: Remove all Linux capabilities
  - `--security-opt="no-new-privileges:true"`: Prevent privilege escalation
  - `--tmpfs /tmp`: In-memory temp files, no persistence
  - `--user=runner:runner`: Non-root user (UID > 1000)
  - Volume mounts read-only except workspace

- **gVisor** (optional): Stronger sandbox for high-risk jobs
  - Userspace kernel: intercepts syscalls
  - Prevents kernel exploits
  - 2-5% performance overhead

- **Firecracker** (optional): Lightweight VM sandbox
  - Full OS isolation
  - Max 125 MB overhead per job
  - Best for untrusted code

**Network isolation**:
- Isolated Docker network per job
- No host network access
- Egress limited to approved domains (GitHub, registries)
- DNS only to GitHub's nameservers
- Port 22 (SSH) explicitly blocked

### Layer 2: Secret Management

**Goal**: Prevent secret leakage

**Mechanisms**:
- **At-rest**: Secrets stored encrypted in GitHub, never written to disk runner-side
- **In-transit**: GitHub Actions API uses TLS + certificate pinning
- **Runtime injection**: Secrets injected as environment variables only for job steps
- **Masking**: Stdout/stderr automatically masks secret values
- **Audit**: All secret access logged to GitHub Action audit log
- **Rotation**: Secrets rotated automatically by GitHub

**Best practices**:
- Short-lived tokens (GitHub OIDC preferred over PATs)
- Minimal secret scope (org-level, repo-level, or environment-level)
- Separate secrets for build vs. deploy
- Never log environment
- Never commit secrets to code

### Layer 3: Ephemeral Workspaces

**Goal**: Prevent cross-job data leakage

**Mechanisms**:
- Each job gets a temp workspace: `/tmp/job-<uuid>`
- Workspace destroyed after job completion (shred, not rm)
- Shared directories (e.g., Docker cache) are read-only or per-job-isolated
- No `.git` config persists across jobs

**Cleanup verification**:
- Verify workspace files removed
- Verify environment variables cleared
- Verify shell history cleared
- Verify Docker containers destroyed
- Verify temp files securely wiped

### Layer 4: Artifact Signing & Attestation

**Goal**: Ensure artifact integrity and provenance

**Mechanisms**:
- **Cosign**: Sign every artifact with asymmetric encryption
  - Public key in trusted repository
  - Signature verifiable offline
  - Private key in secure KMS (not on runner)

- **SBOM (SPDX)**: Document all dependencies
  - Machine-readable format
  - Vulnerability scanning integration
  - License compliance checking

- **Attestations (SLSA)**: Record build metadata
  - Build tool identity
  - Build environment
  - Inputs and outputs
  - Stored in transparency log (rekor)

**Verification**:
```bash
# Verify signature before deployment
cosign verify --key cosign.pub myapp:v1.0.0

# Check SBOM for vulnerabilities
syft myapp:v1.0.0 | grype
```

### Layer 5: Policy Enforcement (OPA)

**Goal**: Enforce security and compliance policies

**Policies** (see `security/policy/opa-policies.rego`):
- Container security: no privileged, read-only rootfs, resource limits
- Image security: signed, from approved registries, scanned
- Network: restricted ingress/egress
- RBAC: least-privilege role bindings
- Secrets: no hardcoded secrets, no logs of sensitive data
- Compliance: SOC2, PCI-DSS, HIPAA checks

**Enforcement**:
- Applied during build (pipeline gates)
- Applied at deployment (admission webhook)
- Applied to infrastructure (infrastructure-as-code validation)

**Failure handling**:
- Policy violation → job fails
- Violation reported with remediation steps
- Metrics tracked for compliance reports

### Layer 6: Observability & Forensics

**Goal**: Detect and investigate security incidents

**Logging**:
- All runner actions logged (job start/end, update, health checks)
- Job execution details: steps, environment (with secret masking), exit codes
- Security events: policy violations, auth failures, artifact scans
- Logs retained for 90 days (configurable)
- Immutable append logs for audit trail

**Monitoring**:
- Real-time alerts for:
  - Job failure spikes
  - Unusual resource usage
  - Network connections to unapproved hosts
  - Privilege escalation attempts
  - Policy violations

**Incident Response**:
- Trace job execution: commit, author, changes
- Link to artifact scan results
- Review logs and traces
- Collect artifacts for forensic analysis
- Automated remediation (quarantine malicious runner)

### Layer 7: Self-Healing

**Goal**: Detect and recover from compromise

**Health checks**:
- Process status (is runner alive?)
- Disk space (is workspace leaking?)
- Memory (is container escaping?)
- Network (can we reach GitHub?)
- Docker daemon (is container runtime alive?)
- Zombie processes (are there orphans?)

**Recovery**:
- If health score > 2: attempt restart
- If restart succeeds: return to normal
- If restart fails: quarantine and alert ops

**Quarantine**:
- Stop accepting new jobs
- Log diagnostic information
- Signal ops team (alert, email, Slack)
- Wait for manual investigation or auto-destroy

## Security Configuration

See `config/runner-env.yaml` and `config/feature-flags.yaml`:

```yaml
# Enable all security features
EPHEMERAL_WORKSPACE: true
REQUIRE_SIGNED_ARTIFACTS: true
ENABLE_SECRET_SCANNING: true
ENABLE_SAST: true
SANDBOX_TYPE: docker  # or gvisor for high-risk
ENABLE_READONLY_ROOTFS: true
ENABLE_AUTO_HEALING: true
SECURE_WORKSPACE_WIPE: true  # Use shred (slower)
```

## Compliance Mappings

### SOC2

- **CC6.2** (Logical access controls): OIDC federation + RBAC
- **CC7.2** (Monitoring): All actions logged to immutable audit trail
- **CC7.3** (Change management): OPA policies enforce change control

### PCI-DSS

- **Requirement 1** (Firewall): Network policies isolate runner traffic
- **Requirement 2** (Default credentials): Secrets rotated automatically
- **Requirement 3** (Data protection): Encryption at rest (Vault) and in transit (TLS)
- **Requirement 8** (Authentication): OIDC + MFA for admin actions
- **Requirement 10** (Audit logging): 90+ day retention

### HIPAA

- **Security Rule**: Encryption, RBAC, audit trails
- **Breach Notification**: Incident response automation
- **Minimum Necessary**: Secrets scoped per environment

## Testing & Validation

### Security Testing

Run these before production:

```bash
# 1. Policy validation
cd security/policy
conftest test -p opa-policies.rego deploy/*.yaml

# 2. Secret scanning
truffleHog filesystem .

# 3. Container security
trivy image --severity HIGH,CRITICAL runner:latest

# 4. SBOM generation and scanning
syft runner:latest | grype

# 5. Red team simulation (optional, high-risk)
# - Attempt to leak secrets from job
# - Attempt to write to workspace after job
# - Attempt to access host network from container
# - Attempt privilege escalation
```

### Verification Checklist

- [ ] Workspace cleaned after job (no leftover files)
- [ ] Secrets never appear in logs
- [ ] Artifacts signed and verifiable
- [ ] Network policies enforced
- [ ] Health checks running
- [ ] Audit log populated
- [ ] Metrics exported to Prometheus
- [ ] Quarantine logic tested

## Incident Response Playbook

### Secret Credential Leak

1. **Immediate**:
   - Revoke leaked credentials immediately
   - Quarantine affected runner
   - Stop all jobs on runner

2. **Investigation**:
   - Recover runner logs from last 24 hours
   - Trace which jobs had access to secret
   - Check for exfiltration in egress logs
   - Review git history for commits with secret

3. **Remediation**:
   - Rotate all credentials
   - Notify affected services (deployments, API keys)
   - Update enforcement to prevent pattern (scan SAST)
   - Destroy and rebuild runner

### Malicious Code Execution

1. **Immediate**:
   - Quarantine runner
   - Stop job execution
   - Prevent further network access

2. **Forensics**:
   - Collect container image and logs
   - Analyze job steps for payloads
   - Check Docker history for persistence attempts
   - Review policy violations leading to execution

3. **Containment**:
   - If lateral movement detected: quarantine entire runner pool
   - Review repos for forks with malicious changes
   - Scan all recent deployments for backdoors

4. **Recovery**:
   - Destroy compromised runner
   - Redeploy fresh runner with updated base image
   - Conduct post-mortem and update policies

## Related Documents

- `docs/architecture.md` — System architecture
- `docs/runner-lifecycle.md` — Runner state machine
- `config/runner-env.yaml` — Security configuration
- `security/policy/opa-policies.rego` — Policy enforcement rules


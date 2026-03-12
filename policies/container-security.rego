# OPA (Open Policy Agent) Policies for Elite MSP Operations

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CONTAINER IMAGE POLICY - Elite Security Standards
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

package container_policy

import future.keywords.contains
import future.keywords.if

# POLICY 1: No unapproved registries
deny[msg] {
    image := input.container_image
    not startswith(image, "registry.company.com/")
    not startswith(image, "docker.io/library/")
    msg := sprintf("Image %s from unauthorized registry", [image])
}

# POLICY 2: No latest tags in production
deny[msg] {
    image := input.container_image
    endswith(image, ":latest")
    input.environment == "production"
    msg := sprintf("Using :latest tag in production is forbidden: %s", [image])
}

# POLICY 3: All images must be signed
deny[msg] {
    not input.image_signature_verified
    input.environment == "production"
    msg := "Container image must be cryptographically signed"
}

# POLICY 4: Vulnerability severity limits
deny[msg] {
    vuln := input.vulnerabilities[_]
    vuln.severity == "CRITICAL"
    msg := sprintf("CRITICAL vulnerability found: %s (CVE-%s)", [vuln.package, vuln.cve])
}

deny[msg] {
    count(input.vulnerabilities[_]) > 5
    input.environment == "production"
    msg := sprintf("Too many vulnerabilities (%d) for production", [count(input.vulnerabilities)])
}

# POLICY 5: Image must have SLA guarantees
deny[msg] {
    not input.image_sla_tier
    input.environment == "production"
    msg := "Production image must have SLA tier defined"
}

# POLICY 6: No insecure registries
deny[msg] {
    registry := input.container_registry
    not registry.tls_enabled
    msg := sprintf("Registry %s must use TLS", [registry.url])
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DEPLOYMENT POLICY - Compliance & Safety
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

package deployment_policy

# POLICY 1: Blue-green or canary required for production
deny[msg] {
    input.environment == "production"
    input.deployment_strategy not in ["blue-green", "canary", "rolling"]
    msg := "Production deployments must use blue-green, canary, or rolling strategy"
}

# POLICY 2: Minimum replicas for HA
deny[msg] {
    input.replicas < 3
    input.environment == "production"
    msg := "Production deployments must have minimum 3 replicas for HA"
}

# POLICY 3: Resource limits must be set
deny[msg] {
    not input.container.resources.limits.cpu
    msg := "Container must have CPU limit defined"
}

deny[msg] {
    not input.container.resources.limits.memory
    msg := "Container must have memory limit defined"
}

# POLICY 4: Health checks required
deny[msg] {
    not input.container.livenessProbe
    input.environment == "production"
    msg := "Production containers must have liveness probe"
}

deny[msg] {
    not input.container.readinessProbe
    input.environment == "production"
    msg := "Production containers must have readiness probe"
}

# POLICY 5: No privileged containers
deny[msg] {
    input.container.securityContext.privileged == true
    msg := "Privileged containers are not allowed"
}

# POLICY 6: No root user
deny[msg] {
    input.container.securityContext.runAsUser == 0
    msg := "Containers must not run as root (UID 0)"
}

# POLICY 7: Immutable root filesystem
deny[msg] {
    input.container.securityContext.readOnlyRootFilesystem != true
    input.environment == "production"
    msg := "Production containers must have immutable root filesystem"
}

# POLICY 8: Network policies required
deny[msg] {
    not input.network_policy_enabled
    input.environment == "production"
    msg := "Production deployments must have network policies"
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RBAC POLICY - Access Control
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

package rbac_policy

# POLICY 1: Only approved roles can access production
approved_roles := {"sre", "platform-engineer", "devops", "release-manager"}

deny[msg] {
    input.environment == "production"
    not input.requester_role in approved_roles
    msg := sprintf("Role %s not authorized for production access", [input.requester_role])
}

# POLICY 2: Separation of duties
deny[msg] {
    input.action == "approve_deployment"
    input.previous_reviewer == input.current_approver
    msg := "Same person cannot review and approve (segregation of duties)"
}

# POLICY 3: MFA required for production
deny[msg] {
    input.environment == "production"
    not input.mfa_verified
    msg := "MFA is required for production access"
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DATA POLICY - Data Protection & Privacy
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

package data_policy

# POLICY 1: No plaintext secrets in artifacts
deny[msg] {
    artifact := input.artifacts[_]
    secret_pattern := ["password", "api_key", "token", "secret", "credential"]
    contains(artifact.content, secret_pattern[_])
    msg := sprintf("Artifact %s contains plaintext secrets", [artifact.name])
}

# POLICY 2: PII must be encrypted at rest
deny[msg] {
    input.contains_pii == true
    not input.encryption_algorithm
    msg := "PII data must be encrypted at rest"
}

# POLICY 3: Data retention limits
deny[msg] {
    input.data_retention_days > 90
    input.data_classification == "confidential"
    msg := "Confidential data must not be retained beyond 90 days"
}

# POLICY 4: Backup encryption required
deny[msg] {
    not input.backup_encryption_enabled
    msg := "Backups must be encrypted"
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# COMPLIANCE POLICY - Standards & Regulations
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

package compliance_policy

# POLICY 1: CIS Kubernetes Benchmarks
deny[msg] {
    input.container.securityContext.allowPrivilegeEscalation == true
    msg := "CIS 5.2.5: Containers must not allow privilege escalation"
}

# POLICY 2: PCI-DSS: Audit logging
deny[msg] {
    not input.audit_logging_enabled
    input.handles_payment_data == true
    msg := "PCI-DSS: Payment data handling requires audit logging"
}

# POLICY 3: HIPAA: Data encryption
deny[msg] {
    not input.encryption_algorithm
    input.handles_pii == true
    msg := "HIPAA: PII must be encrypted"
}

# POLICY 4: SOC2: Change management
deny[msg] {
    not input.change_ticket_id
    input.is_production_change == true
    msg := "SOC2: Production changes require change management ticket"
}

# POLICY 5: ISO27001: Risk assessment
deny[msg] {
    not input.risk_assessment_completed
    input.is_high_risk == true
    msg := "ISO27001: High-risk changes require risk assessment"
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# COST POLICY - Budget Control
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

package cost_policy

# POLICY 1: Limit resource requests
deny[msg] {
    cpu := tonumber(trim(input.cpu_request, "m"))
    cpu > 4000
    msg := sprintf("CPU request %dm exceeds limit of 4000m", [cpu])
}

deny[msg] {
    memory := tonumber(trim(input.memory_request, "Gi"))
    memory > 16
    msg := sprintf("Memory request %dGi exceeds limit of 16Gi", [memory])
}

# POLICY 2: Restrict expensive instance types
restrict_instance_types := ["cpu-optimized", "memory-optimized", "gpu"]

deny[msg] {
    input.instance_type in restrict_instance_types
    input.approval_level != "director"
    msg := sprintf("Instance type %s requires director-level approval", [input.instance_type])
}

# POLICY 3: Budget tracking
deny[msg] {
    input.estimated_monthly_cost > input.budget_limit
    input.budget_limit > 0
    msg := sprintf("Estimated cost $%f exceeds budget $%f", [input.estimated_monthly_cost, input.budget_limit])
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AUDIT & REPORTING
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

package audit_policy

# All policy violations are automatically logged
violation_log[entry] {
    entry := {
        "timestamp": now,
        "policy": "audit_policy",
        "severity": "HIGH",
        "action": "automatic_remediation",
        "status": "denied"
    }
}

# OPA/Rego policies for CI/CD pipeline enforcement
# These policies validate build artifacts, deployments, and runtime parameters

package cicd_policy

# Artifact signing enforcement
deny_unsigned_artifacts[msg] {
  input.artifact.signed == false
  msg := "Artifacts must be signed with cosign"
}

# SBOM requirement
deny_missing_sbom[msg] {
  not input.artifact.sbom
  msg := "Artifacts must include SBOM (SPDX/CycloneDX)"
}

# Container security baseline
deny_insecure_container[msg] {
  input.container.privileged == true
  msg := "Containers must not run as privileged"
}

deny_missing_resource_limits[msg] {
  not input.container.resources.limits
  msg := "Containers must define resource limits (CPU, memory)"
}

deny_root_filesystem[msg] {
  input.container.securityContext.readOnlyRootFilesystem == false
  msg := "Root filesystem must be read-only"
}

# Network policies
deny_unrestricted_network[msg] {
  input.pod.networkPolicy.ingress[_].from[_].podSelector.matchLabels == {}
  msg := "Network policies must restrict ingress"
}

# Image registry validation
deny_unregistered_image[msg] {
  not regex.match("^(gcr.io|registry.example.com)/", input.image)
  msg := "Images must come from approved registries"
}

# RBAC enforcement
deny_cluster_admin_role[msg] {
  input.rbac.roleType == "cluster-admin"
  msg := "cluster-admin role bindings require explicit approval"
}

# Secret scanning
deny_hardcoded_secrets[msg] {
  regex.match(".*(password|secret|token|key).*=", input.source.code)
  msg := "Hardcoded secrets detected in source code"
}

# Version pinning
deny_floating_tags[msg] {
  regex.match("(latest|main|develop)$", input.image.tag)
  msg := "Image tags must be pinned to specific versions"
}

# Audit logging
require_audit_log[msg] {
  not input.cluster.auditLog.enabled
  msg := "Cluster audit logging must be enabled"
}

# Compliance: SOC2, PCI-DSS, HIPAA
compliance_soc2[msg] {
  input.encryption.atRest == true
  input.encryption.inTransit == true
  input.audit.retention >= 90
  msg := "SOC2 compliance check passed"
}

compliance_pci[msg] {
  input.network.tls.minVersion >= "1.2"
  input.rbac.mfa == true
  input.logging.centralizedMonitoring == true
  msg := "PCI-DSS compliance check passed"
}

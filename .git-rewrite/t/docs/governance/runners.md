# GitHub Actions Runners: Governance & Policy

This document outlines governance policies for self-hosted GitHub Actions runners in the ElevatedIQ platform.

## Overview

Self-hosted runners provide compute resources for GitHub Actions workflows with full customization and cost control. This document establishes policies for:

- Runner provisioning and lifecycle management
- Security and compliance requirements
- Resource allocation and optimization
- Monitoring and incident response

## Runner Tiers

### Standard Tier (ubuntu-latest)
- **Specs**: 2 vCPU, 7GB RAM
- **Use Case**: Unit tests, linting, documentation builds
- **Scaling**: 1-10 instances per environment

### High-Memory Tier  
- **Specs**: 4 vCPU, 32GB+ RAM
- **Use Case**: Docker builds, integration tests, end-to-end testing
- **Scaling**: 1-5 instances per environment

## Provisioning

All runners are provisioned via Terraform IaC with:

- Automated lifecycle management
- VPC isolation and security groups
- IAM role-based access control
- Ephemeral storage (auto-wiped)
- Monitoring and health checks

Documentation: [RUNNER_INFRASTRUCTURE_DEPLOYMENT.md](../management/RUNNER_INFRASTRUCTURE_DEPLOYMENT.md)

## Security Requirements

### 1. Zero-Trust Network Access
- Outbound HTTPS only (GitHub API)
- No inbound SSH access (managed via Terraform)
- Network policies enforced at security group level

### 2. Credential Management
- No hardcoded tokens or secrets  
- GitHub app-based authentication
- Secrets managed via GitHub Secrets, Vault, or AWS Secrets Manager
- Token rotation enforced (24-hour max lifetime)

### 3. Audit Logging
- All runner actions logged to CloudWatch
- Terraform changes tracked in git
- Access logs retained for 30+ days

## Compliance

- CIS Benchmarks for EC2 instances
- Encrypted data at rest (EBS volumes)
- Encrypted data in transit (HTTPS APIs)
- Regular security patching (automatic updates)

## References

See [RUNNER_HEALTH_MONITORING_SYSTEM.md](../management/RUNNER_HEALTH_MONITORING_SYSTEM.md) for operationalization.

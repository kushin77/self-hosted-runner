# Phase P3 Compliance & Air-Gapped BYOC (Issue #16)

This document outlines the design and implementation plan for air-gapped BYOC
control plane and compliance requirements (SOC 2 Type II / HIPAA / FedRAMP).

## Goals

- **Air-gap architecture**: control plane operates with inbound-only connections
  from customer VPC, no outbound egress permitted.
- **Gatekeeper pattern**: single ingress point with strict policy, no DNS egress.
- **Compliance**: achieve SOC 2 Type II, HIPAA, FedRAMP ready state.

## Components

1. **Gatekeeper Proxy**: Nginx container running in customer VPC receives
   runner heartbeats and job telemetry over TLS. No outbound rules allowed.
2. **Data diodes**: physically or logically enforce one-way data from runners
   to control plane. Use S3 presigned URLs with restricted PUT-only policies.
3. **Kubernetes**: private cluster with private endpoint (no internet access).
4. **Runner software**: compiled to static binary, shipped via air-gapped channel
   (signed tarball on USB/CD-ROM).
5. **Documentation & Audit**: runbook describing procedures for air-gapped
   upgrades, incident response, and evidence collection for auditors.

## Implementation Notes

- Add `--no-egress` flag to BYOC Terraform module.
- Integrate `iptables` rules into runner_setup.sh to drop all outbound packets.
- Provide a `scripts/automation/pmo/airgap-verify.sh` that scans nodes for
  unauthorized connections and generates compliance report.

## Next Steps

- Prototype air-gapped deployment in lab environment.
- Engage third-party auditor early (Week 8).
- Develop compliance dashboard with evidence logs, policy attestations.


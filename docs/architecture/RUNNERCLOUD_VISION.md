# RunnerCloud: Product Vision & Strategy

**Date Approved**: March 4, 2026  
**Status**: Approved and In-Progress  
**Document Version**: 1.0

## Executive Summary

RunnerCloud is a GitHub Actions runner orchestration platform that owns the middle ground between SaaS simplicity and self-hosted control. We compete against Blacksmith, Depot, WarpBuild, GitHub-hosted, and Buildkite by delivering:

- **Instant Deploy**: 5 minutes from signup to live runners (all modes)
- **Three Deployment Modes**: Managed SaaS, BYOC (your VPC), On-Prem (bare metal)
- **Windows Moat**: First production-grade autoscaling Windows runners (competitors have zero)
- **Compliance Advantage**: SOC 2, HIPAA, FedRAMP-ready BYOC (SaaS runners cannot compete here)
- **Cost Transparency**: Public TCO calculator proving 50–70% savings vs. GitHub-hosted at scale

## The Three Deployment Modes

**Mode 1: Managed** - Runners in RunnerCloud's multi-tenant fleet (AWS + GCP), per-second billing, 2–4x faster than GitHub-hosted  
**Mode 2: BYOC** - Deploy ARC + Karpenter into customer's AWS/GCP/Azure cluster via Terraform, $199/mo control plane + customer's cloud bill  
**Mode 3: On-Prem** - Single systemd binary on any Linux/Windows host, no Kubernetes required, target: game studios + universities

## Competitive Advantages

- ✅ Windows Server 2025 native autoscaling (competitors have zero)
- ✅ Compliance-first BYOC (SOC 2, HIPAA, FedRAMP out of box)
- ✅ AI Failure Oracle (LLM-powered root cause analysis)
- ✅ LiveMirror Cache (4–40x faster builds via persistent NVMe cache)
- ✅ TCO Calculator (prove 50–70% cost savings at scale)

To view full product spec, architecture, pricing, GTM, and risk details, see https://github.com/kushin77/self-hosted-runner/blob/main/ROADMAP.md

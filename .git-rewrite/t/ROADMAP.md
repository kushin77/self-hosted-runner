# RunnerCloud: 12-Week Delivery Roadmap

**Status**: Approved & In-Progress  
**Start Date**: March 4, 2026  
**Phases**: P2 (SaaS Launch) + P3 (Enterprise) + GTM

## Phase P2: SaaS Launch (Weeks 1–7)

### Week 1–3: P2.1 – Managed Mode (Linux x64 + ARM64)
**GitHub Issue**: #8 | **Team**: Platform + Infra (3–4 FTE)

Multi-tenant runner pool (AWS EC2 + GCP), GitHub App OAuth, per-second billing, LiveMirror cache infrastructure, Performance benchmarks (cold start < 15s, warm start < 5s).

**Success Criteria**: First runner within 30s of GitHub App auth, 3–4x faster than GitHub-hosted, 99.5% uptime.

---

### Week 4–5: P2.2 – LiveMirror Persistent Dependency Cache
**GitHub Issue**: #9 | **Team**: Platform + Data (2–3 FTE)

NVMe-backed cache (npm, pip, Maven, Docker), hash-based invalidation, cache warming from main branch, overlay filesystem per-job isolation.

**Success Criteria**: npm install < 500ms (cached), pip < 300ms, Docker 40–50% faster, 85%+ cache hit rate.

---

### Week 6–7: P2.3 – AI Failure Oracle
**GitHub Issue**: #10 | **Team**: Data Science + Platform (2–3 FTE)

LLM-powered root cause analysis (Claude API), log streaming, GitHub comment posting, confidence thresholding (≥80%).

**Success Criteria**: < 20% false positives, > 90% fix suggestion correctness, < 30s end-to-end latency, < $0.01 per failure.

---

## Phase P3: Enterprise Features (Weeks 8–12+)

### Week 8–9: P3.1 – BYOC Mode (ARC + Karpenter)
**GitHub Issue**: #11 | **Team**: Platform + Cloud (3–4 FTE)

Deploy ARC + Karpenter into customer VPC via Terraform, RunnerCloud control plane manages scaling, cost attribution dashboard, OIDC-based credentials.

**Success Criteria**: Terraform deployment < 10min, cost overhead < 2%, scaling < 60s, SOC 2 attestation.

---

### Week 10–11: P3.2 – Windows Server 2025 Support
**GitHub Issue**: #12 | **Team**: Platform (dedicated Windows ops, 3–4 FTE)

Windows AMI with .NET 8/9, Visual Studio Build Tools, Unity Editor, Karpenter Windows nodes, Hyper-V snapshot scaling.

**Success Criteria**: .NET builds 30–40% faster than GitHub-hosted, cold start < 30s, 99.5% uptime, zero job loss.

---

### Week 12+: P3.3 – On-Prem Bare Metal Mode
**GitHub Issue**: #13 | **Team**: Platform (2 FTE)

Single systemd binary (Go), GitHub Scale Set SDK integration, snapshot-based auto-scaling (Hyper-V, KVM, ESXi).

**Success Criteria**: Download binary + systemctl start, < 60s scaling, 1,000+ runners per control plane, 99.5% uptime.

---

### Week 12+: P3.5 – Native Observability (OTEL Exporters) ✅
**GitHub Issue**: #15 | **Team**: Platform + Observability (2 FTE)

Native exporters for Datadog, Splunk, Prometheus, pre-built dashboards.  (baseline
Prometheus metrics for managed-auth and vault-shim now merged; next steps extend
OTEL and dashboards).

**Success Criteria**: < 2s dashboard load, < 60s data freshness, < 5% export cost overhead.

---

### Week 12+: P3.6 – Compliance & Air-Gapped BYOC
**GitHub Issue**: #16 | **Team**: Platform + Security + Compliance (3 FTE)

Air-gapped control plane, gatekeeper inbound-only pattern, no-egress iptables rules, SOC 2 Type II / HIPAA / FedRAMP ready.

**Success Criteria**: FedRAMP-deployable, zero security vulns (pen test), SOC 2 attested, customer data residency.

---

## Parallel: Go-to-Market (Weeks 1–12)

### Week 1–2: P3.4 – Public TCO Calculator
**GitHub Issue**: #14 | **Team**: Product + Marketing (2 FTE)

No-signup cost comparison (RunnerCloud vs. GitHub/Blacksmith/Depot/Buildkite).

**Success Metrics**: #1 Google ranking, 10%+ conversion rate, 2k+ monthly visitors.

### Week 2–4: GTM Wedge #1 – Windows Refugee
**GitHub Issue**: #17 | **Target**: Game studios, .NET enterprises

**Message**: "Autoscaling Windows runners for $0.002/min"  
**Deliverables**: Blog post, 2 case studies, Reddit/Twitter ads, direct outreach  
**Metrics**: 5k+ traffic, 20+ SQLs, 4+ converts

### Week 5–7: GTM Wedge #2 – Blacksmith Upgrade
**Target**: Blacksmith users hitting compliance reviews

**Message**: "Blacksmith for speed. RunnerCloud for compliance."  
**Deliverables**: Migration guide, comparison table, compliance content, 30-day free trial  
**Metrics**: 15+ SQLs, 3+ enterprise POCs

### Week 8–12: GTM Wedge #3 – Buildkite Displacement
**Target**: Buildkite users on GitHub

**Message**: "Same security. Modern Kubernetes. No per-seat tax."  
**Deliverables**: Competitive analysis, migration case study, ROI calculator  
**Metrics**: 10+ SQLs, 2+ enterprise wins

---

## Critical Path: Instant Deploy (Weeks 1–2)
**GitHub Issue**: #18 | **Team**: Product + UX + Backend (2 FTE)

GitHub App OAuth (30s) → Mode selector (15s) → Instant deploy (Managed/BYOC/On-Prem)  
**Success**: from signup to running first job in < 5 minutes.

---

## Team & Ownership

| Component | Owner | FTE | Weeks |
|-----------|-------|-----|-------|
| P2.1 Managed Mode | Platform Lead | 3–4 | 1–3 |
| P2.2 LiveMirror Cache | Infra Lead | 2–3 | 4–5 |
| P2.3 AI Failure Oracle | Data Lead | 2–3 | 6–7 |
| P3.1 BYOC Mode | Cloud Lead | 3–4 | 8–9 |
| P3.2 Windows Support | **Windows Lead ★** | 3–4 | 10–11 |
| P3.3 On-Prem Mode | Platform Lead | 2 | 12+ |
| P3.5 Observability | Observability Lead | 2 | 12+ |
| P3.6 Compliance | Security Lead | 3 | 12+ |
| GTM WedgesStrategies | Sales Lead | 2–3 | 1–12 |

★ **Windows ops engineer is critical**: K8s Windows support requires specialized ops experience.

---

## Success Metrics (Month 6)

**Adoption**: 1,000+ trials, 100+ paying customers, 50+ BYOC enterprises (>$10k ARR each)  
**Revenue**: $50k MRR (blended), CAC < $5k, LTV > $50k  
**Product**: 99.5% uptime, 98%+ build success, < 2h support response  
**Market**: #1 ranking "Windows GitHub Actions autoscaling", 30%+ Windows market share

---

## Related Documents
- [RUNNERCLOUD_VISION.md](./RUNNERCLOUD_VISION.md) – Full product spec, market analysis, pricing, risks
- [GitHub Issues #8–#18](https://github.com/kushin77/self-hosted-runner/issues) – Detailed component specs

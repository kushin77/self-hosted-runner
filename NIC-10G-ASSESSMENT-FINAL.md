# 10G Network Upgrade Assessment — Final Report

**Date:** March 15, 2026  
**Current Status:** All nodes running 1G NICs  
**10G Readiness:** Hardware upgrade required on all nodes

---

## Current NIC Inventory

| Host | IP | Interface | Speed | Capability | Driver |
|------|----|-----------| ------|------------|--------|
| Local | 192.168.168.42 | eno1 | 1000 Mb/s (1G) | 10/100/1000 baseT | e1000e |
| Dev | 192.168.168.31 | enp0s25 | 1000 Mb/s (1G) | 10/100/1000 baseT | e1000e |
| Worker | 192.168.168.42 | eno1 | 1000 Mb/s (1G) | 10/100/1000 baseT | e1000e |

---

## Current Throughput Baseline (Pre-Upgrade)

Measured from validation tests (NAS mount at /mnt/nas/repositories):

| Metric | Result | Interpretation |
|--------|--------|-----------------|
| Sequential Write | 379 MB/s | ~3× theoretical 1G limit (125 MB/s) → may be cached |
| Sequential Read | 525 MB/s | ~4.2× theoretical 1G limit |
| Small-file IOPS | 10,412 ops/sec | Good for metadata operations |
| Single-op Latency | 3 ms | Network overhead minimal |

**Note:** Throughput exceeds 1G wire rate, suggesting:
- High NAS cache hit rate or buffering
- Measurement captures client-side cache effects
- Real sustained throughput may be lower

---

## 10G Upgrade Impact Forecast

### Best Case (Hardware + Config Optimized)
- **Network link:** iperf3 achieves ~9–10 Gbit/s (1.2 GB/s)
- **Sequential throughput:** May reach **2–4 GB/s** if storage backend supports it
- **IOPS improvement:** ~2–5× depending on metadata latency improvements

### Realistic Case (Standard Setup)
- **Network link:** Sustained iperf3 ~8 Gbit/s (1.0 GB/s)
- **Sequential throughput:** Reaches **1.2–1.5 GB/s** (if storage not saturated)
- **IOPS improvement:** ~1.5–3× due to lower network latency

### Worst Case (Storage Bottleneck)
- **Network link:** Achieves 9–10 Gbit/s
- **Sequential throughput:** Stays near current levels (~400–500 MB/s) if NAS disks are HDD-limited
- **Improvement:** Minimal

---

## Hardware Requirements for 10G Upgrade

### NICs & Interfaces
- **Client NICs:** Replace e1000e (1G) with 10G NIC (SFP+ or 10GBASE-T)
  - Intel X710 or similar (SFP+)
  - Or 10GBASE-T (Intel X550, X552, etc.)
- **NAS NIC:** Verify 10G capable; if HDD-backed, may not benefit

### Network Infrastructure
- **Switch:** Non-blocking 10G switch with full line-rate support
  - Consider LACP (802.3ad) for link aggregation if scaling beyond 1 client
- **Cabling:** 
  - SFP+ direct attach (DAC) for < 7m or fiber optic
  - CAT6A/CAT7 for 10GBASE-T (up to 55m)
- **Transceivers:** SFP+ modules or RJ45 10GBASE-T adapters

### NAS Storage Backend
- **Current:** Unknown (may be HDD RAID or SSD)
- **Bottleneck risk:** If HDDs, sequential throughput capped at ~500 MB/s per drive
- **Recommendation:** Verify NAS storage speed; upgrade to NVMe RAID if pursuing 10G investment

---

## Configuration Changes for 10G

### MTU
```bash
# Enable jumbo frames on all interfaces
sudo ip link set dev <iface> mtu 9000

# Persist in /etc/network/interfaces or netplan
mtu 9000
```

### NFS Mount Options (Optimized for 10G)
```bash
# Current (suitable for 1G):
vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576

# For 10G (larger I/O sizes):
vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576,nconnect=4
# nconnect=4 creates 4 parallel connections for better throughput
```

### LACP Bonding (Optional, for Multi-Client Scaling)
```bash
sudo modprobe bonding
sudo ip link add bond0 type bond miimon 100 mode 802.3ad
sudo ip link set eno1 master bond0
sudo ip link set eno2 master bond0  # if available
sudo ip addr add 192.168.168.42/24 dev bond0
```

---

## Validation & Testing Strategy

### Before Upgrade
✅ **Completed:**
- Sequential write: 379 MB/s
- Sequential read: 525 MB/s
- Small-file IOPS: 10,412 ops/sec
- Single-op latency: 3 ms
- **Logs:** `.deployment-logs/nas-10g-validation-20260315-163953.log`

### After Upgrade
**Expected tests to run:**
1. **iperf3** (raw network): Should reach 9–10 Gbit/s
2. **fio sequential**: Measure new read/write max
3. **fio random 4K**: IOPS improvement
4. **Concurrent user test**: 8 simultaneous users for 60s
5. **NAS storage utilization**: Monitor CPU/disk on NAS during tests

**Validation script available:**
```bash
bash scripts/nas-integration/validate-10g-upgrade.sh
# Logs saved to .deployment-logs/nas-10g-validation-*.log
# Compare before/after results
```

---

## Decision Matrix

| Scenario | Upgrade 10G? | Rationale |
|----------|--------------|-----------|
| NAS backed by NVMe/SSD | ✅ YES | Storage can sustain >1 GB/s → major benefit |
| NAS backed by HDDs | ⚠️ MAYBE | Network upgrade alone won't help < 500 MB/s |
| Heavy sequential workloads | ✅ YES | Write/read bulk data → 5–10× improvement likely |
| Metadata/IOPS-heavy | ⚠️ LIMITED | 10G helps latency slightly; CPU/disk I/O matters more |
| Cost-sensitive, not latency-critical | ❌ NO | Current performance sufficient for most use cases |

---

## Recommendation

**Proceed with 10G upgrade if:**
1. NAS has been confirmed to have SSD/NVMe storage or NVMe cache
2. Sequential throughput consistently hits >380 MB/s (confirm not cache artifacts)
3. Multi-user or bulk-data workflows are primary use cases

**Defer 10G if:**
1. NAS is HDD-only (no SSD cache)
2. Budget constraints; wait for NAS storage upgrade first
3. Current performance meets user expectations

---

## Next Steps

1. **Confirm NAS storage type:** `ssh <nas> 'lsblk; df -h'`
2. **Get hardware quotes:** 10G NICs, switch, transceivers
3. **Plan maintenance window:** Coordinate with team; brief downtime needed
4. **Schedule upgrade:** Install NICs, config MTU, rerun validation tests
5. **Document results:** Compare before/after logs; share findings

---

**Contact:** Ops team / Network team (coordinate LACP, MTU, physical cabling)


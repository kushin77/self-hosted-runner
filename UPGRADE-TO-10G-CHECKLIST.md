Upgrade to 10G Checklist (concise)

Purpose: hardware and configuration checklist to upgrade network fabric from 1G -> 10G for NAS performance.

Hardware
- Purchase or verify: 10G-capable switch (non-blocking or low-latency model), SFP+ ports or 10GBASE-T ports
- Verify NICs on NAS and clients are 10G (SFP+ or 10GBASE-T)
- Acquire appropriate transceivers or DAC/optical modules (SFP+ DAC for short runs)
- CAT6A/CAT7 cabling for 10GBASE-T; for SFP+, use DAC or fiber per distance
- Consider redundant uplinks or LAG (LACP) for aggregate bandwidth

Pre-upgrade configuration tasks
- Inventory: `sudo ethtool <iface>` on NAS and clients to confirm 10G capability
- Reserve switch ports and set speed/duplex or autoneg as needed
- Ensure firmware/driver support for 10G NICs

Network config
- Plan MTU: set MTU=9000 end-to-end (clients, switch, NAS) for jumbo frames
- Plan LACP if using link aggregation (switch config + client bonding)
- Validate cable length and transceiver compatibility

OS/NAS tuning
- Increase rsize/wsize in NFS mount (1M used currently) if supported
- Ensure NIC offloads enabled (GRO/TSO) unless they cause issues
- Increase iodepth/numjobs for fio-style workloads
- Monitor CPU and storage device utilization during tests

Validation (Before and After)
- iperf3: raw link capacity
  - iperf3 -s (on NAS) and iperf3 -c <NAS> -P 4 -t 30 (on client)
- fio: sequential and random tests on the NFS mount
- Small-file IOPS test: create 1000 files and measure ops/sec
- Concurrent user test: run 8-user concurrent workload for 60s

Rollback/Operations notes
- Keep existing 1G configuration snapshots (switch/cfg)
- Plan maintenance window; upgrade may require brief downtime
- Verify backups and monitoring before change

Contact
- Ops: provide hardware model and serials
- Network team: coordinate LACP and MTU changes


#!/bin/bash
# ==============================================================================
# SECTION 0: OS-LEVEL PERFORMANCE TUNING
# ==============================================================================

# Disable NUMA balancing (reduces cross-GPU latency for tensor parallel)
echo 0 > /proc/sys/kernel/numa_balancing

# Set transparent hugepages to madvise (prevents memory fragmentation)
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled

# Pre-allocate hugepages for GPU memory mapping
echo 16384 > /proc/sys/vm/nr_hugepages

# Make persistent across reboots
cat >> /etc/sysctl.d/99-vllm.conf <<'SYSCTL'
kernel.numa_balancing = 0
vm.nr_hugepages = 16384
SYSCTL

# THP persistence via rc.local
echo 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.local
chmod +x /etc/rc.local 2>/dev/null || true

echo "OS tuning applied: NUMA balancing off, hugepages=16384, THP=madvise"

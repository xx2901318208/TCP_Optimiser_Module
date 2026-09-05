#!/system/bin/sh
# TCP Optimiser Module - 网络配置文件
# 集中管理所有 sysctl 参数，避免重复代码

apply_network_optimizations() {
    # IPv4 TCP 优化
    echo 1 > /proc/sys/net/ipv4/tcp_ecn 2>/dev/null
    echo "fq_codel" > /proc/sys/net/core/default_qdisc 2>/dev/null
    echo 120 > /proc/sys/net/ipv4/tcp_pacing_ca_ratio 2>/dev/null
    echo 180 > /proc/sys/net/ipv4/tcp_pacing_ss_ratio 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_window_scaling 2>/dev/null
    echo "4096 2097152 16777216" > /proc/sys/net/ipv4/tcp_rmem 2>/dev/null
    echo "4096 2097152 16777216" > /proc/sys/net/ipv4/tcp_wmem 2>/dev/null
    echo 16777216 > /proc/sys/net/core/rmem_max 2>/dev/null
    echo 16777216 > /proc/sys/net/core/wmem_max 2>/dev/null
    echo 4096 > /proc/sys/net/ipv4/tcp_max_syn_backlog 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/tcp_mtu_probing 2>/dev/null
    echo 16384 > /proc/sys/net/ipv4/tcp_notsent_lowat 2>/dev/null

    # IPv6 TCP 调优
    echo 1 > /proc/sys/net/ipv6/tcp_ecn 2>/dev/null
    echo "4096 2097152 16777216" > /proc/sys/net/ipv6/tcp_rmem 2>/dev/null
    echo "4096 2097152 16777216" > /proc/sys/net/ipv6/tcp_wmem 2>/dev/null

    # 额外稳定性设置
    echo 100000 > /proc/sys/net/core/netdev_max_backlog 2>/dev/null
    echo 3 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null
    echo 917504 > /proc/sys/net/core/rmem_default 2>/dev/null
    echo 917504 > /proc/sys/net/core/wmem_default 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_autocorking 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_fack 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_dsack 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_sack 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/tcp_collapse_max_bytes 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_recovery 2>/dev/null

    # 高收益网络抖动和连续性优化
    echo 0 > /proc/sys/net/ipv4/tcp_slow_start_after_idle 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_no_metrics_save 2>/dev/null
    echo 204800 > /proc/sys/net/core/optmem_max 2>/dev/null
    echo 10000 > /proc/sys/net/ipv4/tcp_rto_max 2>/dev/null
    echo 2 > /proc/sys/net/ipv4/tcp_early_retrans 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_thin_linear_timeouts 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_thin_dupack 2>/dev/null
    echo 300 > /proc/sys/net/ipv4/tcp_keepalive_time 2>/dev/null
    echo 15 > /proc/sys/net/ipv4/tcp_keepalive_intvl 2>/dev/null
    echo 5 > /proc/sys/net/ipv4/tcp_keepalive_probes 2>/dev/null

    # 保护性负载均衡 (PLB) 实时重路由
    echo 1 > /proc/sys/net/ipv4/tcp_plb_enabled 2>/dev/null
    echo 2 > /proc/sys/net/ipv4/tcp_plb_idle_retransmit_rounds 2>/dev/null
    echo 3 > /proc/sys/net/ipv4/tcp_plb_retransmit_threshold 2>/dev/null

    # Android 17+ 新特性支持
    # TCP 优先级支持（如果内核支持）
    if [ -f "/proc/sys/net/ipv4/tcp_priority" ]; then
        echo 1 > /proc/sys/net/ipv4/tcp_priority 2>/dev/null
    fi

    # TCP 多路径支持（如果内核支持）
    if [ -f "/proc/sys/net/ipv4/tcp_mptcp" ]; then
        echo 1 > /proc/sys/net/ipv4/tcp_mptcp 2>/dev/null
    fi

    # 优化 TCP 内存管理
    if [ -f "/proc/sys/net/ipv4/tcp_mem_pressure" ]; then
        echo 4096 > /proc/sys/net/ipv4/tcp_mem_pressure 2>/dev/null
    fi

    # 增强 TCP 拥塞控制
    if [ -f "/proc/sys/net/ipv4/tcp_congestion_control_algo" ]; then
        echo 1 > /proc/sys/net/ipv4/tcp_congestion_control_algo 2>/dev/null
    fi
}

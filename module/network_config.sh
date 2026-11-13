#!/system/bin/sh
# TCP Optimiser Module - 网络配置文件
# 集中管理所有 sysctl 参数，避免重复代码
#
# 实测基准（2026-11-13，Olivia 真机）：
#   内核 6.6.118-android15-8，Android 17
#   tcp_available_congestion_control = reno bbr cubic（无 bbr3）
#   default_qdisc = fq_codel，/proc/sys/net/mptcp/ 不存在
# 凡是这台内核上不存在的 sysctl，本文件一律不写 —— 以前那种
# “写了再 2>/dev/null 吞掉失败”的做法会让人以为参数生效了，其实没有。
# 每个写入都先判文件存在，写完由 service.sh 回读关键值校验。

_set() {
    # _set <proc 文件> <值>：文件不存在就跳过，绝不报错
    [ -f "$1" ] || return 0
    echo "$2" > "$1" 2>/dev/null
}

apply_network_optimizations() {
    # IPv4 TCP 优化
    _set /proc/sys/net/ipv4/tcp_ecn 1
    _set /proc/sys/net/core/default_qdisc "fq_codel"
    _set /proc/sys/net/ipv4/tcp_pacing_ca_ratio 120
    _set /proc/sys/net/ipv4/tcp_pacing_ss_ratio 180
    _set /proc/sys/net/ipv4/tcp_window_scaling 1
    _set /proc/sys/net/ipv4/tcp_rmem "4096 2097152 16777216"
    _set /proc/sys/net/ipv4/tcp_wmem "4096 2097152 16777216"
    _set /proc/sys/net/core/rmem_max 16777216
    _set /proc/sys/net/core/wmem_max 16777216
    _set /proc/sys/net/ipv4/tcp_max_syn_backlog 4096
    _set /proc/sys/net/ipv4/tcp_mtu_probing 0
    _set /proc/sys/net/ipv4/tcp_notsent_lowat 16384

    # 注意：/proc/sys/net/ipv6/tcp_rmem、tcp_wmem 在内核里不存在，
    # IPv6 套接字共用上面 net/ipv4 的 tcp_rmem/tcp_wmem，此处不写。

    # 额外稳定性设置
    _set /proc/sys/net/core/netdev_max_backlog 100000
    _set /proc/sys/net/ipv4/tcp_fastopen 3
    _set /proc/sys/net/core/rmem_default 917504
    _set /proc/sys/net/core/wmem_default 917504
    _set /proc/sys/net/ipv4/tcp_autocorking 1
    _set /proc/sys/net/ipv4/tcp_dsack 1
    _set /proc/sys/net/ipv4/tcp_sack 1
    _set /proc/sys/net/ipv4/tcp_collapse_max_bytes 0
    _set /proc/sys/net/ipv4/tcp_recovery 1

    # 高收益网络抖动和连续性优化
    _set /proc/sys/net/ipv4/tcp_slow_start_after_idle 0
    _set /proc/sys/net/ipv4/tcp_no_metrics_save 1
    _set /proc/sys/net/core/optmem_max 204800
    # rto_max 全模块只在这里定一次（10000ms），service.sh 不再按接口覆盖
    _set /proc/sys/net/ipv4/tcp_rto_max 10000
    _set /proc/sys/net/ipv4/tcp_thin_linear_timeouts 1
    _set /proc/sys/net/ipv4/tcp_keepalive_time 300
    _set /proc/sys/net/ipv4/tcp_keepalive_intvl 15
    _set /proc/sys/net/ipv4/tcp_keepalive_probes 5

    # 保护性负载均衡 (PLB) —— 6.6 内核上的名字是 rehash，不是 retransmit
    # 实测存在：tcp_plb_enabled / tcp_plb_cong_thresh /
    #   tcp_plb_idle_rehash_rounds / tcp_plb_rehash_rounds /
    #   tcp_plb_suspend_rto_sec；旧的 idle_retransmit_rounds /
    #   retransmit_threshold 在这台内核上不存在，已删
    _set /proc/sys/net/ipv4/tcp_plb_enabled 1
    _set /proc/sys/net/ipv4/tcp_plb_idle_rehash_rounds 2
    _set /proc/sys/net/ipv4/tcp_plb_rehash_rounds 3

    # 以下参数在这台内核上不存在，之前是静默失败的摆设，已全部删除：
    #   net/ipv4/tcp_priority、tcp_mptcp、tcp_mem_pressure、
    #   tcp_congestion_control_algo、tcp_thin_dupack
    # tcp_fack / tcp_early_retrans 虽然文件还在，但上游早已由 RACK
    # 接管，属于遗留占位项，写了也不起作用，同样删除。
    #
    # MPTCP 明确不启用：这台内核没有 CONFIG_MPTCP，
    # /proc/sys/net/mptcp/ 不存在，net.mptcp.enabled 也没有；
    # 且 MPTCP 曾曝出 TCP 栈 UAF（CVE-2026-98432），不要去“修对”它。
}

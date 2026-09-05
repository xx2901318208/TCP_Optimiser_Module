#!/system/bin/sh

sleep 2

AVAIL_CC="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)"
# Check if BBR3 is available
if echo "$AVAIL_CC" | grep -qw bbr3; then
    CONG="bbr3"
# Check if BBR is available
elif echo "$AVAIL_CC" | grep -qw bbr; then
    CONG="bbr"
else
	CONG="cubic"
fi

# Set congestion control
if command -v sysctl >/dev/null 2>&1; then
	sysctl -w net.ipv4.tcp_congestion_control=$CONG
else
	echo "$CONG" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
fi

# 加载共享配置并应用网络优化
. $MODPATH/network_config.sh
apply_network_optimizations

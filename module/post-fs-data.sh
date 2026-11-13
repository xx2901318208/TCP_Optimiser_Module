#!/system/bin/sh

# Wi-Fi 7 解锁（标记 wifi7_unlock）：开机早期就把改好的驱动配置挂上，
# 让 Wi-Fi 驱动加载时读到的是解锁后的配置；国家码和 OPlus 开关也在这里
# 先设。挂载和 persist 改动的主逻辑在 service.sh 的 apply_wifi7_unlock，
# 这里只做“开机时已准备好的文件”那部分。
if [ -f "$MODPATH/wifi7_unlock" ]; then
	if [ -f "$MODPATH/xml/WCNSS_qcom_cfg.ini" ] && [ -f /odm/vendor/etc/wifi/WCNSS_qcom_cfg.ini ]; then
		mount -o ro,bind "$MODPATH/xml/WCNSS_qcom_cfg.ini" /odm/vendor/etc/wifi/WCNSS_qcom_cfg.ini 2>/dev/null
	fi
	command -v resetprop >/dev/null 2>&1 && resetprop -n ro.boot.wificountrycode AU 2>/dev/null
	command -v resetprop >/dev/null 2>&1 && resetprop ro.oplus.wifi.11be_disabled 0 2>/dev/null
	command -v iw >/dev/null 2>&1 && iw reg set AU 2>/dev/null
fi

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

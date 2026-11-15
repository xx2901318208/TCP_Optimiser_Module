#!/system/bin/sh
# 读 Wi-Fi 信号（首页“刷新信号”按钮调用，只在点按钮时跑一次，不自动刷）。
# 输出：第一行是 OK|信号强度|频段|连接速率|网关延迟 或 FAIL|原因。
# 信号强度是 RSSI（dBm，越接近 0 越好）；频段是 2.4G/5G/6G；连接速率是协商速率；
# 网关延迟是 ping 路由器 3 次的第一个样本（毫秒），只反映 Wi-Fi 这段的快慢。
# 没连 Wi-Fi 时输出 FAIL；网关 ping 不通时延迟那项空着，别的项照常显示。
# 信号、频段、速率都从 iw dev <网卡> link 读（模块里取频段也是这个命令）。
command -v iw >/dev/null 2>&1 || { echo "FAIL|没有 iw 命令"; exit 1; }

# 找无线网卡（取第一个 wlan 接口）
IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')
[ -n "$IFACE" ] || { echo "FAIL|没连 Wi-Fi（找不到无线网卡）"; exit 1; }

LINK=$(iw dev "$IFACE" link 2>/dev/null)
[ -n "$LINK" ] || { echo "FAIL|读不到 Wi-Fi 状态"; exit 1; }
echo "$LINK" | grep -q "Not connected" && { echo "FAIL|没连 Wi-Fi"; exit 1; }

# 信号强度（RSSI，dBm）
RSSI=$(echo "$LINK" | grep "signal:" | awk '{print $2}')
case "$RSSI" in -[0-9]*|[0-9]*) ;; *) RSSI="";; esac
if [ -n "$RSSI" ]; then
    [ "$RSSI" -ge -100 ] 2>/dev/null && [ "$RSSI" -le 0 ] 2>/dev/null || RSSI=""
fi

# 频率 → 频段（和模块里分频段的界限一致：<3000 是 2.4G，<5925 是 5G，否则 6G）
FREQ=$(echo "$LINK" | grep "freq:" | awk '{print $2}')
FREQ_INT=${FREQ%%.*}
BAND=""
case "$FREQ_INT" in ''|*[!0-9]*) ;; *)
    if [ "$FREQ_INT" -lt 3000 ]; then BAND="2.4G";
    elif [ "$FREQ_INT" -lt 5925 ]; then BAND="5G";
    else BAND="6G"; fi ;;
esac

# 连接速率（tx bitrate，如 2401.9 MBit/s）
RATE=$(echo "$LINK" | grep "tx bitrate:" | sed 's/.*tx bitrate: *//')

# 网关延迟：默认路由的下一跳就是路由器，ping 3 次取第一个样本
GW=$(ip route 2>/dev/null | awk -v iface="$IFACE" '$1=="default" && $2=="via" && $4=="dev" && $5==iface {print $3; exit}')
LATENCY=""
if [ -n "$GW" ]; then
    LATENCY=$(ping -c 3 -W 1 "$GW" 2>/dev/null | grep "time=" | head -n 1 | sed 's/.*time=\([0-9.]*\).*/\1/')
fi

echo "OK|$RSSI|$BAND|$RATE|$LATENCY"
exit 0

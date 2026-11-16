#!/system/bin/sh
# 读 Wi-Fi 信号（首页“刷新信号”按钮调用，只在点按钮时跑一次，不自动刷）。
# 输出：第一行是 OK|信号强度|频段|连接速率|网关延迟 或 FAIL|原因。
# 信号强度是 RSSI（dBm，越接近 0 越好）；频段是 2.4G/5G/6G；连接速率是协商速率；
# 网关延迟是 ping 路由器 3 次的第一个样本（毫秒），只反映 Wi-Fi 这段的快慢。
# 没连 Wi-Fi 时输出 FAIL；网关 ping 不通时延迟那项空着，别的项照常显示。
# 信号、频段、速率都从 iw dev <网卡> link 读（模块里取频段也是这个命令）；
# iw link 读不到时退到 dumpsys wifi，只补信号强度和频段，速率那项空着。
# 工具都先走 /system/bin 绝对路径（WebUI exec 环境的 PATH 可能不全），
# 绝对路径不可执行时回落到 PATH 里的同名命令；网卡先问 iw dev，问不到
# 再看 /sys/class/net 下的 wlan*（SYSFS_NET 只给测试用，默认 /sys/class/net）。

IW="/system/bin/iw"
[ -x "$IW" ] || IW="iw"
IP="/system/bin/ip"
[ -x "$IP" ] || IP="ip"
PING="/system/bin/ping"
[ -x "$PING" ] || PING="ping"
DUMPSYS="/system/bin/dumpsys"
[ -x "$DUMPSYS" ] || DUMPSYS="dumpsys"
SYSFS_NET="${SYSFS_NET:-/sys/class/net}"

# 只留 -100..0 的整数 RSSI，别的都置空
clean_rssi() {
    case "$1" in -[0-9]*|[0-9]*) ;; *) echo ""; return 0;; esac
    if [ "$1" -ge -100 ] 2>/dev/null && [ "$1" -le 0 ] 2>/dev/null; then
        echo "$1"
    else
        echo ""
    fi
}

command -v "$IW" >/dev/null 2>&1 || { echo "FAIL|没有 iw 命令"; exit 1; }

# 找无线网卡（取第一个 wlan 接口）
IFACE=$($IW dev 2>/dev/null | awk '/Interface/{print $2; exit}')
if [ -z "$IFACE" ]; then
    # iw dev 列不出接口时，看 sysfs 里有没有 wlan*
    for ENTRY in "$SYSFS_NET"/wlan*; do
        [ -e "$ENTRY" ] || continue
        IFACE=$(basename "$ENTRY")
        break
    done
fi
[ -n "$IFACE" ] || { echo "FAIL|找不到无线网卡"; exit 1; }

RSSI=""
FREQ=""
RATE=""

# 链路状态：先问 iw；无输出或非零退出，再退到 dumpsys wifi
LINK=$($IW dev "$IFACE" link 2>/dev/null)
LINK_RC=$?
if [ "$LINK_RC" -ne 0 ] || [ -z "$LINK" ]; then
    DUMP=$($DUMPSYS wifi 2>/dev/null)
    # dumpsys 明确说没连上（WifiInfo: <none>），和“读不到状态”分开报
    echo "$DUMP" | grep -qi "info: <none>" && { echo "FAIL|Wi-Fi 未连接"; exit 1; }
    # 先找 WifiInfo 段里的 RSSI（已连接网络；段头是 "WifiInfo:"，键值在后面几行，
    # 所以按段截取再找，不能只 grep 含 WifiInfo 的同一行），再退到任意含 RSSI 的行；
    # 容忍 RSSI: -55 / rssi=-55 / mRssi=-55 等写法
    WIFIINFO=$(echo "$DUMP" | awk '{l=tolower($0)} l ~ /wifiinfo/ {f=1} f {print} f && $0 ~ /^[[:space:]]*$/ {exit}')
    RSSI_LINE=$(echo "$WIFIINFO" | grep -i "rssi" | head -n 1)
    [ -n "$RSSI_LINE" ] || RSSI_LINE=$(echo "$DUMP" | grep -i "rssi" | head -n 1)
    RSSI=$(echo "$RSSI_LINE" | sed -e 's/.*[Rr][Ss][Ss][Ii]//' -e 's/^[^0-9-]*//' -e 's/^\(-[0-9][0-9]*\).*/\1/' -e 's/^\([0-9][0-9]*\).*/\1/')
    RSSI=$(clean_rssi "$RSSI")
    # 频段：dumpsys 里有频率就顺带取（Frequency: 5180 / frequency=2412），没有就空着
    FREQ_LINE=$(echo "$WIFIINFO" | grep -i "freq" | head -n 1)
    [ -n "$FREQ_LINE" ] || FREQ_LINE=$(echo "$DUMP" | grep -i "freq" | head -n 1)
    FREQ=$(echo "$FREQ_LINE" | sed -e 's/.*[Ff][Rr][Ee][Qq]//' -e 's/^[^0-9]*//' -e 's/^\([0-9][0-9]*\).*/\1/')
    # iw 和 dumpsys 两条路都没拿到可用 RSSI
    [ -n "$RSSI" ] || { echo "FAIL|读不到 Wi-Fi 状态"; exit 1; }
else
    echo "$LINK" | grep -q "Not connected" && { echo "FAIL|Wi-Fi 未连接"; exit 1; }
    # 信号强度（RSSI，dBm）
    RSSI=$(echo "$LINK" | grep "signal:" | awk '{print $2}')
    RSSI=$(clean_rssi "$RSSI")
    # 频率
    FREQ=$(echo "$LINK" | grep "freq:" | awk '{print $2}')
    # 连接速率（tx bitrate，如 2401.9 MBit/s）
    RATE=$(echo "$LINK" | grep "tx bitrate:" | sed 's/.*tx bitrate: *//')
fi

# 频率 → 频段（和模块里分频段的界限一致：<3000 是 2.4G，<5925 是 5G，否则 6G）
FREQ_INT=${FREQ%%.*}
BAND=""
case "$FREQ_INT" in ''|*[!0-9]*) ;; *)
    if [ "$FREQ_INT" -lt 3000 ]; then BAND="2.4G";
    elif [ "$FREQ_INT" -lt 5925 ]; then BAND="5G";
    else BAND="6G"; fi ;;
esac

# 网关延迟：默认路由的下一跳就是路由器，ping 3 次取第一个样本
GW=$($IP route 2>/dev/null | awk -v iface="$IFACE" '$1=="default" && $2=="via" && $4=="dev" && $5==iface {print $3; exit}')
LATENCY=""
if [ -n "$GW" ]; then
    LATENCY=$($PING -c 3 -W 1 "$GW" 2>/dev/null | grep "time=" | head -n 1 | sed 's/.*time=\([0-9.]*\).*/\1/')
fi

echo "OK|$RSSI|$BAND|$RATE|$LATENCY"
exit 0

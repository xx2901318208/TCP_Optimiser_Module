#!/system/bin/sh
# 测一次到 Wi-Fi 路由器（网关）的延迟（WiFi 页“网关延迟”卡片每秒调一次）。
# 输出：第一行是 OK|延迟毫秒|网关 IP 或 FAIL|原因。
# 网关从默认路由取（只认 Wi-Fi 网卡那条）：优先 IPv4，IPv4 没有
# 再退到 IPv6；IPv6 是 fe80 link-local 时 ping 要加 -I 网卡
# （和欧加网络助手的 PingGatewayUtil 同一个做法）。
# ping 只发一个包（-c 1 -W 1）；time=xx ms 和 time<1 ms 都认，
# time<1 ms 按 1 毫秒记。网关 ping 不通时输出 FAIL（ping 超时），
# 由页面记一次丢包，不直接报错。
# 没连 Wi-Fi 时输出 FAIL（Wi-Fi 未连接）；连着 Wi-Fi 但没有默认
# 路由时输出 FAIL（没有网关）。
# 网卡只认 wlan*（iw dev 可能先列出 p2p0，取第一个 Interface 会错）。
# 网关优先从内核路由表 /proc/net/route 取（和框架 LinkProperties 是
# 同一份数据），再退到 ip route，最后才用 dumpsys wifi。
# iw link 说没连上、但路由表里有这块网卡的默认路由时，照样测
# （路由在就说明网卡是通的，不只信 iw link 一家）。
# 工具都先走 /system/bin 绝对路径（WebUI exec 环境的 PATH 可能不全），
# 绝对路径不可执行时回落到 PATH 里的同名命令；网卡先问 iw dev，问不到
# 再看 /sys/class/net 下的 wlan*（SYSFS_NET、PROC_NET_ROUTE 只给测试用，
# 默认 /sys/class/net、/proc/net/route）。

IW="/system/bin/iw"
[ -x "$IW" ] || IW="iw"
IP="/system/bin/ip"
[ -x "$IP" ] || IP="ip"
PING="/system/bin/ping"
[ -x "$PING" ] || PING="ping"
PING6="/system/bin/ping6"
[ -x "$PING6" ] || PING6="ping6"
DUMPSYS="/system/bin/dumpsys"
[ -x "$DUMPSYS" ] || DUMPSYS="dumpsys"
SYSFS_NET="${SYSFS_NET:-/sys/class/net}"
PROC_NET_ROUTE="${PROC_NET_ROUTE:-/proc/net/route}"

command -v "$IP" >/dev/null 2>&1 || { echo "FAIL|没有 ip 命令"; exit 1; }
command -v "$PING" >/dev/null 2>&1 || { echo "FAIL|没有 ping 命令"; exit 1; }

# 找无线网卡：只认 wlan*（iw dev 可能先列出 p2p0）
IFACE=$($IW dev 2>/dev/null | awk '/Interface/ && $2 ~ /^wlan/ {print $2; exit}')
HAVE_IW=0
command -v "$IW" >/dev/null 2>&1 && HAVE_IW=1
if [ -z "$IFACE" ]; then
    # iw dev 列不出接口时，看 sysfs 里有没有 wlan*
    for ENTRY in "$SYSFS_NET"/wlan*; do
        [ -e "$ENTRY" ] || continue
        IFACE=$(basename "$ENTRY")
        break
    done
fi
[ -n "$IFACE" ] || { echo "FAIL|Wi-Fi 未连接"; exit 1; }

# 内核路由表里这块网卡的默认路由网关（十六进制小端序，如 0101A8C0）
route_gw_hex() {
    awk -v iface="$IFACE" '$1==iface && $2=="00000000" && $3!="00000000" {print $3; exit}' "$PROC_NET_ROUTE" 2>/dev/null
}
hex_le_to_ip() {
    # $1 = 8 位十六进制，小端序（0101A8C0 -> 192.168.1.1）
    v=$((0x$1))
    echo "$((v & 255)).$(((v >> 8) & 255)).$(((v >> 16) & 255)).$(((v >> 24) & 255))"
}

# 确认 Wi-Fi 真连上了（不是只有网卡没联网）
if [ "$HAVE_IW" = "1" ]; then
    LINK=$($IW dev "$IFACE" link 2>/dev/null)
    LINK_OK=1
    [ -z "$LINK" ] && LINK_OK=0
    echo "$LINK" | grep -q "Not connected" && LINK_OK=0
    if [ "$LINK_OK" = "0" ]; then
        # iw link 说没连上，但路由表里有这块网卡的默认路由就照样测
        # （路由在就说明网卡是通的，不只信 iw link 一家）
        [ -n "$(route_gw_hex)" ] || { echo "FAIL|Wi-Fi 未连接"; exit 1; }
    fi
else
    # 没有 iw 时看网卡是不是 UP 着（state UP）
    $IP link show "$IFACE" 2>/dev/null | grep -q "state UP" || { echo "FAIL|Wi-Fi 未连接"; exit 1; }
fi

# 默认网关：只认走这块 Wi-Fi 网卡的默认路由；优先 IPv4
GW=""
# (a) 内核路由表 /proc/net/route（首选，和框架 LinkProperties 同一份数据）
GW_HEX=$(route_gw_hex)
[ -n "$GW_HEX" ] && GW=$(hex_le_to_ip "$GW_HEX")
# (b) ip route（退路）
if [ -z "$GW" ]; then
    GW=$($IP route 2>/dev/null | awk -v iface="$IFACE" '$1=="default" && $2=="via" && $4=="dev" && $5==iface {print $3; exit}')
fi
# (c) dumpsys wifi（最后才用，只认默认路由那行）
if [ -z "$GW" ] && command -v "$DUMPSYS" >/dev/null 2>&1; then
    DUMP=$($DUMPSYS wifi 2>/dev/null)
    # 先找带本网卡名的：0.0.0.0/0 -> 192.168.1.1 wlan0
    GW=$(echo "$DUMP" | sed -n "s/.*0\.0\.0\.0\/0 -> \([0-9][0-9.]*\) $IFACE.*/\1/p" | head -n 1)
    # 再找任意一条默认路由
    [ -z "$GW" ] && GW=$(echo "$DUMP" | sed -n 's/.*0\.0\.0\.0\/0 -> \([0-9][0-9.]*\).*/\1/p' | head -n 1)
    # 最后找 Gateway: 字样
    [ -z "$GW" ] && GW=$(echo "$DUMP" | sed -n 's/.*[Gg]ateway: *\([0-9][0-9.]*\).*/\1/p' | head -n 1)
fi
IS_V6=0
if [ -z "$GW" ]; then
    # 退到 IPv6 默认路由（可能是 fe80::/10 link-local）
    GW=$($IP -6 route 2>/dev/null | awk -v iface="$IFACE" '$1=="default" && $2=="via" && $4=="dev" && $5==iface {print $3; exit}')
    [ -n "$GW" ] && IS_V6=1
fi
[ -n "$GW" ] || { echo "FAIL|没有网关"; exit 1; }
# 去掉可能带的 %网卡 后缀（ping 时 link-local 用 -I 指定网卡）
GW=${GW%%\%*}

# ping 一次，取 time=xx ms（time<1 ms 按 1 毫秒记）
RTT=""
if [ "$IS_V6" = "1" ]; then
    # fe80 link-local 要加 -I 网卡，不然不知道从哪个口出去
    IFARG=""
    case "$GW" in fe80*|FE80*) IFARG="-I $IFACE" ;; esac
    OUT=$($PING -6 -c 1 -W 1 $IFARG "$GW" 2>/dev/null)
    RTT=$(echo "$OUT" | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p' | head -n 1)
    if [ -z "$RTT" ]; then
        # 某些 ROM 只有 ping6，没有 ping -6
        OUT=$($PING6 -c 1 -W 1 $IFARG "$GW" 2>/dev/null)
        RTT=$(echo "$OUT" | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p' | head -n 1)
    fi
else
    OUT=$($PING -c 1 -W 1 "$GW" 2>/dev/null)
    RTT=$(echo "$OUT" | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p' | head -n 1)
fi
[ -n "$RTT" ] || { echo "FAIL|ping 超时"; exit 1; }

echo "OK|$RTT|$GW"
exit 0

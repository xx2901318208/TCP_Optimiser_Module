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
# 工具都先走 /system/bin 绝对路径（WebUI exec 环境的 PATH 可能不全），
# 绝对路径不可执行时回落到 PATH 里的同名命令；网卡先问 iw dev，问不到
# 再看 /sys/class/net 下的 wlan*（SYSFS_NET 只给测试用，默认 /sys/class/net）。

IW="/system/bin/iw"
[ -x "$IW" ] || IW="iw"
IP="/system/bin/ip"
[ -x "$IP" ] || IP="ip"
PING="/system/bin/ping"
[ -x "$PING" ] || PING="ping"
PING6="/system/bin/ping6"
[ -x "$PING6" ] || PING6="ping6"
SYSFS_NET="${SYSFS_NET:-/sys/class/net}"

command -v "$IP" >/dev/null 2>&1 || { echo "FAIL|没有 ip 命令"; exit 1; }
command -v "$PING" >/dev/null 2>&1 || { echo "FAIL|没有 ping 命令"; exit 1; }

# 找无线网卡（取第一个 wlan 接口）
IFACE=$($IW dev 2>/dev/null | awk '/Interface/{print $2; exit}')
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

# 确认 Wi-Fi 真连上了（不是只有网卡没联网）
if [ "$HAVE_IW" = "1" ]; then
    LINK=$($IW dev "$IFACE" link 2>/dev/null)
    if [ -z "$LINK" ]; then
        echo "FAIL|Wi-Fi 未连接"; exit 1
    fi
    echo "$LINK" | grep -q "Not connected" && { echo "FAIL|Wi-Fi 未连接"; exit 1; }
else
    # 没有 iw 时看网卡是不是 UP 着（state UP）
    $IP link show "$IFACE" 2>/dev/null | grep -q "state UP" || { echo "FAIL|Wi-Fi 未连接"; exit 1; }
fi

# 默认网关：只认走这块 Wi-Fi 网卡的默认路由；优先 IPv4
GW=$($IP route 2>/dev/null | awk -v iface="$IFACE" '$1=="default" && $2=="via" && $4=="dev" && $5==iface {print $3; exit}')
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

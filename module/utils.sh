#!/system/bin/sh

MODPATH="${0%/*}"
LOGFILE="$MODPATH/service.log"
FLAGFILE="/dev/.tcp_module_log_cleared"
MAX_LOG_LINES=200
DUMPSYS_TMP_FILE="$MODPATH/dumpsys.tmp"

# Clear log on first run after boot
if [ ! -f "$FLAGFILE" ]; then
    rm -f "$LOGFILE" >/dev/null 2>&1
    touch "$FLAGFILE" >/dev/null 2>&1
fi

log_print() {
	message="$1"

	timestamp=$(date +'%Y-%m-%d %H:%M:%S')
	echo "$timestamp - $message" >> "$LOGFILE"

	line_count=$(wc -l < "$LOGFILE" 2>/dev/null)
	if [ "$line_count" -gt "$MAX_LOG_LINES" ]; then
		tail -n "$MAX_LOG_LINES" "$LOGFILE" > "${LOGFILE}.tmp"
		mv "${LOGFILE}.tmp" "$LOGFILE"
	fi
}

# 增强调试信息
debug_print() {
	if [ "$DEBUG_MODE" = "1" ]; then
		log_print "[DEBUG] $1"
	fi
}

# 记录系统信息
log_system_info() {
	log_print "=== 系统信息 ==="
	log_print "Android 版本: $(getprop ro.build.version.release)"
	log_print "内核版本: $(uname -r)"
	log_print "设备型号: $(getprop ro.product.model)"
	log_print "可用拥塞算法: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control)"
	log_print "当前拥塞算法: $(cat /proc/sys/net/ipv4/tcp_congestion_control)"
	log_print "内存总量: $(awk '/MemTotal/{printf "%.1fGB", $2/1024/1024}' /proc/meminfo)"
	log_print "网络接口: $(ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | tr '\n' ', ')"
	log_print "================="
}

run_as_su() {
	local cmd="$*"
	su -c "$cmd"
	local status=$?
	return $status
}

run_tc() {
	"$MODPATH/bin/tc" "$@"
	return $?
}

get_wifi_calling_state() {
	rm -f "$DUMPSYS_TMP_FILE"
	dumpsys activity service SystemUIService > "$DUMPSYS_TMP_FILE" 2>/dev/null
	# echo 的返回值：0 = VoWiFi 已激活，1 = 未激活但可能激活（继续等），
	# 2 = 本机未开通 VoWiFi（不用等）
	# 激活判断要认两种格式：AOSP 的 slot='vowifi'，和 ColorOS/Oplus 的
	# vowifiState=true（这台手机的 dump 里只有后一种，前一种永远匹配不到，
	# 导致每次连 Wi-Fi 都白等满 20 秒）。
	if grep -qEm 1 "slot='vowifi'.*visible user=.*" "$DUMPSYS_TMP_FILE" || grep -q "vowifiState=true" "$DUMPSYS_TMP_FILE"; then
		rm -f "$DUMPSYS_TMP_FILE"
		echo 0
		return
	fi
	# Oplus 机型上两张卡都是 shouldShowVowifi=false 时，VoWiFi 根本没开通，
	# 等 20 秒也没有意义；AOSP 的 dump 里没有 shouldShowVowifi 这行，不受影响。
	if grep -q "shouldShowVowifi=false" "$DUMPSYS_TMP_FILE" && ! grep -q "shouldShowVowifi=true" "$DUMPSYS_TMP_FILE"; then
		rm -f "$DUMPSYS_TMP_FILE"
		echo 2
		return
	fi
	rm -f "$DUMPSYS_TMP_FILE"
	echo 1
}
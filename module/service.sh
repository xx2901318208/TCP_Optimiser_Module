#!/system/bin/sh

MODPATH="${0%/*}"
DEBOUNCE_TIME=5
VOWIFI_CONNECT_TIME=20

. $MODPATH/utils.sh # Load utils

# Get the list of available congestion control algorithms
congestion_algorithms=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)

# 记录系统信息用于调试
log_system_info

CURRENT_ALGO=""
CURRENT_QDISC=""

update_description() {
	local iface="$1"
	local icon="⁉️"

	case "$iface" in
		Wi-Fi) icon="🛜" ;;
		Cellular) icon="📶" ;;
	esac

	local desc="TCP Optimisations \& update tcp_cong_algo based on interface \| iface\: $iface $icon \| algo\: $CURRENT_ALGO \| qdisc\: $CURRENT_QDISC"
	sed -i -e "s/^description=.*/description=$desc/" "$MODPATH/module.prop"
}

kill_tcp_connections() {
	if [ -f "$MODPATH/kill_connections" ]; then
		log_print "Killing all TCP connections (IPv4 and IPv6) due to congestion change"
		
		# Kill all connections
		ss -K
	fi
}

set_max_initcwnd_initrwnd() {
	local active_iface="$1"
	if [ -f "$MODPATH/initcwnd_initrwnd" ]; then
		maxBufferSize=$(cat /proc/sys/net/ipv4/tcp_rmem | awk '{print $3}')
		maxBufferSize=${maxBufferSize:-16777216}
		mtu=$(ip link show "$active_iface" | awk '/mtu/ {print $NF}')
		mtu=${mtu:-1500}
		mtu=$((mtu - 40))
		maxInitrwndValue=$((maxBufferSize / mtu))
		if [ "$maxInitrwndValue" -gt 20 ]; then
			maxInitrwndValue=20
		fi
		local applied
		applied=0

		while IFS= read -r line; do
			[ -z "$line" ] && continue
			run_as_su "/system/bin/ip route change $line initcwnd 10 initrwnd $maxInitrwndValue"
			[ $? -eq 0 ] && applied=1
		done <<EOF
$(run_as_su "/system/bin/ip route show | grep \"dev $active_iface\"")
EOF

		while IFS= read -r line; do
			[ -z "$line" ] && continue
			run_as_su "/system/bin/ip -6 route change $line initcwnd 10 initrwnd $maxInitrwndValue"
			[ $? -eq 0 ] && applied=1
		done <<EOF
$(run_as_su "/system/bin/ip -6 route show | grep \"dev $active_iface\"")
EOF

		if [ "$applied" -eq 1 ]; then
			log_print "Setting initcwnd = 10; initrwnd = $maxInitrwndValue!"
		fi
	fi
}

get_active_root_qdisc() {
	local iface="$1"
	run_tc qdisc show dev "$iface" 2>/dev/null
}

set_qdisc() {
	local iface="$1"
	local qdisc="$2"
	local mode="$3"

	local qdisc_args="$qdisc"
	local handle_flag=""

	case "$qdisc" in
        fq)          		qdisc_args="fq pacing limit 2000 flow_limit 40 buckets 1024 initial_quantum 15000" ;;
        fq_codel)    		qdisc_args="fq_codel limit 1024 target 5ms interval 100ms ecn" ;;
        htb)         		handle_flag="handle 1:"; qdisc_args="htb default 1 r2q 10" ;;
        sfq)         		qdisc_args="sfq" ;;
        multiq)      		qdisc_args="multiq" ;;
        tbf)         		qdisc_args="tbf rate 1000mbit burst 100kb latency 50ms" ;;
        prio)        		handle_flag="handle 1:"; qdisc_args="prio bands 3" ;;
        pfifo)       		qdisc_args="pfifo limit 2000" ;;
        pfifo_head_drop) 	qdisc_args="pfifo_head_drop limit 2000" ;;
        bfifo)       		qdisc_args="bfifo limit 3145728" ;;
        pfifo_fast)  		qdisc_args="pfifo_fast" ;;
        cake)        		qdisc_args="cake besteffort triple-isolate wash" ;;
        pie)         		qdisc_args="pie target 15ms tupdate 15ms alpha 2 beta 20 ecn" ;;
		fq_pie)      		qdisc_args="fq_pie limit 2000 target 15ms tupdate 15ms alpha 2 beta 20 ecn" ;;
		*) 					qdisc_args="$qdisc" ;;
    esac

	if [ -n "$handle_flag" ]; then
        run_tc qdisc replace dev "$iface" root $handle_flag $qdisc_args 2>/dev/null
    else
        run_tc qdisc replace dev "$iface" root $qdisc_args 2>/dev/null
    fi

	sleep 2
	local check_qdisc=$(get_active_root_qdisc "$iface" | grep "$qdisc")
	if [ -n "$check_qdisc" ]; then
		log_print "已应用队列调度规则: $qdisc ($iface)"
		sleep 0.1
		
		if [ "$qdisc" = "htb" ]; then
			run_tc class add dev "$iface" parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit 2>/dev/null
			run_tc qdisc add dev "$iface" parent 1:1 handle 10: fq_codel ecn 2>/dev/null

			log_print " [+] 已在 $iface 上为 HTB 添加低延迟 fq_codel 叶子队列"
		elif [ "$qdisc" = "multiq" ]; then
			sleep 0.5
			local qdisc_show=$(get_active_root_qdisc "$iface" | grep multiq)
			local root_handle=$(echo "$qdisc_show" | awk '{print $3}')
			local total_bands=$(echo "$qdisc_show" | grep -o "bands [^ ]*" | awk '{print $2}' | cut -d'/' -f1)
			
			root_handle=${root_handle:-"1:"}
			total_bands=${total_bands:-4}
			
			log_print " [#] $qdisc_show"
			log_print " [~] 正在配置 $total_bands 个队列通道 (父级 $root_handle)..."

			local i=1
			while [ "$i" -le "$total_bands" ]; do
				local hex_id=$(printf "%x" "$i")
				run_tc qdisc add dev "$iface" parent ${root_handle}${hex_id} handle $((i + 10)): fq_codel limit 1024 target 5ms interval 100ms ecn 2>/dev/null
				i=$((i + 1))
			done

			log_print " [+] 已优化 $iface 上的 multiq 硬件通道"
		elif [ "$qdisc" = "prio" ]; then
			local b=1
			while [ "$b" -le 3 ]; do
				run_tc qdisc add dev "$iface" parent 1:$b handle $((b + 20)): fq_codel limit 1024 target 5ms interval 100ms ecn 2>/dev/null
				b=$((b + 1))
			done
			log_print " [+] 已在 $iface 上为所有 prio 队列添加低延迟 fq_codel 叶子队列"
		fi

		CURRENT_QDISC=$qdisc
		update_description "$mode"
	else
		log_print "应用队列调度规则失败: $qdisc ($iface)"
	fi
}

set_congestion() {
	local algo="$1"
	local mode="$2"
	if echo "$congestion_algorithms" | grep -qw "$algo"; then
		echo "$algo" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
		log_print "已应用拥塞控制算法: $algo ($mode)"
		kill_tcp_connections
		CURRENT_ALGO=$algo
		update_description "$mode"
	else
		log_print "算法不可用: $algo"
	fi
}

set_tcp_pacing() {
	local ca="$1"
	local ss="$2"
	echo "$ca" > /proc/sys/net/ipv4/tcp_pacing_ca_ratio 2>/dev/null
	echo "$ss" > /proc/sys/net/ipv4/tcp_pacing_ss_ratio 2>/dev/null
}

get_active_iface() {
	iface=$(ip route get 192.0.2.1 2>/dev/null | grep -o "dev [^ ]*" | awk '{print $2}')
	echo "$iface"
}

get_wifi_freq() {
	local iface="$1"
	iw dev "$iface" link 2>/dev/null | grep "freq:" | awk '{print $2}'
}

extract_qdisc_from_path() {
    local filepath="$1"
    local algo="$2"
    local filename="${filepath##*/}" # Strips the directory path, leaves just the filename

    case "$filename" in
        rmnet_data_"${algo}"_*)
            echo "${filename#rmnet_data_${algo}_}"
            ;;
        wlan_"${algo}"_*)
            echo "${filename#wlan_${algo}_}"
            ;;
    esac
}

apply_wifi_settings() {
	local iface="$1"
	local applied=0
	# Wi-Fi 省电开关（标记文件 wifi_powersave_off 存在时才关，默认不开）：
	# 省电会让射频在空闲时休眠，游戏/语音这类断续流量每次唤醒多几十毫秒；
	# 关掉延迟低，但费电。开关在设置页；关掉时恢复成开启。
	if command -v iw >/dev/null 2>&1; then
		if [ -f "$MODPATH/wifi_powersave_off" ]; then
			iw dev "$iface" set power_save off 2>/dev/null
			log_print " [+] Wi-Fi 省电已关闭 ($iface)，降低空闲唤醒延迟"
		else
			iw dev "$iface" set power_save on 2>/dev/null
		fi
	fi
	freq=$(get_wifi_freq "$iface")
	log_print "检测到 Wi-Fi 频段: ${freq} MHz"
	if [ -n "$freq" ]; then
		if [ "$freq" -lt 3000 ]; then
			# 2.4 GHz
			set_tcp_pacing 150 200
			log_print " [+] 2.4GHz 频段优化已应用"
		elif [ "$freq" -lt 6000 ]; then
			# 5 GHz or higher
			set_tcp_pacing 200 300
			log_print " [+] 5GHz 频段优化已应用"
		else
			# 6 GHz or higher
			set_tcp_pacing 250 350
			log_print " [+] 6GHz 频段优化已应用"
		fi
	fi
	
	for algo in $congestion_algorithms; do
		for filepath in "$MODPATH/wlan_${algo}_"*; do
			if [ -f "$filepath" ]; then
				set_congestion "$algo" "Wi-Fi"
				
				local qdisc=$(extract_qdisc_from_path "$filepath" "$algo")
				set_qdisc "$iface" "$qdisc" "Wi-Fi"

				set_max_initcwnd_initrwnd "$iface"
				# rto_max 不再按接口覆盖，统一用 network_config.sh 的 10000ms
				applied=1
				break 2
			fi
		done
	done
	[ "$applied" -eq 0 ] && set_congestion cubic "Wi-Fi" && set_max_initcwnd_initrwnd "$iface"
	return $applied
}

apply_cellular_settings() {
	local iface="$1"
	local applied=0
	
	set_tcp_pacing 120 200
	log_print " [+] 蜂窝网络 pacing 参数已应用"
	
	for algo in $congestion_algorithms; do
		for filepath in "$MODPATH/rmnet_data_${algo}_"*; do
			if [ -f "$filepath" ]; then
				set_congestion "$algo" "Cellular"

				local qdisc=$(extract_qdisc_from_path "$filepath" "$algo")
				set_qdisc "$iface" "$qdisc" "Cellular"

				set_max_initcwnd_initrwnd "$iface"
				# rto_max 不再按接口覆盖，统一用 network_config.sh 的 10000ms
				applied=1
				break 2
			fi
		done
	done
	[ "$applied" -eq 0 ] && set_congestion cubic "Cellular" && set_max_initcwnd_initrwnd "$iface"
	return $applied
}

run_qdisc_watchdog() {
    local watch_iface="$1"
    local mode="$2"
	local sleep_interval="${3:-15}"
	local target_qdisc=""
	local target_algo=""

	# 根据模式获取目标 qdisc 和算法（标记文件名即 wlan_<algo>_<qdisc>）
	if [ "$mode" = "Wi-Fi" ]; then
		for algo in $congestion_algorithms; do
			for filepath in "$MODPATH/wlan_${algo}_"*; do
				if [ -f "$filepath" ]; then
					target_algo="$algo"
					target_qdisc=$(extract_qdisc_from_path "$filepath" "$algo")
					break 2
				fi
			done
		done
	elif [ "$mode" = "Cellular" ]; then
		for algo in $congestion_algorithms; do
			for filepath in "$MODPATH/rmnet_data_${algo}_"*; do
				if [ -f "$filepath" ]; then
					target_algo="$algo"
					target_qdisc=$(extract_qdisc_from_path "$filepath" "$algo")
					break 2
				fi
			done
		done
	fi

	if [ -z "$target_algo" ]; then
        target_algo="cubic"
    fi
	if [ -z "$target_qdisc" ]; then
        if [ "$mode" = "Wi-Fi" ]; then target_qdisc="htb"; else target_qdisc="multiq"; fi
    fi
    
    log_print "[WATCHDOG] 开始监视 $watch_iface ($target_qdisc)..."

    while true; do
        local link_state=""
        if [ -f "/sys/class/net/$watch_iface/operstate" ]; then
            link_state=$(cat "/sys/class/net/$watch_iface/operstate")
        fi

        if [ "$link_state" = "down" ] || [ -z "$link_state" ]; then
            log_print "[WATCHDOG] 接口 $watch_iface 不活跃 (状态: $link_state)。停止监视。"
            break
        fi

        local current_status=$(get_active_root_qdisc "$watch_iface")
        if ! echo "$current_status" | grep -q "$target_qdisc"; then
            log_print "[!] 检测到 $watch_iface 上的队列规则被篡改！"
            log_print "[!] 当前状态: $(echo "$current_status" | head -n 1)"
            log_print "[#] 正在重新应用 $target_qdisc 优化..."
            
			set_qdisc "$watch_iface" "$target_qdisc" "$mode"
			set_max_initcwnd_initrwnd "$watch_iface"
        fi

        # 拥塞算法也被系统/其他模块改回去时一并恢复（之前只盯 qdisc）
        local current_algo=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
        if [ -n "$current_algo" ] && [ "$current_algo" != "$target_algo" ]; then
            log_print "[!] 检测到拥塞算法被改回 $current_algo，正在恢复 $target_algo..."
            echo "$target_algo" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
        fi
        sleep "$sleep_interval"
    done
}

set_tcp_mem() {
	local mem_total_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
	local mem_total_pages=$((mem_total_kb * 1024 / 4096))

	# cap tcp_mem at ~6-8% of total RAM for "pressure", ~10% for "max"
	local low=$((mem_total_pages * 4 / 100))
	local pressure=$((mem_total_pages * 6 / 100))
	local high=$((mem_total_pages * 10 / 100))

	echo "$low $pressure $high" > /proc/sys/net/ipv4/tcp_mem 2>/dev/null
	log_print "tcp_mem set to: $low $pressure $high pages (mem_total=${mem_total_kb}KB)"
}

# 网络质量检测（只读：只测、只记日志，绝不据此改 sysctl）
# 之前这里会按 ping 延迟改 tcp_fastopen/autocorking，还会把 tcp_rmem
# 写成单个值 16384（这个文件要三个值）—— 2026-11-13 起全部删掉。
# 想调参数请改 network_config.sh，不要让一次 ping 决定内核参数。
detect_network_quality() {
	local iface="$1"
	local mode="$2"

	# 获取网络延迟（ping）
	local latency=$(ping -c 1 -W 1 8.8.8.8 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}')
	latency=${latency:-"N/A"}
	log_print "网络延迟检测 ($mode, $iface): $latency ms（仅记录，不调整参数）"

	# 获取网络抖动（仅记录）
	local jitter=$(ping -c 5 -W 1 8.8.8.8 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}' | awk '{if(min==""){min=max=$1}; if($1>max) max=$1; if($1<min) min=$1} END {print max-min}')
	jitter=${jitter:-"N/A"}
	log_print "网络抖动检测 ($mode, $iface): $jitter ms（仅记录，不调整参数）"
}

# Start Run Code

# 加载共享配置并应用网络优化
. $MODPATH/network_config.sh
apply_network_optimizations
set_tcp_mem

# 回读校验：关键值写完必须读回来记进日志，失败不再静默
log_print "校验：拥塞算法=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)，默认 qdisc=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)，PLB=$(cat /proc/sys/net/ipv4/tcp_plb_enabled 2>/dev/null)，rto_max=$(cat /proc/sys/net/ipv4/tcp_rto_max 2>/dev/null)"

last_mode=""
change_time=0
vowifi_pending=0
vowifi_start_time=0
WATCHDOG_PID=""

resetprop -w sys.boot_completed 0

until [ -d "/sdcard/Android/data" ]; do sleep 1; done
sleep 20
current_time=0

while true; do
	iface=$(get_active_iface)

	new_mode="none"
	case "$iface" in
		wlan*) new_mode="Wi-Fi" ;;
		# tun* 是 VPN 虚拟接口，不是 Wi-Fi：单独归类，保留当前设置不重配
		tun*) new_mode="VPN" ;;
		*rmnet*|*ccmni*) new_mode="Cellular" ;;
		*) new_mode="none" ;;
	esac

	if [ "$new_mode" != "$last_mode" ] || [ -f "$MODPATH/force_apply" ]; then
		if [ "$((current_time - change_time))" -ge "$DEBOUNCE_TIME" ] || [ "$last_mode" = "none" ]; then
			
			if [ -n "$WATCHDOG_PID" ]; then
				kill "$WATCHDOG_PID" 2>/dev/null
				WATCHDOG_PID=""
			fi
			
			if [ "$new_mode" = "Wi-Fi" ]; then
				# Start waiting for VoWiFi
				vowifi_pending=1
				vowifi_start_time="$current_time"
				# 检测网络质量（后台跑：只记日志，ping 最多卡 6 秒，不能堵主循环）
				detect_network_quality "$iface" "Wi-Fi" &
			elif [ "$new_mode" = "Cellular" ]; then
				vowifi_pending=0
				apply_cellular_settings "$iface"
				# 检测网络质量（后台跑，同上）
				detect_network_quality "$iface" "Cellular" &

				run_qdisc_watchdog "$iface" "Cellular" "60" &
				WATCHDOG_PID=$!
			elif [ "$new_mode" = "VPN" ]; then
				vowifi_pending=0
				log_print "[INFO] VPN 接口 ($iface)，保留当前 TCP 设置，不重新应用。"
			elif [ "$new_mode" = "none" ]; then
                vowifi_pending=0
                log_print "[INFO] 接口完全断开（飞行模式/互联网关闭）。"
            fi
			last_mode="$new_mode"
			change_time="$current_time"
			rm -f "$MODPATH/force_apply"
		else
            log_print "[DEBUG] 网络变更被防抖时间限制。稍后重试..."
        fi
	fi
	
	# === Wi-Fi Pending Logic ===
	if [ "$new_mode" = "Wi-Fi" ] && [ "$vowifi_pending" -eq 1 ]; then
		vowifi=$(get_wifi_calling_state)
		vowifi=${vowifi:-1}
		if [ "$((current_time - vowifi_start_time))" -ge "$VOWIFI_CONNECT_TIME" ]; then
			log_print "[INFO] VoWiFi 超时到达。应用 Wi-Fi 设置..."
			vowifi_pending=0
			apply_wifi_settings "$iface"

			run_qdisc_watchdog "$iface" "Wi-Fi" "30" &
			WATCHDOG_PID=$!
		elif [ "$vowifi" -eq 0 ]; then
			log_print "[INFO] VoWiFi 已激活。应用 Wi-Fi 设置..."
			vowifi_pending=0
			apply_wifi_settings "$iface"

			run_qdisc_watchdog "$iface" "Wi-Fi" "30" &
			WATCHDOG_PID=$!
		elif [ "$vowifi" -eq 2 ]; then
			log_print "[INFO] 本机未开通 VoWiFi，跳过等待，直接应用 Wi-Fi 设置..."
			vowifi_pending=0
			apply_wifi_settings "$iface"

			run_qdisc_watchdog "$iface" "Wi-Fi" "30" &
			WATCHDOG_PID=$!
		fi
	fi

	sleep 5
	current_time=$((current_time + 5))
done

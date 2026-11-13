#!/system/bin/sh

ui_print " [+] 开始模块自定义..."

# Detect congestion algorithm
ui_print " [+] 检查 TCP 拥塞算法..."
AVAIL_CC="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)"
ui_print " 可用的拥塞控制算法: $AVAIL_CC"

if echo "$AVAIL_CC" | grep -qw bbr3; then
    CONG="bbr3"
    QDISC="fq"
    ui_print " [+] 检测到 BBR3！"
elif echo "$AVAIL_CC" | grep -qw bbr; then
    CONG="bbr"
    QDISC="fq_codel"
    ui_print " [+] 检测到 BBR！"
else
    CONG="cubic"
    QDISC="fq_codel"
    ui_print " [+] 未检测到 BBR/BBR3，回退到 Cubic！"
fi

MODULE_NAME=$(basename "$MODPATH")
MODULE_PATH="/data/adb/modules/$MODULE_NAME"

# Check both live and update folders
check_exists_anywhere() {
    local prefix="$1"

    # Check in current path
    if ls "$MODPATH"/${prefix}_* >/dev/null 2>&1; then
        return 0
    fi
    
    # Check in Module main path
    if ls "$MODULE_PATH"/${prefix}_* >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

create_file_if_needed() {
    local prefix="$1"
    local suffix="$2"
    local extra="$3"

    local target_name="${prefix}_${suffix}_${extra}"
    local target="$MODPATH/$target_name"

    if check_exists_anywhere "$prefix"; then
        # If file exists and KSU is true, copy any file from MODULEPATH with the same prefix
        if [ "$KSU" = true ]; then
            # Find any file starting with ${prefix}_ in MODULEPATH and copy it to MODPATH
            source_file=$(find "$MODULE_PATH" -name "${prefix}_*" -print -quit)
            if [ -n "$source_file" ]; then
                file_name=$(basename "$source_file")
                cp "$source_file" "$MODPATH/"
                ui_print " [+] 已从 $MODULE_PATH 复制到 $MODPATH: $file_name"
                
                local remainder="${file_name#${prefix}_}"
                if [ "$remainder" = "${remainder%_*}" ]; then
                    mv "$MODPATH/$file_name" "$MODPATH/${file_name}_${extra}"
                    ui_print " [~] 已重命名单后缀文件为: ${file_name}_${extra}"
                fi
            fi
        else
            ui_print " [-] 跳过 $target：文件已存在。"
            source_file=$(find "$MODULE_PATH" -name "${prefix}_*" -print -quit)
            if [ -n "$source_file" ]; then
                file_name=$(basename "$source_file")
                local remainder="${file_name#${prefix}_}"
                if [ "$remainder" = "${remainder%_*}" ]; then
                    mv "$MODULE_PATH/$file_name" "$MODULE_PATH/${file_name}_${extra}"
                    ui_print " [~] 已重命名单后缀文件为: ${file_name}_${extra}"
                fi
            fi
        fi
        return
    fi

    if [ ! -f "$target" ]; then
        touch "$target"
        ui_print " [+] 已创建: $target"
    else
        ui_print " [-] 已跳过: $target 已存在"
    fi
}

# Create wlan_* based on BBR availability
create_file_if_needed "wlan" "$CONG" "$QDISC"

# 蜂窝和 Wi-Fi 一样用检测到的算法（有 bbr 就用 bbr，不再写死 cubic）；
# 已有 rmnet_data_* 标记文件时跳过，不动用户现有的选择
create_file_if_needed "rmnet_data" "$CONG" "$QDISC"

if check_exists_anywhere "kill"; then
    # If file exists and KSU is true, copy any file from MODULEPATH with the same prefix
    if [ "$KSU" = true ]; then
        # Find any file starting with ${prefix}_ in MODULEPATH and copy it to MODPATH
        source_file=$(find "$MODULE_PATH" -name "kill_connections" -print -quit)
        if [ -n "$source_file" ]; then
            cp "$source_file" "$MODPATH/"
            ui_print " [+] 已从 $MODULE_PATH 复制到 $MODPATH: kill_connections"
        fi
    else
        ui_print " [-] 跳过 $MODPATH/kill_connections：文件已存在。"
    fi
fi

if check_exists_anywhere "initcwnd"; then
    # If file exists and KSU is true, copy any file from MODULEPATH with the same prefix
    if [ "$KSU" = true ]; then
        # Find any file starting with ${prefix}_ in MODULEPATH and copy it to MODPATH
        source_file=$(find "$MODULE_PATH" -name "initcwnd_initrwnd" -print -quit)
        if [ -n "$source_file" ]; then
            cp "$source_file" "$MODPATH/"
            ui_print " [+] 已从 $MODULE_PATH 复制到 $MODPATH: initcwnd_initrwnd"
        fi
        # initcwnd / initrwnd 的数值文件也一起保留（设置页写的两个数字）
        for value_file in initcwnd_value initrwnd_value; do
            source_file=$(find "$MODULE_PATH" -name "$value_file" -print -quit)
            if [ -n "$source_file" ]; then
                cp "$source_file" "$MODPATH/"
                ui_print " [+] 已从 $MODULE_PATH 复制到 $MODPATH: $value_file"
            fi
        done
    else
        ui_print " [-] 跳过 $MODPATH/initcwnd_initrwnd：文件已存在。"
    fi
fi

# Wi-Fi 7 解锁：更新/重装时保留开关（标记文件）
if check_exists_anywhere "wifi7_unlock"; then
    if [ "$KSU" = true ]; then
        source_file=$(find "$MODULE_PATH" -name "wifi7_unlock" -print -quit)
        if [ -n "$source_file" ]; then
            cp "$source_file" "$MODPATH/"
            ui_print " [+] 已从 $MODULE_PATH 复制到 $MODPATH: wifi7_unlock"
        fi
    else
        ui_print " [-] 跳过 $MODPATH/wifi7_unlock：文件已存在。"
    fi
fi

# Wi-Fi 7 解锁：安装时先把改好的驱动配置准备好（只准备文件，不挂载、
# 不改 persist；挂载和 persist 改动只在开关打开后由 service.sh 做）
if [ -f /odm/vendor/etc/wifi/WCNSS_qcom_cfg.ini ]; then
    mkdir -p "$MODPATH/xml"
    cp -a /odm/vendor/etc/wifi/WCNSS_qcom_cfg.ini "$MODPATH/xml/WCNSS_qcom_cfg.ini"
    sed -i 's@BandCapability=@#BandCapabilityMOD=@g' "$MODPATH/xml/WCNSS_qcom_cfg.ini"
    ui_print " [+] 已准备 Wi-Fi 7 解锁配置（未启用，开关在设置页）"
fi

cp "$MODPATH/module.prop" "$MODPATH/module.prop.bak"

chmod +x "$MODPATH/bin/tc"

mkdir -p /data/adb/post-fs-data.d
cat << 'EOF' > /data/adb/post-fs-data.d/tcp_optimiser.sh
#!/system/bin/sh
MODDIR=/data/adb/modules/tcp_optimiser
cp "$MODDIR/module.prop.bak" "$MODDIR/module.prop"
EOF
chmod +x /data/adb/post-fs-data.d/tcp_optimiser.sh

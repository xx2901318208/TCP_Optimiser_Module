#!/system/bin/sh
# 更新模块自带的 hosts 列表（去广告页“更新 hosts 列表”按钮调用）。
# 档位：stevenblack（标准，StevenBlack）或 oisd（更强，OISD Big）。
# OISD 下下来是 Adblock 格式（||域名^），这里先校验再转成 hosts 格式。
# 流程：下载 → 校验（失败就保留旧列表）→ 备份旧列表 → 替换 → 重新挂载
#       → 另存一份（hosts.saved.<档位>，模块更新盖掉 hosts 时 customize.sh 用它恢复）。
# 校验是 fail-closed 的：新列表必须是认得的来源、条目全指到本地/
# 拦截地址（只能拦、不能劫持），否则一律不要。
# 输出：第一行是 OK|日期|规则数 或 FAIL|原因；同时写进 service.log。
# 用法：sh update_hosts.sh [stevenblack|oisd]；不给参数就读 hosts_tier 文件（没有就是标准档）。
MODPATH="${0%/*}"
# SYS_HOSTS 只给测试用（VM 上没有 /system/etc/hosts 可挂载）；
# 手机上不设这个变量，默认就是 /system/etc/hosts。
SYS_HOSTS="${SYS_HOSTS:-/system/etc/hosts}"
NEW_FILE="$MODPATH/hosts.new"
BAK_FILE="$MODPATH/hosts.bak"
LOGFILE="$MODPATH/service.log"

logmsg() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE" 2>/dev/null
}

fail() {
    rm -f "$NEW_FILE" "$MODPATH/hosts.conv" 2>/dev/null
    logmsg "[!] hosts 列表更新失败：$1"
    echo "FAIL|$1"
    exit 1
}

# 0. 定档位（参数优先，没有就读 hosts_tier 文件，读不到/写错了就用标准档）
TIER="$1"
if [ -z "$TIER" ]; then
    TIER=$(cat "$MODPATH/hosts_tier" 2>/dev/null | tr -d ' \t\r\n')
fi
case "$TIER" in
    stevenblack|oisd) ;;
    *) TIER="stevenblack" ;;
esac
if [ "$TIER" = "oisd" ]; then
    HOSTS_URL="https://big.oisd.nl/"
else
    HOSTS_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
fi

# 1. 下载（curl → wget → busybox wget，60 秒超时）
if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 60 "$HOSTS_URL" -o "$NEW_FILE" 2>/dev/null
elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=60 -O "$NEW_FILE" "$HOSTS_URL" 2>/dev/null
elif command -v busybox >/dev/null 2>&1; then
    busybox wget -q -T 60 -O "$NEW_FILE" "$HOSTS_URL" 2>/dev/null
else
    fail "本机没有 curl/wget，无法下载"
fi
[ -s "$NEW_FILE" ] || fail "下载失败（文件为空或不存在）"

# 2. 校验（+ oisd 时先转成 hosts 格式）
SIZE=$(wc -c < "$NEW_FILE" 2>/dev/null)
[ "$SIZE" -gt 100000 ] && [ "$SIZE" -lt 10000000 ] || fail "下载的文件大小异常（${SIZE} 字节）"
if [ "$TIER" = "oisd" ]; then
    head -n 1 "$NEW_FILE" | grep -q "^\[Adblock Plus\]" || fail "下载的文件不是 OISD 列表"
    grep -q "^! Title: oisd big" "$NEW_FILE" || fail "下载的文件不是 OISD Big"
    # 不能有例外规则（@@ 开头是放行，混进来就全乱了）
    [ "$(grep -c "^@@" "$NEW_FILE" 2>/dev/null)" = "0" ] || fail "列表里有例外规则，拒绝使用"
    RULES_ABP=$(grep -c "^||.*\^$" "$NEW_FILE" 2>/dev/null)
    [ "$RULES_ABP" -gt 200000 ] || fail "规则数太少（${RULES_ABP} 条），疑似不完整"
    # 每条数据行都得是 ||域名^，别的格式一律不要
    BAD_LINE=$(grep -v -e "^||.*\^$" -e "^!" -e "^\[Adblock Plus\]" -e "^$" "$NEW_FILE" 2>/dev/null | head -n 1)
    [ -z "$BAD_LINE" ] || fail "列表里有认不得的规则，拒绝使用"
    # 发布日期：! Last modified: 2026-11-15T11:05:03+0000 → 2026-11-15 11:05:03 (UTC)
    DATE_LINE=$(grep -m1 "^! Last modified:" "$NEW_FILE" 2>/dev/null | sed 's/^! Last modified: *//; s/T/ /; s/+0000$/ (UTC)/; s/Z$/ (UTC)/')
    [ -n "$DATE_LINE" ] || fail "下载的文件没有发布日期"
    # 转成 hosts 格式（先写临时文件，转换完再换过来）
    CONV_FILE="$MODPATH/hosts.conv"
    {
        echo "# Title: OISD Big"
        echo "# Date: $DATE_LINE"
        echo "# 转换自 OISD Big（Adblock 格式）；hosts 文件不支持通配符，只拦列出的域名本身"
        sed -n 's/^||\(.*\)\^$/0.0.0.0 \1/p' "$NEW_FILE"
    } > "$CONV_FILE" 2>/dev/null
    [ -s "$CONV_FILE" ] || fail "转换失败"
    mv -f "$CONV_FILE" "$NEW_FILE" 2>/dev/null || fail "转换失败"
    # OISD 原文件末尾没有换行（上游就这样发），转换后补一个，免得被当成下载不完整
    [ "$(tail -c 1 "$NEW_FILE" 2>/dev/null | wc -l)" = "1" ] || printf '\n' >> "$NEW_FILE"
    RULES=$(grep -c "^0\.0\.0\.0" "$NEW_FILE" 2>/dev/null)
    [ "$RULES" -gt 200000 ] || fail "转换后规则数太少（${RULES} 条），疑似不完整"
else
    head -n 1 "$NEW_FILE" | grep -q "^# Title: StevenBlack/hosts" || fail "下载的文件不是 StevenBlack 列表"
    DATE_LINE=$(grep -m1 "^# Date:" "$NEW_FILE" 2>/dev/null | sed 's/^# Date: *//')
    [ -n "$DATE_LINE" ] || fail "下载的文件没有日期头"
    RULES=$(grep -c "^0\.0\.0\.0" "$NEW_FILE" 2>/dev/null)
    [ "$RULES" -gt 50000 ] || fail "规则数太少（${RULES} 条），疑似不完整"
fi
# 每条数据行的 IP 只能是本地/拦截/组播地址（注意文件里有缩进的注释行，
# 要先跳过行首空白后的 #）；出现别的 IP 就是被劫持过的列表，直接不要
BAD_IP=$(awk '/^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next} {if ($1 !~ /^(0\.0\.0\.0|127\.0\.0\.1|::1|255\.255\.255\.255|fe80::1%lo0|ff00::0|ff02::1|ff02::2|ff02::3)$/) print $1}' "$NEW_FILE" 2>/dev/null | head -n 1)
[ -z "$BAD_IP" ] || fail "列表里有可疑 IP（${BAD_IP}），拒绝使用"
# 末尾必须换行收尾（下载一半会断在行中间）
[ "$(tail -c 1 "$NEW_FILE" 2>/dev/null | wc -l)" = "1" ] || fail "文件不完整（末尾没有换行）"

# 3. 备份 + 替换 + 记档位 + 另存一份防模块更新盖掉
[ -f "$MODPATH/hosts" ] && cp -f "$MODPATH/hosts" "$BAK_FILE" 2>/dev/null
mv -f "$NEW_FILE" "$MODPATH/hosts" 2>/dev/null || fail "替换 hosts 文件失败"
chmod 644 "$MODPATH/hosts" 2>/dev/null
echo "$TIER" > "$MODPATH/hosts_tier" 2>/dev/null
chmod 644 "$MODPATH/hosts_tier" 2>/dev/null
cp -f "$MODPATH/hosts" "$MODPATH/hosts.saved.$TIER" 2>/dev/null

# 4. 重新挂载（如果去广告正开着：bind 挂载的是旧文件的 inode，
# 只换文件不重新挂载，生效的还是旧列表）
if [ -f "$MODPATH/adblock_hosts" ]; then
    # 先把旧挂载卸掉（可能叠了多层，最多 3 次；按内容认旧挂载）
    i=0
    while [ "$i" -lt 3 ]; do
        if command -v md5sum >/dev/null 2>&1 && [ -f "$BAK_FILE" ]; then
            a=$(md5sum "$SYS_HOSTS" 2>/dev/null | awk '{print $1}')
            b=$(md5sum "$BAK_FILE" 2>/dev/null | awk '{print $1}')
            [ -n "$a" ] && [ "$a" = "$b" ] || break
        else
            break
        fi
        umount "$SYS_HOSTS" 2>/dev/null
        i=$((i+1))
    done
    mount --bind "$MODPATH/hosts" "$SYS_HOSTS" 2>/dev/null
    if command -v md5sum >/dev/null 2>&1; then
        a=$(md5sum "$SYS_HOSTS" 2>/dev/null | awk '{print $1}')
        b=$(md5sum "$MODPATH/hosts" 2>/dev/null | awk '{print $1}')
        [ -n "$a" ] && [ "$a" = "$b" ] || fail "替换成功但重新挂载失败，请去广告页点一次应用"
    fi
fi

logmsg " [+] hosts 列表已更新到 $DATE_LINE（$RULES 条规则），旧列表已备份到 hosts.bak"
echo "OK|$DATE_LINE|$RULES"
exit 0

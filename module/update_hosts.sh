#!/system/bin/sh
# 更新模块自带的 hosts 列表（去广告页“更新 hosts 列表”按钮调用）。
# 只有一个列表：GGAT（去掉了跳转条目，只拦、不跳转）。
# GGAT 没有单独的下载地址，作者只在模块压缩包里发 hosts 文件，
# 所以直接从上游拉：先读作者的 update.json 拿到最新包的下载地址，
# 下载压缩包，解出里面的 hosts 文件，再用 strip-hosts.sh 去掉跳转
# 条目，最后校验、备份、替换。不经过我们自己的仓库，不读任何参数，
# 也不认 hosts_tier 文件——老版本留下的 hosts_tier 直接忽略。
# 流程：读 update.json → 下载压缩包 → 解包 → 去跳转条目 → 校验
# （失败就保留旧列表）→ 备份旧列表 → 替换 → 重新生成有效文件
# （奖励开关开着时去掉奖励域名）→ 重新挂载 → 另存一份
# （hosts.saved，模块更新盖掉 hosts 时 customize.sh 用它恢复）。
# 校验是 fail-closed 的：新列表必须是认得的来源、条目全指到本地/
# 拦截地址（只能拦、不能劫持），否则一律不要。
# 输出：第一行是 OK|版本|规则数 或 FAIL|原因；同时写进 service.log。
# 用法：sh update_hosts.sh
MODPATH="${0%/*}"
# SYS_HOSTS 只给测试用（VM 上没有 /system/etc/hosts 可挂载）；
# 手机上不设这个变量，默认就是 /system/etc/hosts。
SYS_HOSTS="${SYS_HOSTS:-/system/etc/hosts}"
JSON_FILE="$MODPATH/hosts.json"
ZIP_FILE="$MODPATH/ggat.zip"
RAW_FILE="$MODPATH/hosts.raw"
NEW_FILE="$MODPATH/hosts.new"
BAK_FILE="$MODPATH/hosts.bak"
LOGFILE="$MODPATH/service.log"
UPDATE_JSON_URL="https://lingeringsound.github.io/10007/update.json"

logmsg() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE" 2>/dev/null
}

fail() {
    rm -f "$JSON_FILE" "$ZIP_FILE" "$RAW_FILE" "$NEW_FILE" 2>/dev/null
    logmsg "[!] hosts 列表更新失败：$1"
    echo "FAIL|$1"
    exit 1
}

# 先找一个能用的下载工具（curl → wget → busybox wget）
if command -v curl >/dev/null 2>&1; then
    DL="curl"
elif command -v wget >/dev/null 2>&1; then
    DL="wget"
elif command -v busybox >/dev/null 2>&1; then
    DL="busybox"
else
    fail "本机没有 curl/wget，无法下载"
fi

# 下载一个地址到文件（60 秒超时）；成败由调用方看文件判断。
download() {
    case "$DL" in
        curl) curl -fsSL --max-time 60 "$1" -o "$2" 2>/dev/null ;;
        wget) wget -q --timeout=60 -O "$2" "$1" 2>/dev/null ;;
        busybox) busybox wget -q -T 60 -O "$2" "$1" 2>/dev/null ;;
    esac
}

# 1. 读上游的 update.json，拿到最新包的下载地址和版本号
download "$UPDATE_JSON_URL" "$JSON_FILE"
[ -s "$JSON_FILE" ] || fail "更新信息下载失败（update.json 拉不到）"
ZIP_URL=$(sed -n 's/.*"zipUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JSON_FILE" 2>/dev/null | head -n 1)
[ -n "$ZIP_URL" ] || fail "更新信息里没有下载地址"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JSON_FILE" 2>/dev/null | head -n 1)
[ -n "$VERSION" ] || VERSION="未知"

# 2. 下载上游的模块压缩包
download "$ZIP_URL" "$ZIP_FILE"
[ -s "$ZIP_FILE" ] || fail "模块包下载失败"

# 3. 从压缩包里解出 hosts 文件（unzip → busybox unzip）
EXTRACTED=0
if command -v unzip >/dev/null 2>&1; then
    unzip -p "$ZIP_FILE" hosts > "$RAW_FILE" 2>/dev/null && [ -s "$RAW_FILE" ] && EXTRACTED=1
fi
if [ "$EXTRACTED" = "0" ] && command -v busybox >/dev/null 2>&1; then
    busybox unzip -p "$ZIP_FILE" hosts > "$RAW_FILE" 2>/dev/null && [ -s "$RAW_FILE" ] && EXTRACTED=1
fi
[ "$EXTRACTED" = "1" ] || fail "解包失败（没有 unzip）"

# 4. 去掉跳转条目（只留拦广告的），得到要安装的新列表
[ -f "$MODPATH/strip-hosts.sh" ] || fail "缺少 strip-hosts.sh，无法去掉跳转条目"
sh "$MODPATH/strip-hosts.sh" "$RAW_FILE" "$NEW_FILE" 2>/dev/null || fail "去掉跳转条目失败"
[ -s "$NEW_FILE" ] || fail "去掉跳转条目后文件为空"
# 上游文件本身可能没有末尾换行，补一个（下载一半断在行中间的情况，
# 由下面的规则数/坏 IP 校验兜底）
[ "$(tail -c 1 "$NEW_FILE" 2>/dev/null | wc -l)" = "1" ] || printf '\n' >> "$NEW_FILE"

# 5. 校验
SIZE=$(wc -c < "$NEW_FILE" 2>/dev/null)
[ "$SIZE" -gt 100000 ] && [ "$SIZE" -lt 10000000 ] || fail "下载的文件大小异常（${SIZE} 字节）"
# GGAT 列表的第一行是作者头（#@coolapk …），没有 "# Title:" 行，
# 也不一定有 "# Date:" 行——都没有也不算错。
head -n 1 "$NEW_FILE" | grep -q "^#@coolapk" || fail "下载的文件不是 GGAT 列表"
RULES=$(grep -c "^0\.0\.0\.0" "$NEW_FILE" 2>/dev/null)
[ "$RULES" -gt 10000 ] || fail "规则数太少（${RULES} 条），疑似不完整"
# 每条数据行的 IP 只能是本地/拦截/组播地址（注意文件里有缩进的注释行，
# 要先跳过行首空白后的 #）；出现别的 IP 就是被劫持过的列表，直接不要。
# 允许整段 127.x.x.x 和 ::1/::2/::3：GGAT 列表里本地回环不止 127.0.0.1。
BAD_IP=$(awk '/^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next} {if ($1 !~ /^(0\.0\.0\.0|127\.[0-9]+\.[0-9]+\.[0-9]+|::1|::2|::3|255\.255\.255\.255|fe80::1%lo0|ff00::0|ff02::1|ff02::2|ff02::3)$/) print $1}' "$NEW_FILE" 2>/dev/null | head -n 1)
[ -z "$BAD_IP" ] || fail "列表里有可疑 IP（${BAD_IP}），拒绝使用"

# 6. 备份 + 替换 + 另存一份防模块更新盖掉
[ -f "$MODPATH/hosts" ] && cp -f "$MODPATH/hosts" "$BAK_FILE" 2>/dev/null
mv -f "$NEW_FILE" "$MODPATH/hosts" 2>/dev/null || fail "替换 hosts 文件失败"
chmod 644 "$MODPATH/hosts" 2>/dev/null
cp -f "$MODPATH/hosts" "$MODPATH/hosts.saved" 2>/dev/null

# 7. 重新生成有效文件（奖励开关开着时，这里去掉奖励域名；
# 开关关着时，有效文件就是新列表本身）
sh "$MODPATH/gen_effective_hosts.sh" 2>/dev/null
EFFECTIVE="$MODPATH/hosts.effective"
[ -f "$EFFECTIVE" ] || EFFECTIVE="$MODPATH/hosts"

# 8. 重新挂载（如果去广告正开着：bind 挂载的是旧文件的 inode，
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
    mount --bind "$EFFECTIVE" "$SYS_HOSTS" 2>/dev/null
    if command -v md5sum >/dev/null 2>&1; then
        a=$(md5sum "$SYS_HOSTS" 2>/dev/null | awk '{print $1}')
        b=$(md5sum "$EFFECTIVE" 2>/dev/null | awk '{print $1}')
        [ -n "$a" ] && [ "$a" = "$b" ] || fail "替换成功但重新挂载失败，请去广告页点一次应用"
    fi
fi

rm -f "$JSON_FILE" "$ZIP_FILE" "$RAW_FILE" 2>/dev/null
logmsg " [+] hosts 列表已更新到 $VERSION（$RULES 条规则），旧列表已备份到 hosts.bak"
echo "OK|$VERSION|$RULES"
exit 0

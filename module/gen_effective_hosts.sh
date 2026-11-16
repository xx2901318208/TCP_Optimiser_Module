#!/system/bin/sh
# 生成真正要挂载的 hosts 文件（hosts.effective）。
# 广告奖励开关开着（adblock_reward 标记存在）时，从 hosts 里去掉
# reward_domains 列出的域名——这些域名不拦，奖励广告才能正常领；
# 开关关着时，有效文件就是 hosts 本身。
# update_hosts.sh（换新列表后）和 service.sh（每次应用去广告设置时）
# 都会调它，两边用的永远是同一份有效文件。
# 用法：sh gen_effective_hosts.sh（不读参数，只看标记文件）。
MODPATH="${0%/*}"
HOSTS="$MODPATH/hosts"
EFFECTIVE="$MODPATH/hosts.effective"
REWARD="$MODPATH/reward_domains"
TMP_FILE="$MODPATH/hosts.effective.tmp"

[ -f "$HOSTS" ] || exit 0
if [ -f "$MODPATH/adblock_reward" ] && [ -s "$REWARD" ]; then
    # 只删域名正好在奖励列表里的那一行（比 $2，忽略大小写）；
    # 注释、空行和别的域名原样保留。
    awk 'NR==FNR { r[tolower($1)]=1; next } /^[[:space:]]*#/ {print; next} /^[[:space:]]*$/ {print; next} { if (tolower($2) in r) next; print }' "$REWARD" "$HOSTS" > "$TMP_FILE" 2>/dev/null \
        && mv -f "$TMP_FILE" "$EFFECTIVE" 2>/dev/null
else
    cp -f "$HOSTS" "$EFFECTIVE" 2>/dev/null
fi
chmod 644 "$EFFECTIVE" 2>/dev/null
exit 0

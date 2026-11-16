#!/system/bin/sh
# strip-hosts.sh — 从 hosts 文件里去掉跳转条目，只留下拦广告的条目。
# 用法：sh strip-hosts.sh <输入 hosts> <输出 hosts>
# 留下：注释行、空行，以及第一列是拦截地址的数据行
# （0.0.0.0、127.x.x.x 本地回环、::1/::2/::3）。
# 去掉：第一列是别的真实 IP 的数据行——这些是跳转/加速条目
# （比如小米 OTA、谷歌推送的固定 IP），hosts 文件只该拦、不该跳转。
# 这条规则是通用的：以后上游再加新的跳转条目，也一样会被去掉。
# update_hosts.sh 从上游拉到新列表后调它；它只管筛，不做别的。
set -eu
[ "$#" = "2" ] || { echo "用法：strip-hosts.sh <输入 hosts> <输出 hosts>" >&2; exit 2; }
IN="$1"
OUT="$2"
[ -f "$IN" ] || { echo "输入文件不存在：$IN" >&2; exit 2; }
awk '
/^[[:space:]]*#/ { print; next }
/^[[:space:]]*$/ { print; next }
{
    ip = $1
    if (ip == "0.0.0.0" || ip ~ /^127\./ || ip == "::1" || ip == "::2" || ip == "::3") print
    # 别的 IP 都是跳转条目，直接去掉
}
' "$IN" > "$OUT"

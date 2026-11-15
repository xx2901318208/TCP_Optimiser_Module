#!/system/bin/sh
# 检查一个 Private DNS 解析器的 DoT 端口（853）是否连得上。
# 去广告页点“应用”和 service.sh 写 Private DNS 设置之前调用。
# 退出码：0=连得上，1=连不上，2=无法检查（本机没有 curl）。
# 方法：curl 对 853 端口做一次 HTTPS 请求。DoT 不是 HTTP，所以
# 握手成功后 HTTP 交换一定失败（52/56）；只认“解析失败/连不上/
# 超时/TLS 握手失败”这几种码当连不上。
# 注意：这是个启发式判断（各家对 853 的拦截方式不同，真机验证才
# 算数）；service.sh 的 dns_applied/删标记逻辑仍是兜底。
HOST="$1"
[ -n "$HOST" ] || exit 2
command -v curl >/dev/null 2>&1 || exit 2
curl -s --max-time 4 -o /dev/null "https://$HOST:853/" 2>/dev/null
rc=$?
case "$rc" in
    6|7|28|35) exit 1 ;;
    *) exit 0 ;;
esac

# K-network
一个 Magisk/KernelSU 模块，根据当前活跃的网络类型自动切换 TCP 拥塞控制算法，并提供一些网络增强功能。

**原项目**: [fatalcoder524/TCP_Optimiser_Module](https://github.com/fatalcoder524/TCP_Optimiser_Module)

**二改汉化**: 酷安 @R1263599071

**改名说明（2026-11-15，v4.18）**：模块从 TCP_Optimiser_Module 改名 K-network，模块 id 从 `tcp_optimiser` 改成 `k-network`。装 4.18 时会自动把老模块的开关设置（去广告、Private DNS、Wi-Fi 7、initcwnd 等）搬过来并删掉老模块，重启一次即可；仓库名和下载链接不变。

# 为什么？
在某些内核中，TCP 拥塞控制算法 BBR 可能已经启用。或者你想根据使用的接口启用特定的算法或设置。我观察到在我的内核中，当我在 Wi-Fi 上使用 BBR 时，上传速度比 cubic 快 50-60 Mbps，但 BBR 在蜂窝网络上上传速度较差。所以我设计了这个模块，根据活跃的网络接口自动切换。

# 功能
1. 根据接口（Wi-Fi/蜂窝数据）设置 TCP 拥塞控制算法。
2. 接口切换时自动更改 TCP 拥塞控制算法。
3. 将 initcwnd 和 initrwnd 值设置为最大值（两个值可在 WebUI 设置页调，默认 10 / 20）。
4. **网络质量检测**：只测只记（延迟/抖动写进日志），不再据此改任何 sysctl。
5. **Android 17 实测**：内核 6.6.118-android15-8 上可用算法只有 reno/bbr/cubic（无 bbr3），默认 qdisc fq_codel，无 MPTCP；MPTCP 明确不启用。

# 实测环境（2026-11-13）
- 内核：`6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k`，Android 17
- `tcp_available_congestion_control`：`reno bbr cubic`
- 当前算法：`bbr`，`default_qdisc`：`fq_codel`
- 不存在：`tcp_priority`、`tcp_mptcp`、`tcp_mem_pressure`、`tcp_congestion_control_algo`、`tcp_thin_dupack`、`net.mptcp.*`；PLB 在 6.6 上叫 `tcp_plb_idle_rehash_rounds` / `tcp_plb_rehash_rounds`
6. **智能参数调整**：根据 Wi-Fi 频段自动调整 TCP pacing 参数。
7. **系统信息记录**：启动时记录系统信息，便于调试。
8. **代码优化**：集中管理网络配置，减少代码重复。
9. **Wi-Fi 6GHz / Wi-Fi 7 解锁**：设置页开关（默认关闭），改高通驱动配置并强制 AU 国家码，解锁思路来自公开的 AndroPlus magisk-module-wifi7，脚本为本模块重新编写；只做高通机型，KernelSU 下重启两次生效。

# 如何使用
1. 安装模块。
2. 模块会在模块文件夹中创建 2 个文件：`wlan_{algo}_{qdisc}` 和 `rmnet_data_{algo}_{qdisc}`。
3. 重启设备。
4. 模块的基本功能会在开机时正常运行。

# 通过文件调整模块设置 [/data/adb/modules/k-network]
1. 通过编辑文件名中的 `{algo}` 部分来更改给定接口的 TCP 拥塞控制算法。Wi-Fi 使用 `wlan_{algo}_{qdisc}`，蜂窝数据使用 `rmnet_data_{algo}_qdisc`。
2. 通过编辑文件名中的 `{qdisc}` 部分来更改给定接口的队列调度规则。Wi-Fi 使用 `wlan_{algo}_{qdisc}`，蜂窝数据使用 `rmnet_data_{algo}_qdisc`。
3. 创建一个名为 `initcwnd_initrwnd` 的空文件，将 initcwnd 和 initrwnd 值设置为最大值。两个值可在 WebUI 设置页调（数字框，1–100，默认 10 / 20）；也可以直接写文件：`initcwnd_value` 和 `initrwnd_value` 里各放一个数字。initcwnd 是 TCP 连接一开始不用等确认就能发多少个包，initrwnd 是对方一开始能发多少个包——值越大，新连接起步越快（打开网页、加载图片少等几轮），但突发流量也越大，弱网或拥堵时更容易丢包重传；Wi-Fi 好时可适当调大，蜂窝弱信号时建议调小。
4. 创建一个名为 `kill_connections` 的空文件，在切换时断开所有连接。[请小心！]
5. 创建一个名为 `force_apply` 的空文件，立即应用更改。
6. 创建一个名为 `wifi_powersave_off` 的空文件，在连 Wi-Fi 时关闭 Wi-Fi 省电（降低游戏/语音的空闲唤醒延迟，但更费电；也可以在 WebUI 设置页开关）。
7. Wi-Fi 低延迟模式：创建一个名为 `wifi_low_latency` 的空文件（或在 WebUI 设置页打开开关），模块会在开机、切网、强制应用时调系统低延迟模式（`cmd wifi force-low-latency-mode enabled`），Wi-Fi 固件省电关、后台扫描减少，打游戏和实时语音延迟更低，费电略增；关掉开关时主动写 `disabled`（这个开关重启前一直有效，只停写不会自己关）。做法来自公开的 mazemingw/oplus-network-helper 的 WiFi Turbo（只借了这一行系统命令，TCP 调优仍是本模块自己的）。
7. Private DNS 一键切换（在 WebUI 去广告页下拉框里选，点应用后 5 秒内生效，不用等切网）：创建一个名为 `private_dns_<hostname>` 的空文件，模块会在开机、切网、强制应用时把系统 Private DNS 写成该解析器（和在设置里手填是同一个设置）。连通性预检（4.19）：写之前先测解析器的 853 端口通不通（curl 对 853 做一次握手），不通就不写、记一行日志（去广告页点应用会直接提示“连不上，没应用”），标记留着下次切网再试；本机没有 curl 时跳过预检、直接写。注意预检是启发式判断（各家对 853 的拦截方式不同），删标记逻辑仍是兜底。可选值：`dns.adguard-dns.com`（AdGuard，去广告；国内常被挡——2026-11-15 真机连不上，慎用）、`dns.alidns.com`（阿里，国内快）、`dot.pub`（腾讯 DNSPod，国内快）。不要用 Cloudflare（`one.one.one.one`）和 Google（`dns.google`）——国内基本不通。创建一个名为 `private_dns_default` 的空文件可恢复系统默认（把模式写回 off）。没有标记文件时模块不碰这个设置。注意：Private DNS 是严格模式，解析器连不上时手机会显示无网络；开 VPN 时 VPN 的 DNS 优先。安全说明：三个解析器都是加密传输（DoT），都不劫持不存在的域名；区别在日志——AdGuard 宣称不记日志（境外），阿里/腾讯按国内法律留日志。自定义解析器（如 NextDNS `<你的ID>.dns.nextdns.io`）直接按 `private_dns_<hostname>` 的格式建文件即可。如果解析器连不上、系统弹框里点了关闭，模块会删掉标记（去广告页会诚实显示未启用，不会再自动重开、循环弹框）；想再开，去广告页重新选。
8. 去广告（hosts）：创建一个名为 `adblock_hosts` 的空文件，模块会在开机、切网、强制应用时把自带的 hosts 列表挂载到 /system/etc/hosts（StevenBlack，广告+恶意域名，2026-11-08 版，78215 条规则）；删掉标记文件则卸载恢复原样。也可以在 WebUI 去广告页开关，点应用后 5 秒内生效（不用重启手机；已经打开的应用要等 DNS 缓存过期或重启应用才生效）。注意：不要和 Private DNS 同时开（两者叠加优先级不明确，出了问题难排查；用 hosts 时把 Private DNS 选成“恢复系统默认”或“关闭（不管理）”）。如果装了 AdAway / Systemless Hosts 等其他 hosts 工具，模块会让路、不重复挂载。去广告页有“更新 hosts 列表”按钮：手机直接从 StevenBlack 上游下载最新版，校验通过（必须是 StevenBlack、条目全指到本地地址、文件完整）才替换，失败保留旧列表；替换前旧列表备份到 `hosts.bak`，去广告开着时会重新挂载立即生效。也可以直接替换模块目录下的 `hosts` 文件（需重启或强制应用）。
9. Wi-Fi 6GHz / Wi-Fi 7 解锁：创建一个名为 `wifi7_unlock` 的空文件（或在 WebUI 设置页打开开关），模块会改高通驱动配置 `WCNSS_qcom_cfg.ini`（注释掉 `BandCapability` 限制、开 `enable_11be`）、强制 AU 国家码（`ro.boot.wificountrycode AU` + `iw reg set AU` + `cmd wifi force-country-code`）、开 OPlus 11be 开关（`ro.oplus.wifi.11be_disabled=0`）。只做高通机型（`WCNSS_qcom_cfg.ini`），联发科不在此列；KernelSU 下重启两次才生效，开启后若仍未见 6GHz，开关一次 Wi-Fi 或再重启一次。persist 那份配置改之前先备份到模块目录（`xml/WCNSS_qcom_cfg.ini.persist.bak`），关掉开关时从备份恢复；驱动配置挂载也会卸除。注意：国内 6GHz 未开放，强制 AU 国家码是灰色地带，开关默认关闭，请自行决定。解锁思路来自公开的 AndroPlus magisk-module-wifi7（v10），脚本为本模块重新编写，未直接复制其文件；它的两个 overlay APK 未采用——先以驱动+国家码+OPlus 开关实现，真机验证后再决定是否需要。

# 通过 WebUI 调整模块设置
所有模块设置都可以通过 KSU 和 APatch 的模块 WebUI 或 Magisk 的 KsuWebUIStandalone 应用来控制。

## 注意：
1. 文件名中的 `{algo}` 可以是任何 TCP 拥塞控制算法（cubic、bbr、reno 等）。
2. 文件名中的 `{qdisc}` 可以是任何队列调度规则（fq、fq_codel、pfifo_fast 等）。
3. **蜂窝数据**的默认算法是 **cubic**。
4. **Wi-Fi** 的默认算法是 **bbr**（如果内核支持）。否则使用 **cubic**。
5. 有一个选项可以在算法切换时断开当前 TCP 连接。这会停止正在进行的下载、上传或其他连接，受影响的应用可能需要重启。默认禁用此功能。
6. 算法仅在内核中存在时才会应用。
7. 模块日志位于 `/data/adb/modules/k-network/service.log`。

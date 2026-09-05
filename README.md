# TCP_Optimiser_Module
一个 Magisk/KernelSU 模块，根据当前活跃的网络类型自动切换 TCP 拥塞控制算法，并提供一些网络增强功能。

# 为什么？
在某些内核中，TCP 拥塞控制算法 BBR 可能已经启用。或者你想根据使用的接口启用特定的算法或设置。我观察到在我的内核中，当我在 Wi-Fi 上使用 BBR 时，上传速度比 cubic 快 50-60 Mbps，但 BBR 在蜂窝网络上上传速度较差。所以我设计了这个模块，根据活跃的网络接口自动切换。

# 功能
1. 根据接口（Wi-Fi/蜂窝数据）设置 TCP 拥塞控制算法。
2. 接口切换时自动更改 TCP 拥塞控制算法。
3. 将 initcwnd 和 initrwnd 值设置为最大值。
4. **网络质量检测**：自动检测网络延迟和抖动，根据网络状况优化参数。
5. **Android 17+ 支持**：支持新内核特性（如 MPTCP、TCP 优先级等）。
6. **智能参数调整**：根据 Wi-Fi 频段自动调整 TCP pacing 参数。
7. **系统信息记录**：启动时记录系统信息，便于调试。
8. **代码优化**：集中管理网络配置，减少代码重复。

# 如何使用
1. 安装模块。
2. 模块会在模块文件夹中创建 2 个文件：`wlan_{algo}_{qdisc}` 和 `rmnet_data_{algo}_{qdisc}`。
3. 重启设备。
4. 模块的基本功能会在开机时正常运行。

# 通过文件调整模块设置 [/data/adb/modules/tcp_optimiser]
1. 通过编辑文件名中的 `{algo}` 部分来更改给定接口的 TCP 拥塞控制算法。Wi-Fi 使用 `wlan_{algo}_{qdisc}`，蜂窝数据使用 `rmnet_data_{algo}_qdisc`。
2. 通过编辑文件名中的 `{qdisc}` 部分来更改给定接口的队列调度规则。Wi-Fi 使用 `wlan_{algo}_{qdisc}`，蜂窝数据使用 `rmnet_data_{algo}_qdisc`。
3. 创建一个名为 `initcwnd_initrwnd` 的空文件，将 initcwnd 和 initrwnd 值设置为最大值。
4. 创建一个名为 `kill_connections` 的空文件，在切换时断开所有连接。[请小心！]
5. 创建一个名为 `force_apply` 的空文件，立即应用更改。

# 通过 WebUI 调整模块设置
所有模块设置都可以通过 KSU 和 APatch 的模块 WebUI 或 Magisk 的 KsuWebUIStandalone 应用来控制。

## 注意：
1. 文件名中的 `{algo}` 可以是任何 TCP 拥塞控制算法（cubic、bbr、reno 等）。
2. 文件名中的 `{qdisc}` 可以是任何队列调度规则（fq、fq_codel、pfifo_fast 等）。
3. **蜂窝数据**的默认算法是 **cubic**。
4. **Wi-Fi** 的默认算法是 **bbr**（如果内核支持）。否则使用 **cubic**。
5. 有一个选项可以在算法切换时断开当前 TCP 连接。这会停止正在进行的下载、上传或其他连接，受影响的应用可能需要重启。默认禁用此功能。
6. 算法仅在内核中存在时才会应用。
7. 模块日志位于 `/data/adb/modules/tcp_optimiser/service.log`。

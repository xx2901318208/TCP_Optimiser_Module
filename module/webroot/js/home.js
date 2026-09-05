import { exec, toast } from './kernelsu.js';
import { get_active_iface, get_active_algorithm, get_active_qdisc, getInitcwndInitrwndValue, get_wifi_calling_state, getModuleActiveState } from './common.js';
import router_state from './router.js';

export async function updateModuleStatus () {
	var module_status = "正在加载模块状态...⌛";
	var active_iface = "无";
	var active_iface_type = "未知 ⁉️";
	var active_algorithm = "未知 ⁉️";
	var active_qdisc = "未知 ⁉️";
	var wifi_calling_state = "未知 ⁉️";
	var active_InitcwndInitrwndValue = [];
	try
	{
		module_status = (await getModuleActiveState()) == true ? "已启用 ✅" : "已禁用 ❌";
		active_iface = await get_active_iface();
		active_iface = active_iface ? active_iface : "None";
		active_iface_type = active_iface.match("rmnet") || active_iface.match("ccmni") ? "蜂窝数据 📶" : active_iface.startsWith("wlan") || active_iface.startsWith("tun") ? "Wi-Fi 🛜" : "未知 ⁉️";
		active_algorithm = await get_active_algorithm();
		var active_qdisc_tmp = await get_active_qdisc(active_iface);
		active_qdisc = active_qdisc_tmp ? active_qdisc_tmp : active_qdisc;
		active_InitcwndInitrwndValue = await getInitcwndInitrwndValue();
		if(active_iface_type == "Wi-Fi 🛜")
		{
			wifi_calling_state = await get_wifi_calling_state() ? "活跃 ": "未活跃 ";
		}
	} catch (error) {
		console.error('Error updating status: ', error);
		addLog('更新状态出错。');
		toast("更新状态出错。");
	} finally {
		router_state.homePageParams.module_status = module_status;
		router_state.homePageParams.active_iface_type = active_iface_type;
		router_state.homePageParams.active_iface = active_iface;
		router_state.homePageParams.active_algorithm = active_algorithm;
		router_state.homePageParams.active_qdisc = active_qdisc;
		router_state.homePageParams.active_InitcwndInitrwndValue = active_InitcwndInitrwndValue;
		router_state.homePageParams.wifi_calling_state = wifi_calling_state;
	}
}

export function updateHomeUI () {
	if (router_state.isInitializing == false) {
		document.getElementById('module_status_value').textContent = router_state.homePageParams.module_status;
		if(router_state.homePageParams.module_status == "已启用 ✅")
		{
			const ifaceTypeDiv = document.getElementById('active_iface_type_div');
			const ifaceValDiv = document.getElementById('active_iface_div');
			const tcpCongValDiv = document.getElementById('tcp_cong_div');
			const qdiscValDiv = document.getElementById('qdisc_div');
			
			document.getElementById('active_iface_type_value').textContent = router_state.homePageParams.active_iface_type;
			document.getElementById('active_iface_value').textContent = router_state.homePageParams.active_iface;
			document.getElementById('tcp_cong_value').textContent = router_state.homePageParams.active_algorithm;
			document.getElementById('qdisc_value').textContent = router_state.homePageParams.active_qdisc;
			
			if (ifaceTypeDiv?.classList.contains('hidden'))
					ifaceTypeDiv.classList.remove('hidden');
			
			if (ifaceValDiv?.classList.contains('hidden'))
					ifaceValDiv.classList.remove('hidden');
			
			if (tcpCongValDiv?.classList.contains('hidden'))
					tcpCongValDiv.classList.remove('hidden');
				
			if (qdiscValDiv?.classList.contains('hidden'))
					qdiscValDiv.classList.remove('hidden');
			
			const wifiCallingDiv = document.getElementById('wifi_calling_value_div');
			const wifiCallingSpan = document.getElementById('wifi_calling_value');
			
			if(router_state.homePageParams.active_iface_type == "Wi-Fi 🛜")
			{
				if (wifiCallingDiv?.classList.contains('hidden'))
					wifiCallingDiv.classList.remove('hidden');
				
				wifiCallingSpan.textContent = router_state.homePageParams.wifi_calling_state;
			}
			else
			{
				if (wifiCallingDiv.classList.contains('hidden'))
					wifiCallingDiv.classList.add('hidden');
				wifiCallingSpan.textContent = "未知 ⁉️";
			}
			
			const initcwndDiv = document.getElementById('initcwnd_value_div');
			const initrwndDiv = document.getElementById('initrwnd_value_div');
			const initcwndSpan = document.getElementById('initcwnd_value');
			const initrwndSpan = document.getElementById('initrwnd_value');
			
			const values = router_state.homePageParams.active_InitcwndInitrwndValue;
			const isLoading = values.length < 2 && router_state.settingsPageParams.initcwndInitrwnd;
			
			if(values.length == 2 || isLoading)
			{
				if (initcwndDiv?.classList.contains('hidden'))
					initcwndDiv.classList.remove('hidden');
				
				if (initrwndDiv?.classList.contains('hidden'))
					initrwndDiv.classList.remove('hidden');
				
				initcwndSpan.textContent = values.length == 2 ? values[0] : "正在加载 initcwnd 值...";
				initrwndSpan.textContent = values.length == 2 ? values[1] : "正在加载 initrwnd 值...";
			}
			else
			{
				// No data and not loading → hide the section
				if (initcwndDiv && !initcwndDiv.classList.contains('hidden'))
					initcwndDiv.classList.add('hidden');
				
				if (initrwndDiv && !initrwndDiv.classList.contains('hidden'))
					initrwndDiv.classList.add('hidden');
			}
		}
	}
}

export async function initHome() {
	router_state.isInitializing = false;
	updateHomeUI();
	// 加载网络质量信息
	loadNetworkQualityInfo();
}

async function loadNetworkQualityInfo() {
	try {
		// 获取 Android 版本
		const { stdout: androidVersion } = await exec('getprop ro.build.version.release');
		document.getElementById('android_version_value').textContent = androidVersion || '未知';
		document.getElementById('android_version_div').classList.remove('hidden');

		// 获取内核版本
		const { stdout: kernelVersion } = await exec('uname -r');
		document.getElementById('kernel_version_value').textContent = kernelVersion || '未知';
		document.getElementById('kernel_version_div').classList.remove('hidden');

		// 检测网络延迟
		const { stdout: pingResult } = await exec('ping -c 1 -W 1 8.8.8.8 2>/dev/null | grep "time="');
		if (pingResult) {
			const latency = pingResult.match(/time=(\d+\.?\d*)/);
			if (latency) {
				document.getElementById('network_latency_value').textContent = `${latency[1]} ms`;
				document.getElementById('network_latency_div').classList.remove('hidden');
			}
		}

		// 检测网络抖动
		const { stdout: jitterResult } = await exec('ping -c 5 -W 1 8.8.8.8 2>/dev/null | grep "time="');
		if (jitterResult) {
			const times = jitterResult.match(/time=(\d+\.?\d*)/g);
			if (times && times.length >= 2) {
				const values = times.map(t => parseFloat(t.split('=')[1]));
				const jitter = Math.max(...values) - Math.min(...values);
				document.getElementById('network_jitter_value').textContent = `${jitter.toFixed(1)} ms`;
				document.getElementById('network_jitter_div').classList.remove('hidden');
			}
		}
	} catch (error) {
		console.error('加载网络质量信息失败:', error);
	}
}

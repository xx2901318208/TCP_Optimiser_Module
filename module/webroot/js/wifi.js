import { exec, toast } from './kernelsu.js';
import router_state from './router.js';
import { addLog } from './logs.js';
import { fetchModuleDirListing } from './common.js';

export async function initWifi() {
	const wifiPowersaveOff = document.getElementById('wifi-powersave-off');
	const wifiLowLatency = document.getElementById('wifi-low-latency');
	const wifiHiPerf = document.getElementById('wifi-hi-perf');
	const wifi7Unlock = document.getElementById('wifi7-unlock');
	const applyBtn = document.getElementById('wifi-apply');
	const forceApplyBtn = document.getElementById('wifi-force-apply');

	// 打开 WiFi 页只跑 1 个 shell 命令：一次 ls 拿回目录列表，
	// 4 个开关的当前值全从这一次 ls 里本地推导，不再每个各跑一次 shell。
	const listing = await fetchModuleDirListing();

	if(router_state.wifiPageParams.wifiPowersaveOff == null)
		router_state.wifiPageParams.wifiPowersaveOff = listing.includes("wifi_powersave_off");

	if(router_state.wifiPageParams.wifiLowLatency == null)
		router_state.wifiPageParams.wifiLowLatency = listing.includes("wifi_low_latency");

	if(router_state.wifiPageParams.wifiHiPerf == null)
		router_state.wifiPageParams.wifiHiPerf = listing.includes("wifi_hi_perf");

	if(router_state.wifiPageParams.wifi7Unlock == null)
		router_state.wifiPageParams.wifi7Unlock = listing.includes("wifi7_unlock");

	wifiPowersaveOff.checked = router_state.wifiPageParams.wifiPowersaveOff;
	wifiLowLatency.checked = router_state.wifiPageParams.wifiLowLatency;
	wifiHiPerf.checked = router_state.wifiPageParams.wifiHiPerf;
	wifi7Unlock.checked = router_state.wifiPageParams.wifi7Unlock;

	// 高性能和低延迟只能开一个（原项目 UI 也是互斥的；高性能里已经包含低延迟）
	wifiHiPerf.addEventListener('change', () => { if(wifiHiPerf.checked) wifiLowLatency.checked = false; });
	wifiLowLatency.addEventListener('change', () => { if(wifiLowLatency.checked) wifiHiPerf.checked = false; });
	if(wifiHiPerf.checked) wifiLowLatency.checked = false;

	async function applyWifiSettings() {
		const settings = {
			wifiPowersaveOff: wifiPowersaveOff.checked,
			wifiLowLatency: wifiLowLatency.checked,
			wifiHiPerf: wifiHiPerf.checked,
			wifi7Unlock: wifi7Unlock.checked,
		};

		try
		{
			// 合并成两条命令：一条删旧标记，一条写新标记。
			const dir = router_state.moduleInformation.moduleDir;
			await exec(`rm -f ${dir}/wifi_powersave_off ${dir}/wifi_low_latency ${dir}/wifi_hi_perf ${dir}/wifi7_unlock`);

			const touches = [];
			if(settings.wifiPowersaveOff)
				touches.push(`touch ${dir}/wifi_powersave_off && chmod 644 ${dir}/wifi_powersave_off`);

			if(settings.wifiLowLatency)
				touches.push(`touch ${dir}/wifi_low_latency && chmod 644 ${dir}/wifi_low_latency`);

			if(settings.wifiHiPerf)
				touches.push(`touch ${dir}/wifi_hi_perf && chmod 644 ${dir}/wifi_hi_perf`);

			if(settings.wifi7Unlock)
				touches.push(`touch ${dir}/wifi7_unlock && chmod 644 ${dir}/wifi7_unlock`);

			// wifi7 开关变了就顺手 force_apply，让 service.sh 5 秒内就处理
			// （挂载/卸除），不用等下次切网
			if(settings.wifi7Unlock !== router_state.wifiPageParams.wifi7Unlock)
				touches.push(`touch ${dir}/force_apply && chmod 644 ${dir}/force_apply`);

			// 低延迟开关变了同样 force_apply，5 秒内就写进系统
			if(settings.wifiLowLatency !== router_state.wifiPageParams.wifiLowLatency)
				touches.push(`touch ${dir}/force_apply && chmod 644 ${dir}/force_apply`);

			// 高性能开关变了同样 force_apply，5 秒内就写进系统
			if(settings.wifiHiPerf !== router_state.wifiPageParams.wifiHiPerf)
				touches.push(`touch ${dir}/force_apply && chmod 644 ${dir}/force_apply`);

			if(touches.length > 0)
				await exec(touches.join(' ; '));

			console.log('Applied WiFi settings:', settings);

		router_state.wifiPageParams.wifiPowersaveOff = settings.wifiPowersaveOff;
		router_state.wifiPageParams.wifiLowLatency = settings.wifiLowLatency;
		router_state.wifiPageParams.wifiHiPerf = settings.wifiHiPerf;
		router_state.wifiPageParams.wifi7Unlock = settings.wifi7Unlock;
		toast("设置已成功应用！");
		addLog(`应用 WiFi 设置: wifi_powersave_off=${settings.wifiPowersaveOff}, wifi_low_latency=${settings.wifiLowLatency}, wifi_hi_perf=${settings.wifiHiPerf}, wifi7_unlock=${settings.wifi7Unlock}`);
		return 0;
	} catch (error) {
		console.error('Error applying WiFi settings:', error);
		toast("应用设置出错。");
		return 1;
	}
	}

	applyBtn.addEventListener('click', async () => {
		var res = await applyWifiSettings();
		if(res == 0)
			toast("请关闭并重新打开连接以应用设置。");
	});

	forceApplyBtn.addEventListener('click', async () => {
		var res = await applyWifiSettings();
		if(res == 0)
		{
			const { errno: output } = await exec(`touch ${router_state.moduleInformation.moduleDir}/force_apply && chmod 644 ${router_state.moduleInformation.moduleDir}/force_apply`);
			if(output == 0)
				toast("请等待 5 秒以生效更改！");
		}
	});

	router_state.isInitializing = false;
}

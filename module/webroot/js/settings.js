import { exec, toast } from './kernelsu.js';
import router_state from './router.js';
import { addLog } from './logs.js';
import { fetchModuleDirListing } from './common.js';

async function getSelectedQdisc(prefix, listing) {
	try {
		let fileName;
		if (listing) {
			fileName = listing.find(name => name.startsWith(prefix + '_')) || "";
		} else {
			const { stdout: rawFile } = await exec(`ls ${router_state.moduleInformation.moduleDir}/${prefix}_* 2>/dev/null | xargs -n 1 basename | head -n1`);
			fileName = rawFile.trim();
		}
		if (!fileName) return "fifo";
		const stripInterface = fileName.replace(`${prefix}_`, '');
		const qdisc = stripInterface.substring(stripInterface.indexOf('_') + 1);
		switch(prefix)
		{
			case "wlan":
				router_state.settingsPageParams.wlanQdisc = qdisc.trim();
				return router_state.settingsPageParams.wlanQdisc;
				break;
			
			case "rmnet_data":
				router_state.settingsPageParams.rmnetQdisc = qdisc.trim();
				return router_state.settingsPageParams.rmnetQdisc;
				break;
		}
	} catch (error) {
		console.error('Error fetching qdiscs:', error);
		addLog('获取队列调度规则出错');
		toast("获取队列调度规则出错。");
		return null;
	}
}

async function getSelectedAlgorithm(prefix, listing) {
	try {
		let fileName;
		if (listing) {
			fileName = listing.find(name => name.startsWith(prefix + '_')) || "";
		} else {
			const { stdout: rawFile } = await exec(`ls ${router_state.moduleInformation.moduleDir}/${prefix}_* 2>/dev/null | xargs -n 1 basename | head -n1`);
			fileName = rawFile.trim();
		}
		if (!fileName) return "fifo";
		const stripInterface = fileName.replace(`${prefix}_`, '');
		const algo = stripInterface.substring(0, stripInterface.indexOf('_'));
		switch(prefix)
		{
			case "wlan":
				router_state.settingsPageParams.wlanAlgo = algo.trim();
				return router_state.settingsPageParams.wlanAlgo;
				break;
			
			case "rmnet_data":
				router_state.settingsPageParams.rmnetAlgo = algo.trim();
				return router_state.settingsPageParams.rmnetAlgo;
				break;
		}
	} catch (error) {
		console.error('Error fetching algorithm:', error);
		addLog('获取拥塞控制算法出错');
		toast("获取拥塞控制算法出错。");
		return null;
	}
}

async function checkAndGetPrefixValueExists(prefix, type, listing) {
	switch(prefix)
	{
		case "wlan":
			switch(type)
			{
				case "algo":
					return router_state.settingsPageParams.wlanAlgo == null ? await getSelectedAlgorithm(prefix, listing): router_state.settingsPageParams.wlanAlgo;
					break;
				case "qdisc":
					return router_state.settingsPageParams.wlanQdisc == null ? await getSelectedQdisc(prefix, listing): router_state.settingsPageParams.wlanQdisc;
					break;
			}
		break;
		
		case "rmnet_data":
			switch(type)
			{
				case "algo":
					return router_state.settingsPageParams.rmnetAlgo == null ? await getSelectedAlgorithm(prefix, listing): router_state.settingsPageParams.rmnetAlgo;
					break;
				case "qdisc":
					return router_state.settingsPageParams.rmnetQdisc == null ? await getSelectedQdisc(prefix, listing): router_state.settingsPageParams.rmnetQdisc;
					break;
			}
			break;
	}
}

async function populateDropdown(dropdown, options, prefix, type, listing) {
	// 先等当前值回来再清选项：之前先清空再等，等待期间下拉框是空的，
	// 看起来像坏了。原来的“正在加载选项”占位就一直留到值回来。
	var value = await checkAndGetPrefixValueExists(prefix, type, listing);
	dropdown.innerHTML = '';

	var valueExists = false;
  
	options.forEach(option => {
		const optionElement = document.createElement('option');
		optionElement.textContent = optionElement.value = option;
		dropdown.appendChild(optionElement);
		valueExists = (value == option) ? true: valueExists;
	});

	switch(type)
	{
		case "algo":
			dropdown.value = valueExists ? value : "cubic";
			break;
		case "qdisc":
			dropdown.value = valueExists ? value : "fifo";
			break;
	}
}

const fetchAvailableAlgorithms = async (force = false) => {
	try {
		if(router_state.available_algorithms.length == 0 || force)
		{
			const { stdout: output } = await exec('cat /proc/sys/net/ipv4/tcp_available_congestion_control');
			if (output) {
				// Split by whitespace and convert each into an object
				router_state.available_algorithms = output.trim().split(/\s+/).map(algo => algo);
			} else {
				addLog('获取拥塞控制算法失败');
				toast("未找到拥塞控制算法。");
			}
		}
		
	} catch (error) {
		console.error('Error fetching algorithms:', error);
		addLog('获取拥塞控制算法出错');
		toast("获取拥塞控制算法出错。");
	}
};

const fetchAvailableQdiscs = async (force = false) => {
	try {
		if (router_state.available_qdiscs.length === 0 || force) {
			const { stdout: output } = await exec('zcat /proc/config.gz | grep "CONFIG_NET_SCH_"');
			if (output) {
				const qdiscs = [];
				output.split('\n').forEach(line => {
					const match = line.match(/^CONFIG_NET_SCH_([A-Z0-9_]+)=y$/);
					if (match) {
						const qdiscName = match[1];
						if (qdiscName !== "INGRESS" && qdiscName !== "NETEM")
						{
							if(qdiscName === "FIFO")
							{
								qdiscs.push("pfifo");
								qdiscs.push("bfifo");
								qdiscs.push("pfifo_head_drop");
							}
							else
							{
								qdiscs.push(qdiscName.toLowerCase());
							}
						}
					}
				});

				if (!qdiscs.includes("pfifo_fast")) {
					qdiscs.push("pfifo_fast");
				}
				router_state.available_qdiscs = qdiscs;
			} else {
				// /proc/config.gz 读不到（有些内核没开 IKCONFIG_PROC）时给一份
				// 常见内置队列兜底，不然下拉框是空的、没法选
				router_state.available_qdiscs = ["fq_codel", "fq", "pfifo_fast", "htb", "noqueue"];
				addLog('读取内核队列配置失败，使用内置队列列表');
			}
		}
		
	} catch (error) {
		console.error('Error fetching queuing disciplines:', error);
		addLog('获取队列调度规则出错');
		toast("获取队列调度规则出错。");
	}
};

export async function initSettings() {
	const wifiAlgo = document.getElementById('wifi-algo');
	const wifiQdisc = document.getElementById('wifi-qdisc');
	const cellularAlgo = document.getElementById('cellular-algo');
	const cellularQdisc = document.getElementById('cellular-qdisc');
	const killConnections = document.getElementById('kill-connections');
	const initcwndInitrwnd = document.getElementById('initcwnd-initrwnd');
	const wifiPowersaveOff = document.getElementById('wifi-powersave-off');
	const applyBtn = document.getElementById('apply');
	const forceApplyBtn = document.getElementById('force-apply');
	
	// 打开设置页一共只跑 3 个 shell 命令：一次 ls 拿回目录列表、
	// 读可用算法、读可用队列。3 个标记文件和 4 个下拉框的当前值
	// 全从这一次 ls 里本地推导，不再每个各跑一次 shell。
	// （之前是 9 个串行命令；4.11 改成并行也没用——真正慢的是排在
	// 前面的 dumpsys 和 ping 占着 exec 通道，见 common.js 的状态文件。）
	const [listing] = await Promise.all([
		fetchModuleDirListing(),
		(async () => { if(router_state.available_algorithms.length == 0) await fetchAvailableAlgorithms(); })(),
		(async () => { if(router_state.available_qdiscs.length == 0) await fetchAvailableQdiscs(); })(),
	]);

	if(router_state.settingsPageParams.killConnections == null)
		router_state.settingsPageParams.killConnections = listing.includes("kill_connections");

	if(router_state.settingsPageParams.initcwndInitrwnd == null)
		router_state.settingsPageParams.initcwndInitrwnd = listing.includes("initcwnd_initrwnd");

	if(router_state.settingsPageParams.wifiPowersaveOff == null)
		router_state.settingsPageParams.wifiPowersaveOff = listing.includes("wifi_powersave_off");

	await Promise.all([
		populateDropdown(wifiAlgo, router_state.available_algorithms, "wlan", "algo", listing),
		populateDropdown(wifiQdisc, router_state.available_qdiscs, "wlan", "qdisc", listing),
		populateDropdown(cellularAlgo, router_state.available_algorithms, "rmnet_data", "algo", listing),
		populateDropdown(cellularQdisc, router_state.available_qdiscs, "rmnet_data", "qdisc", listing),
	]);
	killConnections.checked =  router_state.settingsPageParams.killConnections;
	initcwndInitrwnd.checked = router_state.settingsPageParams.initcwndInitrwnd;
	wifiPowersaveOff.checked = router_state.settingsPageParams.wifiPowersaveOff;

	async function applySettings() {
		const settings = {
			wifiAlgorithm: wifiAlgo.value,
			wifiQdisc: wifiQdisc.value,
			cellularAlgorithm: cellularAlgo.value,
			cellularQdisc: cellularQdisc.value,
			killOnChange: killConnections.checked,
			setInitcwndInitrwndOnChange: initcwndInitrwnd.checked,
			wifiPowersaveOff: wifiPowersaveOff.checked,
		};
		
		try
		{
			// 原先这里十几个 shell 命令一个接一个等，点应用也要卡几秒。
			// 合并成两条命令：一条删旧标记，一条写新标记。
			const dir = router_state.moduleInformation.moduleDir;
			await exec(`rm -f ${dir}/wlan_* ${dir}/rmnet_data_* ${dir}/kill_connections ${dir}/initcwnd_initrwnd ${dir}/wifi_powersave_off`);

			const touches = [];
			touches.push(`touch ${dir}/wlan_${settings.wifiAlgorithm}_${settings.wifiQdisc} && chmod 644 ${dir}/wlan_${settings.wifiAlgorithm}_${settings.wifiQdisc}`);
			touches.push(`touch ${dir}/rmnet_data_${settings.cellularAlgorithm}_${settings.cellularQdisc} && chmod 644 ${dir}/rmnet_data_${settings.cellularAlgorithm}_${settings.cellularQdisc}`);
			if(settings.killOnChange)
				touches.push(`touch ${dir}/kill_connections && chmod 644 ${dir}/kill_connections`);

			if(settings.setInitcwndInitrwndOnChange)
				touches.push(`touch ${dir}/initcwnd_initrwnd && chmod 644 ${dir}/initcwnd_initrwnd`);

			if(settings.wifiPowersaveOff)
				touches.push(`touch ${dir}/wifi_powersave_off && chmod 644 ${dir}/wifi_powersave_off`);

			if(touches.length > 0)
				await exec(touches.join(' ; '));

			console.log('Applied settings:', settings);
		
		router_state.settingsPageParams.wifiAlgo = settings.wifiAlgorithm;
		router_state.settingsPageParams.wlanQdisc = settings.wifiQdisc;
		router_state.settingsPageParams.rmnetAlgo = settings.cellularAlgorithm;
		router_state.settingsPageParams.rmnetQdisc = settings.cellularQdisc;
		router_state.settingsPageParams.killConnections = settings.killOnChange;
		router_state.settingsPageParams.initcwndInitrwnd = settings.setInitcwndInitrwndOnChange;
		router_state.settingsPageParams.wifiPowersaveOff = settings.wifiPowersaveOff;
		toast("设置已成功应用！");
		addLog(`应用设置: WiFi=${settings.wifiAlgorithm}, WiFi_qdisc=${settings.wifiQdisc}, Cellular=${settings.cellularAlgorithm}, Cellular_qdisc=${settings.cellularQdisc}, Kill=${settings.killOnChange}, initcwnd_initrwnd=${settings.setInitcwndInitrwndOnChange}, wifi_powersave_off=${settings.wifiPowersaveOff}`);
		return 0;
	} catch (error) {
		console.error('Error applying settings:', error);
		toast("应用设置出错。");
		return 1;
	}
	}

	applyBtn.addEventListener('click', async () => {
		var res = await applySettings();
		if(res == 0)
			toast("请关闭并重新打开连接以应用设置。");
	});
	
	forceApplyBtn.addEventListener('click', async () => {
		var res = await applySettings();
		if(res == 0)
		{
			const { errno: output } = await exec(`touch ${router_state.moduleInformation.moduleDir}/force_apply && chmod 644 ${router_state.moduleInformation.moduleDir}/force_apply`);
			if(output == 0)
				toast("请等待 5 秒以生效更改！");
		}
	});
	
	
	document.querySelectorAll('.collapsible-header').forEach(header => {
	  const content = header.nextElementSibling;
	  const arrow = header.querySelector('.arrow');

	  // Set initial state
	  content.classList.add('collapsed');
	  // header.classList.add('active'); // Optional: open first by default

	  header.addEventListener('click', () => {
		const isCollapsed = content.classList.contains('collapsed');
		
		// Toggle collapsed state
		if (isCollapsed) {
		  content.style.maxHeight = content.scrollHeight + "px";
		  header.classList.add('active');
		} else {
		  content.style.maxHeight = "0";
		  header.classList.remove('active');
		}

		content.classList.toggle('collapsed');
		arrow.classList.toggle('rotated');
	  });
	});
	
	router_state.isInitializing = false;
}

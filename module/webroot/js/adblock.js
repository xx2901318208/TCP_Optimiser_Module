import { exec, toast } from './kernelsu.js';
import router_state from './router.js';
import { addLog } from './logs.js';
import { fetchIsConfigFile, fetchPrivateDnsMarker, get_hosts_block_state, get_hosts_list_info, get_private_dns_state } from './common.js';

const PRIVATE_DNS_OPTIONS = [
	{ value: "off", label: "关闭（不管理）" },
	{ value: "default", label: "恢复系统默认" },
	{ value: "dns.adguard-dns.com", label: "AdGuard（去广告）" },
	{ value: "dns.alidns.com", label: "阿里 DNS（国内快）" },
	{ value: "dot.pub", label: "腾讯 DNSPod（国内快）" },
];

async function fetchHostsTier() {
	// 读 hosts_tier 文件（内容是 stevenblack 或 oisd）；没有/读不到/写错了就用标准档
	try {
		const dir = router_state.moduleInformation.moduleDir;
		const { stdout } = await exec(`cat "${dir}/hosts_tier" 2>/dev/null`);
		const tier = (stdout || '').trim();
		return (tier === 'oisd' || tier === 'stevenblack') ? tier : 'stevenblack';
	} catch (error) {
		return 'stevenblack';
	}
}

async function populatePrivateDnsDropdown(dropdown) {
	// 同设置页：先等值回来再清选项，等待期间保留“正在加载选项”占位
	var value = router_state.adblockPageParams.privateDns == null ? await fetchPrivateDnsMarker() : router_state.adblockPageParams.privateDns;
	dropdown.innerHTML = '';

	router_state.adblockPageParams.privateDns = value;
	var valueExists = false;

	PRIVATE_DNS_OPTIONS.forEach(option => {
		const optionElement = document.createElement('option');
		optionElement.textContent = option.label;
		optionElement.value = option.value;
		dropdown.appendChild(optionElement);
		valueExists = (value == option.value) ? true : valueExists;
	});

	// 自定义解析器（标记文件手建的，如 NextDNS）：不在列表里也显示出来，
	// 免得下拉框显示成“关闭”后一点应用就把标记删了
	if (value && value != "off" && !valueExists) {
		const optionElement = document.createElement('option');
		optionElement.textContent = value + "（自定义）";
		optionElement.value = value;
		dropdown.appendChild(optionElement);
		valueExists = true;
	}

	dropdown.value = valueExists ? value : "off";
}

export async function initAdblock() {
	const adblockHosts = document.getElementById('adblock-hosts');
	const privateDns = document.getElementById('private-dns');
	const hostsTier = document.getElementById('hosts-tier');
	const applyBtn = document.getElementById('apply');
	const updateHostsBtn = document.getElementById('update-hosts');
	const updateHostsStatus = document.getElementById('hosts-update-status');

	if(router_state.adblockPageParams.adblockHosts == null)
		router_state.adblockPageParams.adblockHosts = await fetchIsConfigFile("adblock_hosts");

	// 实际生效状态和下拉框一起读：开关只代表“你选了什么”，这里显示
	// 的才是手机上真正生效的——hosts 看挂载，Private DNS 看系统设置。
	await Promise.all([
		refreshAdblockStatus(),
		refreshHostsListInfo(),
		populatePrivateDnsDropdown(privateDns),
	]);
	if (hostsTier) hostsTier.value = await fetchHostsTier();
	adblockHosts.checked = router_state.adblockPageParams.adblockHosts;

	async function applyAdblockSettings() {
		const settings = {
			adblockHosts: adblockHosts.checked,
			privateDns: privateDns.value,
			hostsTier: hostsTier ? hostsTier.value : 'stevenblack',
		};

		try
		{
			// 连通性预检（4.19）：选了解析器先测一下 853 端口通不通，
			// 不通就别写标记（写了也是弹失败框）。检查跑不起来（本机
			// 没有 curl）时直接走老流程，删标记逻辑仍是兜底。
			if (settings.privateDns && settings.privateDns !== "off" && settings.privateDns !== "default") {
				try {
					const dir = router_state.moduleInformation.moduleDir;
					const { errno: checkRc } = await exec(`sh ${dir}/check_dns.sh ${settings.privateDns}`);
					if (checkRc === 1) {
						toast(`${settings.privateDns} 连不上（853 端口不通），没应用。`);
						addLog(`Private DNS 预检失败: ${settings.privateDns} 连不上，没应用`);
						return 1;
					}
				} catch (checkError) {
					console.error('DNS pre-check failed to run, proceeding:', checkError);
				}
			}

			// 和设置页一样：删旧标记、写新标记各合并成一条命令，少等几次 shell。
			const dir = router_state.moduleInformation.moduleDir;
			await exec(`rm -f ${dir}/adblock_hosts ${dir}/private_dns_*`);

			const touches = [];
			if(settings.adblockHosts)
				touches.push(`touch ${dir}/adblock_hosts && chmod 644 ${dir}/adblock_hosts`);

			if(settings.privateDns && settings.privateDns != "off")
				touches.push(`touch ${dir}/private_dns_${settings.privateDns} && chmod 644 ${dir}/private_dns_${settings.privateDns}`);

			if(touches.length > 0)
				await exec(touches.join(' ; '));

			// 档位也写进 hosts_tier 文件（更新按钮和模块更新恢复都认它）；
			// 换档位本身不下载新列表，点“更新 hosts 列表”才下载。
			await exec(`echo "${settings.hostsTier}" > ${dir}/hosts_tier && chmod 644 ${dir}/hosts_tier`);

			console.log('Applied adblock settings:', settings);

			router_state.adblockPageParams.adblockHosts = settings.adblockHosts;
			router_state.adblockPageParams.privateDns = settings.privateDns;
			toast("设置已成功应用！");
			addLog(`应用去广告设置: adblock_hosts=${settings.adblockHosts}, private_dns=${settings.privateDns}, hosts_tier=${settings.hostsTier}`);
			return 0;
		} catch (error) {
			console.error('Error applying adblock settings:', error);
			toast("应用设置出错。");
			return 1;
		}
	}

	// 去广告页的“应用”直接连 force_apply 一起写：hosts 和 Private DNS 不用等
	// 下次切网，5 秒内就生效（设置页的 TCP 选项要下次连接才生效，所以那边
	// 还是两个按钮分开，这里不用分）。
	applyBtn.addEventListener('click', async () => {
		var res = await applyAdblockSettings();
		if(res == 0)
		{
			const { errno: output } = await exec(`touch ${router_state.moduleInformation.moduleDir}/force_apply && chmod 644 ${router_state.moduleInformation.moduleDir}/force_apply`);
			if(output == 0) {
				toast("请等待 5 秒以生效更改！");
				// service.sh 下一轮才真正挂载/写设置，6 秒后再读一次实际状态
				setTimeout(refreshAdblockStatus, 6000);
			}
		}
	});

	// 更新 hosts 列表：手机直接从所选档位的上游下载最新版（标准档是
	// StevenBlack，下下来就是 hosts 格式；更强档是 OISD Big，下下来是
	// Adblock 格式，update_hosts.sh 先校验再转成 hosts 格式），
	// 校验（不是认得的来源 / 有可疑 IP / 不完整就保留旧列表）、备份旧
	// 列表、替换、去广告开着就重新挂载。下载要几秒，期间把按钮锁住，免得重复点。
	if (updateHostsBtn) {
		updateHostsBtn.addEventListener('click', async () => {
			updateHostsBtn.disabled = true;
			if (updateHostsStatus) updateHostsStatus.textContent = '正在从上游下载最新列表…';
			try {
				const dir = router_state.moduleInformation.moduleDir;
				const tier = (hostsTier && hostsTier.value) ? hostsTier.value : 'stevenblack';
				const { stdout } = await exec(`sh ${dir}/update_hosts.sh ${tier}`);
				const firstLine = (stdout || '').trim().split('\n')[0] || '';
				if (firstLine.startsWith('OK|')) {
					const [, date, rules] = firstLine.split('|');
					if (updateHostsStatus) updateHostsStatus.textContent = `已更新到 ${date}（${rules} 条规则），旧列表已备份到 hosts.bak。`;
					addLog(`更新 hosts 列表成功: ${date}, ${rules} 条规则`);
					toast("hosts 列表已更新！");
					await Promise.all([refreshHostsListInfo(), refreshAdblockStatus()]);
				} else if (firstLine.startsWith('FAIL|')) {
					const reason = firstLine.slice(5) || '更新失败';
					if (updateHostsStatus) updateHostsStatus.textContent = `更新失败：${reason}（旧列表还在用）`;
					addLog(`更新 hosts 列表失败: ${reason}`);
					toast("更新失败，旧列表还在用。");
				} else {
					if (updateHostsStatus) updateHostsStatus.textContent = '更新脚本没有返回结果，请看日志。';
					addLog('更新 hosts 列表：脚本无输出');
				}
			} catch (error) {
				console.error('Error updating hosts list:', error);
				if (updateHostsStatus) updateHostsStatus.textContent = '更新出错，请看日志。';
				toast("更新出错。");
			} finally {
				updateHostsBtn.disabled = false;
			}
		});
	}

	router_state.isInitializing = false;
}

// 读两处实际生效状态并显示在页面顶部。hosts 看内容（/system/etc/hosts
// 和模块 hosts 文件 md5 一致就是挂上了，/proc/mounts 认不出文件 bind 挂载），
// Private DNS 只看系统设置——开关选了什么不算数。
async function refreshAdblockStatus() {
	try {
		const [hostsState, dnsState] = await Promise.all([
			get_hosts_block_state(),
			get_private_dns_state(),
		]);

		const hostsEl = document.getElementById('hosts-status');
		if (hostsEl) {
			if (hostsState.status === 'ours') {
				hostsEl.textContent = `已开启（${hostsState.rules} 条规则，正在生效）`;
			} else if (hostsState.status === 'other') {
				hostsEl.textContent = `被其他工具占用（${hostsState.source}），我们的 hosts 没挂上`;
			} else if (hostsState.status === 'error') {
				hostsEl.textContent = '读取失败';
			} else {
				hostsEl.textContent = '未开启';
			}
		}

		const dnsEl = document.getElementById('private-dns-status');
		if (dnsEl) dnsEl.textContent = dnsState;
	} catch (error) {
		console.error('Error refreshing adblock status:', error);
	}
}

// 读模块 hosts 文件的版本（# Date: 头）和规则数，显示在页面顶部。
// 再读 # Title: 头，区分是哪个档位的列表（StevenBlack 还是 OISD Big）。
async function refreshHostsListInfo() {
	try {
		const info = await get_hosts_list_info();
		const infoEl = document.getElementById('hosts-list-info');
		if (!infoEl) return;
		if (info) {
			infoEl.textContent = info.title ? `${info.title}，${info.date}（${info.rules} 条规则）` : `${info.date}（${info.rules} 条规则）`;
		} else {
			infoEl.textContent = '读取失败';
		}
	} catch (error) {
		console.error('Error refreshing hosts list info:', error);
	}
}

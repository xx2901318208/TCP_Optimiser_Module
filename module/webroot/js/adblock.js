import { exec, toast } from './kernelsu.js';
import router_state from './router.js';
import { addLog } from './logs.js';
import { fetchIsConfigFile, fetchPrivateDnsMarker, get_hosts_block_state, get_private_dns_state } from './common.js';

const PRIVATE_DNS_OPTIONS = [
	{ value: "off", label: "关闭（不管理）" },
	{ value: "default", label: "恢复系统默认" },
	{ value: "dns.adguard-dns.com", label: "AdGuard（去广告）" },
	{ value: "dns.alidns.com", label: "阿里 DNS（国内快）" },
	{ value: "dot.pub", label: "腾讯 DNSPod（国内快）" },
];

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
	const applyBtn = document.getElementById('apply');

	if(router_state.adblockPageParams.adblockHosts == null)
		router_state.adblockPageParams.adblockHosts = await fetchIsConfigFile("adblock_hosts");

	// 实际生效状态和下拉框一起读：开关只代表“你选了什么”，这里显示
	// 的才是手机上真正生效的——hosts 看挂载，Private DNS 看系统设置。
	await Promise.all([
		refreshAdblockStatus(),
		populatePrivateDnsDropdown(privateDns),
	]);
	adblockHosts.checked = router_state.adblockPageParams.adblockHosts;

	async function applyAdblockSettings() {
		const settings = {
			adblockHosts: adblockHosts.checked,
			privateDns: privateDns.value,
		};

		try
		{
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

			console.log('Applied adblock settings:', settings);

			router_state.adblockPageParams.adblockHosts = settings.adblockHosts;
			router_state.adblockPageParams.privateDns = settings.privateDns;
			toast("设置已成功应用！");
			addLog(`应用去广告设置: adblock_hosts=${settings.adblockHosts}, private_dns=${settings.privateDns}`);
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

	router_state.isInitializing = false;
}

// 读两处实际生效状态并显示在页面顶部。hosts 只看 /proc/mounts 里的挂载，
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

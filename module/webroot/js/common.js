import { exec, toast, moduleInfo } from './kernelsu.js';
import router_state from './router.js';
import { addLog } from './logs.js';

async function readModuleProp () {
	try {
		const { stdout: details } = await exec(`cat /data/adb/modules/tcp_optimiser/module.prop`);
		const lines = details.trim().split('\n').filter(line => line);
		
		// Convert lines to object
		let moduleInfo = lines.reduce((acc, line) => {
		  const [key, ...rest] = line.split('=');
		  const value = rest.join('=').trim(); // handle values with '=' in them
		  acc[key.trim()] = value;
		  return acc;
		}, {});
		
		moduleInfo["moduleDir"] = `/data/adb/modules/${moduleInfo.id}`;
		return moduleInfo;
	} catch (error) {
		
	}
}

export async function updateModuleInformation () {
	try {
		// 先试管理器的 moduleInfo；解析失败也不炸，直接回落到读文件。
		// 注意最后一定用 readModuleProp 的结果，因为它带 moduleDir，
		// 管理器返回的对象里没有这个字段。
		// 之前这里有个永远为真的判断（对象和 {} 比地址恒不相等），
		// 而版本那几行写在 try 外面：解析一失败 moduleInformation 还是
		// null，后面直接读 .version 就抛错，版本一直停在“正在加载版本…”。
		const parsed = JSON.parse(moduleInfo());
		if (parsed) router_state.moduleInformation = parsed;
	} catch (error) {
		console.error('Error parsing module info:', error);
	}
	router_state.moduleInformation = await readModuleProp();
	if (!router_state.moduleInformation) {
		toast("获取模块信息出错。");
		return;
	}
	var versionStr = router_state.moduleInformation.version ? 'v' + router_state.moduleInformation.version : '';
	var versionCodeStr = router_state.moduleInformation.versionCode ? router_state.moduleInformation.versionCode : '';
	var finalVersionStr = versionStr != '' && versionCodeStr != '' ? `${versionStr} (${versionCodeStr})` : "module.prop 文件可能已损坏！"
	const versionEl = document.getElementById('version');
	if (versionEl) versionEl.textContent = finalVersionStr;
}

export async function getModuleActiveState () {
	try {
		const { stdout: file_exists } = await exec(`ls "/dev/.tcp_module_log_cleared"`);
		return file_exists != "" ? true: false;
	}catch (error) {
		console.error('Error updating module state:', error);
		toast("获取模块状态出错。");
	}
}

export async function get_active_iface () {
	try {
		const { stdout: active_iface } = await exec(`ip route get 192.0.2.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}'`);
		return active_iface.trim()
	} catch (error) {
		console.error('Error fetching active interface: ', error);
		addLog('获取活跃接口出错。');
		toast("获取活跃接口出错。");
		return "error"
	}
};

export async function get_active_algorithm () {
	try {
		const { stdout: active_algo } = await exec(`cat /proc/sys/net/ipv4/tcp_congestion_control`);
		return active_algo.trim()
	} catch (error) {
		console.error('Error fetching active algorithm: ', error);
		addLog('获取活跃算法出错。');
		toast("获取活跃算法出错。");
		return "error"
	}
};

export async function get_active_qdisc(iface) {
	try {
		const moduleInfo = await readModuleProp();
		const tcBin = moduleInfo && moduleInfo.moduleDir ? `${moduleInfo.moduleDir}/bin/tc` : 'tc';
		const { stdout: qdiscRaw } = await exec(`${tcBin} qdisc show dev ${iface} 2>/dev/null`);
		if (qdiscRaw) {
			// Extract the very first word after 'qdisc ' (e.g., 'fq', 'netem', 'fq_codel')
			const match = qdiscRaw.trim().match(/^qdisc\s+(\S+)/);
			if (match && match[1]) {
				return match[1];
			}
		}
		
		return null;
	} catch (error) {
		console.error('Error fetching active qdisc: ', error);
		addLog('获取活跃队列规则出错。');
		toast("获取活跃队列规则出错。");
		return "error";
	}
}

export async function getInitcwndInitrwndValue () {
	try {
		const { stdout: initcwndInitrwndValueOutput } = await exec(`ip route show | grep -o 'initcwnd [0-9]* initrwnd [0-9]*'`);
		const initcwndInitrwndValues = initcwndInitrwndValueOutput.trim().split(/\s+/).filter((_, i) => i % 2 === 1);
		return initcwndInitrwndValues;
	} catch (error) {
		console.error('Error fetching initcwnd/initrwnd value: ', error);
		addLog('获取 initcwnd/initrwnd 值出错。');
		toast("获取 initcwnd/initrwnd 值出错。");
		return [];
	}
};

export async function get_wifi_calling_state() {
  // 首选 service.sh 每轮写的状态文件（cat 一下就行，不用 dumpsys）：
  // 之前这里每 5 秒跑一遍 dumpsys（1-3 秒），还占着 exec 通道，
  // 设置页的下拉框都要在后面排队。文件还没有（刚开机、刚连 Wi-Fi
  // 还没评估到）时才回落到 dumpsys 直查。
  try {
    const STATE_FILE = `${router_state.moduleInformation.moduleDir}/vowifi_state`;
    const { stdout: state } = await exec(`cat "${STATE_FILE}" 2>/dev/null`);
    if (state.trim() === '1') return true;
    if (state.trim() === '0') return false;
  } catch (error) {
    // 读不到文件就继续往下走 dumpsys 回落
  }

  const DUMPSYS_TMP_FILE = `${router_state.moduleInformation.moduleDir}/dumpsys.tmp`;

  try {
    // Run dumpsys and save to file
    await exec(`dumpsys activity service SystemUIService > "${DUMPSYS_TMP_FILE}" 2>/dev/null`);

    // Check for VoWiFi pattern: AOSP slot format, or ColorOS/Oplus
    // vowifiState=true (this device's dump only has the latter)
     const { stdout: returnCode } = await exec(`
      grep -qE "slot=\'vowifi\'.*visible user=.*|vowifiState=true" "${DUMPSYS_TMP_FILE}" && echo $?`
    );

    // Clean up temp file
    await exec(`rm -f "${DUMPSYS_TMP_FILE}"`);

    // Return true if match found (exit code 0)
    return returnCode.trim() === '0';
  } catch (error) {
    console.error('Error checking VoWiFi state:', error);
    addLog('检查 VoWiFi 状态出错。');
    return false;
  }
}

// 一次 ls 拿回模块目录的全部文件名，供设置页/启动时一次推导多个标记和
// 下拉框当前值，免得每个标记、每个下拉框各跑一次 shell。调用方在拿到
// 列表后用它做本地判断，不再逐个 exec。
export async function fetchModuleDirListing() {
	try {
		const { stdout: output } = await exec(`ls ${router_state.moduleInformation.moduleDir}`);
		return output.trim().split('\n').filter(line => line.length > 0);
	} catch (error) {
		console.error('Error listing module dir: ', error);
		return [];
	}
}

export async function fetchPrivateDnsMarker (listing) {
	if (listing) {
		const entry = listing.find(name => name.startsWith('private_dns_'));
		return entry ? entry.replace('private_dns_', '') : "off";
	}
	try {
		const { stdout: rawFile } = await exec(`ls ${router_state.moduleInformation.moduleDir}/private_dns_* 2>/dev/null | xargs -n 1 basename | head -n1`);
		const fileName = rawFile.trim();
		if (!fileName) return "off";
		return fileName.replace('private_dns_', '');
	} catch (error) {
		console.error('Error fetching Private DNS marker:', error);
		return "off";
	}
};

export async function get_private_dns_state() {
	try {
		const { stdout: mode } = await exec('settings get global private_dns_mode');
		if (mode.trim() === 'hostname') {
			const { stdout: host } = await exec('settings get global private_dns_specifier');
			return host.trim() || 'hostname';
		}
		return '已关闭';
	} catch (error) {
		console.error('Error fetching Private DNS state:', error);
		return '未知';
	}
}

// hosts 去广告的实际生效状态：只看 /proc/mounts，不看开关选了什么。
// ours = 我们的列表正挂着；other = 别的工具（AdAway 等）占着位置；
// none = 没挂。开关开了但这里显示“未开启”，就是挂载没成功。
export async function get_hosts_block_state() {
	try {
		const dir = router_state.moduleInformation.moduleDir;
		const { stdout: mountLine } = await exec(`grep " /system/etc/hosts " /proc/mounts | head -n1`);
		const line = mountLine.trim();
		if (line) {
			if (line.startsWith(`${dir}/hosts `)) {
				const { stdout: count } = await exec(`grep -c "^0\\.0\\.0\\.0" "${dir}/hosts" 2>/dev/null`);
				return { status: 'ours', rules: parseInt(count.trim(), 10) || 0 };
			}
			return { status: 'other', source: line.split(' ')[0] };
		}
		return { status: 'none' };
	} catch (error) {
		console.error('Error fetching hosts block state:', error);
		return { status: 'error' };
	}
}

export async function fetchIsConfigFile (file_name, listing) {
	// 调用方已经一次 ls 拿回目录列表时直接本地判断，不再多跑一次 shell
	if (listing) return listing.includes(file_name);
	try {
		const { stdout: output } = await exec(`[ -f "${router_state.moduleInformation.moduleDir}/${file_name}" ] && echo "exist" || echo ""`);
		return output == "exist";
	} catch (error) {
		console.error('Error fetching kill connections status: ', error);
		addLog('获取断开连接状态出错。');
		toast("获取断开连接状态出错。");
		return false;
	}
};

export function formatLocalDateTime(date = new Date()) {
  const pad = (n) => n.toString().padStart(2, '0');

  const yyyy = date.getFullYear();
  const mm   = pad(date.getMonth() + 1);
  const dd   = pad(date.getDate());

  const hh   = pad(date.getHours());
  const min  = pad(date.getMinutes());
  const ss   = pad(date.getSeconds());

  return `${yyyy}-${mm}-${dd} ${hh}:${min}:${ss}`;
}

document.addEventListener('DOMContentLoaded', async () => {
	document.querySelectorAll('.link').forEach(async (link) => {
		link.addEventListener('click', async (event) => {
			event.preventDefault();
			const url = event.currentTarget.getAttribute('data-value');
			await exec(`am start -a android.intent.action.VIEW -d "${url}"`);
		});
	});
});

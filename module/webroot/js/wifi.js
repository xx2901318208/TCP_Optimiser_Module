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

	// 网关延迟测试只手动开始/停止：每秒跑一次 shell 测延迟，自动跑会占 exec 通道
	const latencyStartBtn = document.getElementById('latency-start');
	const latencyStopBtn = document.getElementById('latency-stop');
	if (latencyStartBtn) {
		latencyStartBtn.addEventListener('click', startLatencyTest);
	}
	if (latencyStopBtn) {
		latencyStopBtn.addEventListener('click', stopLatencyTest);
	}

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

// 网关延迟测试：每秒 ping 一次路由器，只留最近 60 个样本（60 秒），
// 画成曲线，同时算最小 / 平均 / 最大 / 丢包率。照欧加网络助手
// PingViewModel 的做法：样本是数字（延迟毫秒）或 null（那一秒没 ping 通，记丢包）。
const LATENCY_WINDOW = 60;
let latencySamples = [];
let latencyTimer = null;
let latencyTickBusy = false;

function latencyEls() {
	return {
		canvas: document.getElementById('latency-chart'),
		gateway: document.getElementById('latency-gateway-value'),
		current: document.getElementById('latency-current-value'),
		min: document.getElementById('latency-min-value'),
		avg: document.getElementById('latency-avg-value'),
		max: document.getElementById('latency-max-value'),
		loss: document.getElementById('latency-loss-value'),
		startBtn: document.getElementById('latency-start'),
		stopBtn: document.getElementById('latency-stop'),
		status: document.getElementById('latency-status'),
	};
}

function setLatencyText(el, text) {
	if (el) el.textContent = text;
}

function startLatencyTest() {
	if (latencyTimer) return;
	latencySamples = [];
	latencyTickBusy = false;
	const els = latencyEls();
	if (els.startBtn) els.startBtn.disabled = true;
	if (els.stopBtn) els.stopBtn.disabled = false;
	setLatencyText(els.status, '正在测试…每秒测一次，最多 60 秒。');
	drawLatencyChart();
	updateLatencyStats();
	latencyTick();
	latencyTimer = setInterval(latencyTick, 1000);
}

function stopLatencyTest() {
	if (latencyTimer) {
		clearInterval(latencyTimer);
		latencyTimer = null;
	}
	const els = latencyEls();
	if (els.startBtn) els.startBtn.disabled = false;
	if (els.stopBtn) els.stopBtn.disabled = true;
	if (els.status && latencySamples.length === 0) {
		setLatencyText(els.status, '已停止。点“开始测试”重新测。');
	} else if (els.status) {
		setLatencyText(els.status, '已停止。');
	}
}

// 每秒跑一次：调 get_gateway_latency.sh 测一次，记进样本里，
// 只留最近 60 个。离开 WiFi 页（卡片不在了）就自动停，免得后台一直 ping。
async function latencyTick() {
	// 卡片不在页面上了（切到别的页了），停掉定时器
	if (!document.getElementById('latency-chart')) {
		stopLatencyTest();
		return;
	}
	// 上一秒那次还没跑完（ping 超时要 1 秒），跳过这次，不叠着跑
	if (latencyTickBusy) return;
	latencyTickBusy = true;
	try {
		const dir = (router_state.moduleInformation && router_state.moduleInformation.moduleDir) || '/data/adb/modules/k-network';
		let rtt = null;
		let gateway = null;
		try {
			const { stdout } = await exec(`sh ${dir}/get_gateway_latency.sh`);
			const firstLine = (stdout || '').trim().split('\n')[0] || '';
			if (firstLine.startsWith('OK|')) {
				const [, rttText, gw] = firstLine.split('|');
				const v = parseFloat(rttText);
				if (isFinite(v)) rtt = v;
				gateway = gw || null;
			}
		} catch (error) {
			console.error('Error pinging gateway:', error);
		}
		latencySamples.push(rtt);
		if (latencySamples.length > LATENCY_WINDOW) {
			latencySamples = latencySamples.slice(-LATENCY_WINDOW);
		}
		const els = latencyEls();
		if (gateway) setLatencyText(els.gateway, gateway);
		if (rtt === null) {
			setLatencyText(els.current, '超时');
			setLatencyText(els.status, '这一秒没 ping 通，记一次丢包。');
		} else {
			setLatencyText(els.current, `${rtt.toFixed(1)} ms`);
			setLatencyText(els.status, `正在测试…已测 ${latencySamples.length} 秒。`);
		}
		drawLatencyChart();
		updateLatencyStats();
	} finally {
		latencyTickBusy = false;
	}
}

function updateLatencyStats() {
	const els = latencyEls();
	const ok = latencySamples.filter((v) => v !== null && v !== undefined);
	if (ok.length === 0) {
		setLatencyText(els.min, '—');
		setLatencyText(els.avg, '—');
		setLatencyText(els.max, '—');
	} else {
		const min = Math.min(...ok);
		const max = Math.max(...ok);
		const avg = ok.reduce((a, b) => a + b, 0) / ok.length;
		setLatencyText(els.min, `${min.toFixed(1)} ms`);
		setLatencyText(els.avg, `${avg.toFixed(1)} ms`);
		setLatencyText(els.max, `${max.toFixed(1)} ms`);
	}
	if (latencySamples.length === 0) {
		setLatencyText(els.loss, '—');
	} else {
		const lost = latencySamples.filter((v) => v === null || v === undefined).length;
		const rate = (lost / latencySamples.length) * 100;
		setLatencyText(els.loss, `${rate.toFixed(0)}%（${lost}/${latencySamples.length}）`);
	}
}

// 画延迟曲线：横轴是最近 60 秒（左旧右新），纵轴是延迟毫秒，
// 丢包的那一秒断开、下面画个红点。没有样本时只画个空框。
function drawLatencyChart() {
	const canvas = document.getElementById('latency-chart');
	if (!canvas) return;
	const dpr = window.devicePixelRatio || 1;
	const cssW = canvas.clientWidth || 600;
	const cssH = 160;
	canvas.width = Math.round(cssW * dpr);
	canvas.height = Math.round(cssH * dpr);
	canvas.style.height = `${cssH}px`;
	const ctx = canvas.getContext('2d');
	if (!ctx) return;
	ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
	ctx.clearRect(0, 0, cssW, cssH);

	const padL = 8, padR = 8, padT = 10, padB = 22;
	const plotW = cssW - padL - padR;
	const plotH = cssH - padT - padB;
	const primary = (getComputedStyle(document.documentElement).getPropertyValue('--primary') || '#bb86fc').trim() || '#bb86fc';

	// 底框
	ctx.strokeStyle = 'rgba(255,255,255,0.15)';
	ctx.lineWidth = 1;
	ctx.strokeRect(padL, padT, plotW, plotH);

	// 纵轴刻度（0 和最大值）
	const ok = latencySamples.filter((v) => v !== null && v !== undefined);
	const maxOk = ok.length > 0 ? Math.max(...ok) : 0;
	const yMax = Math.max(20, Math.ceil(maxOk * 1.2));
	ctx.fillStyle = 'rgba(255,255,255,0.5)';
	ctx.font = '11px sans-serif';
	ctx.textAlign = 'left';
	ctx.fillText(`${yMax} ms`, padL + 2, padT + 11);
	ctx.fillText('0', padL + 2, padT + plotH - 3);
	ctx.textAlign = 'right';
	ctx.fillText('60 秒', padL + plotW - 2, padT + plotH - 3);

	if (latencySamples.length === 0) return;

	// 每个样本占一格，横坐标按序号排
	const stepX = plotW / LATENCY_WINDOW;
	const xOf = (i) => padL + (i + 0.5) * stepX;
	const yOf = (v) => padT + plotH - (v / yMax) * plotH;

	// 丢包的红点（画在底边上）
	ctx.fillStyle = '#f44336';
	latencySamples.forEach((v, i) => {
		if (v === null || v === undefined) {
			ctx.beginPath();
			ctx.arc(xOf(i), padT + plotH - 3, 3, 0, Math.PI * 2);
			ctx.fill();
		}
	});

	// 连线：只连相邻两个都有数的样本，丢包处断开
	ctx.strokeStyle = primary;
	ctx.lineWidth = 2;
	ctx.beginPath();
	let started = false;
	latencySamples.forEach((v, i) => {
		if (v === null || v === undefined) {
			started = false;
			return;
		}
		if (!started) {
			ctx.moveTo(xOf(i), yOf(v));
			started = true;
		} else {
			ctx.lineTo(xOf(i), yOf(v));
		}
	});
	ctx.stroke();

	// 最后一个有数的样本画个点
	for (let i = latencySamples.length - 1; i >= 0; i--) {
		const v = latencySamples[i];
		if (v !== null && v !== undefined) {
			ctx.fillStyle = primary;
			ctx.beginPath();
			ctx.arc(xOf(i), yOf(v), 3.5, 0, Math.PI * 2);
			ctx.fill();
			break;
		}
	}
}

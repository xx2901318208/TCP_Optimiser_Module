import { exec, toast } from './kernelsu.js';
import { formatLocalDateTime } from './common.js';
import router_state from './router.js';

const logHeadingDefaultValue = "日志";
let prev_logs_count = 0;

export async function addLog(message) {
	try
	{
		const LOGFILE = `${router_state.moduleInformation.moduleDir}/service.log`;
		const MAX_LOG_LINES = 200;
		await exec(`echo "${formatLocalDateTime()} - ${message}" >> ${router_state.moduleInformation.moduleDir}/service.log`);
		// Count lines in the log file
		const { stdout: lineCountOutput } = await exec(`wc -l < ${LOGFILE}`);
		let lineCount = parseInt(lineCountOutput.trim(), 10);

		// If file has more than MAX_LOG_LINES, truncate (keep all 200 lines,
		// not half — same fix as utils.sh, so the log no longer loses half
		// its history on every trim)
		if (lineCount > MAX_LOG_LINES) {
			await exec(`tail -n ${MAX_LOG_LINES} ${LOGFILE} > ${LOGFILE}.tmp && mv ${LOGFILE}.tmp ${LOGFILE}`);
		}
	} catch (error)
	{
		console.error('Error Adding to log file: ', error);
		addLogToScreen('写入日志文件出错。');
		toast("写入日志文件出错。");
	}
}

export async function read_log_file() {
	try {
		const { stdout: logs } = await exec(`cat ${router_state.moduleInformation.moduleDir}/service.log`);
		router_state.logsList = logs.trim().split('\n').filter(line => line.length > 0);
	} catch (error) {
		console.error('Error reading log file: ', error);
		addLog('读取日志文件出错。');
		toast("读取日志文件出错。");
	}
}

function addLogToScreen(message, withTimestamp = false) {
	const logEntry = document.createElement('div');
	logEntry.textContent = withTimestamp ? `${formatLocalDateTime()} - ${message}` : `${message}`;
	document.getElementById('log-content').appendChild(logEntry);
	// 不在这里强制滚到底：每行都滚一次会打断用户往上翻看/选中复制，
	// 滚动位置由 updateLogsUI 按“之前是否已在底部”决定。
}

export function updateLogsUI () {
	if (router_state.isInitializing == false) {
		if(router_state.logsList.length != prev_logs_count)
		{
			const logContent = document.getElementById('log-content');
			// 记下重绘前是否已在底部：在底部才跟进新行，否则保持用户正在看的位置，
			// 不然每 5 秒重绘一次就会把翻上去的手打断，根本没法选中复制。
			const nearBottom = logContent.scrollHeight - logContent.scrollTop - logContent.clientHeight < 80;
			document.getElementById('logs-heading').textContent = `${logHeadingDefaultValue} ${router_state.logsList.length > 0 ? `(${router_state.logsList.length})` : ""}`;
			logContent.innerHTML = '';
			router_state.logsList.forEach(log => {
				addLogToScreen(log);
			});
			if (nearBottom) {
				logContent.scrollTop = logContent.scrollHeight;
			}
			// 之前这里写反了：logsList.length = prev_logs_count 会把列表截断，
			// prev_logs_count 永远是 0，导致每 5 秒无条件整页重绘。
			prev_logs_count = router_state.logsList.length;
		}
	}
}

export async function initLogs() {
	const clearLogsBtn = document.getElementById('clear-logs');
	const copyLogsBtn = document.getElementById('copy-logs');

	copyLogsBtn.addEventListener('click', async () => {
		const text = router_state.logsList.join('\n');
		if (!text) {
			toast("暂无日志可复制。");
			return;
		}
		try {
			if (navigator.clipboard && navigator.clipboard.writeText) {
				await navigator.clipboard.writeText(text);
			} else {
				throw new Error('clipboard API unavailable');
			}
		} catch (error) {
			// WebView 里 clipboard 可能不可用：用隐藏输入框 + execCommand 兜底
			const textarea = document.createElement('textarea');
			textarea.value = text;
			textarea.style.position = 'fixed';
			textarea.style.opacity = '0';
			document.body.appendChild(textarea);
			textarea.select();
			const ok = document.execCommand('copy');
			document.body.removeChild(textarea);
			if (!ok) {
				console.error('Error copying logs: ', error);
				toast("复制失败，请长按手动选择复制。");
				return;
			}
		}
		toast(`已复制日志（${router_state.logsList.length} 行）。`);
	});

	clearLogsBtn.addEventListener('click', async () => {
		try
		{
			await exec(`rm -f ${router_state.moduleInformation.moduleDir}/service.log`);
			document.getElementById('log-content').innerHTML = '';
			document.getElementById('logs-heading').textContent = logHeadingDefaultValue;
			router_state.logsList = [];
			prev_logs_count = 0;
		} catch (error)
		{
			console.error('Error clearing log file: ', error);
			addLogToScreen('清除日志文件出错。');
			toast("清除日志文件出错。");
		}
	});
	
	router_state.isInitializing = false;
	updateLogsUI();
}

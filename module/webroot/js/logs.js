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

		// If file has more than MAX_LOG_LINES, truncate
		if (lineCount > MAX_LOG_LINES) {
			const halfLines = Math.floor(MAX_LOG_LINES / 2);
			await exec(`tail -n ${halfLines} ${LOGFILE} > ${LOGFILE}.tmp && mv ${LOGFILE}.tmp ${LOGFILE}`);
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
	document.getElementById('log-content').scrollTop = document.getElementById('log-content').scrollHeight;
}

export function updateLogsUI () {
	if (router_state.isInitializing == false) {
		if(router_state.logsList.length != prev_logs_count)
		{
			document.getElementById('logs-heading').textContent = `${logHeadingDefaultValue} ${router_state.logsList.length > 0 ? `(${router_state.logsList.length})` : ""}`;
			document.getElementById('log-content').innerHTML = '';
			router_state.logsList.forEach(log => {
				addLogToScreen(log);
			});
			router_state.logsList.length = prev_logs_count;
		}
	}
}

export async function initLogs() {
	const clearLogsBtn = document.getElementById('clear-logs');
	
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

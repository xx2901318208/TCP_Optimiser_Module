import { updateModuleInformation, fetchIsConfigFile, fetchPrivateDnsMarker, fetchModuleDirListing } from './common.js';
import { updateModuleStatus, initHome, updateHomeUI } from './home.js';
import { initLogs } from './logs.js';
import { initSettings } from './settings.js';
import { initAdblock } from './adblock.js';
import { addLog, read_log_file, updateLogsUI } from './logs.js';
import { fullScreen } from './kernelsu.js';

const router_state = {
	moduleInformation: null,
	isInitializing: true,
	homePageParams: {
		module_status: "正在加载模块状态...⌛",
		active_iface_type: "无",
		active_iface: "未知 ⁉️",
		active_algorithm: "未知 ⁉️",
		active_qdisc: "未知 ⁉️",
		active_InitcwndInitrwndValue: [],
		wifi_calling_state: false,
		private_dns_state: "未知 ⁉️",
	},
	settingsPageParams: {
		wlanAlgo: null,
		wlanQdisc: null,
		rmnetAlgo: null,
		rmnetQdisc: null,
		killConnections: null,
		initcwndInitrwnd: null,
		wifiPowersaveOff: null,
	},
	adblockPageParams: {
		adblockHosts: null,
		privateDns: null,
	},
	logsList: [],
	available_algorithms: [],
	available_qdiscs: [],
	current_active_page: null,
};

let currentPageStyle = null; // Store reference to the current style link

function setCSS(pageName) {
	if (currentPageStyle) {
		document.head.removeChild(currentPageStyle);
	}

	currentPageStyle = document.createElement('link');
	currentPageStyle.rel = 'stylesheet';
	currentPageStyle.href = `./css/${pageName}.css`;
	document.head.appendChild(currentPageStyle);
}

const realtimeUpdater = async () => {
	try {
		// 首轮读取并行跑：状态、日志、5 个标记文件互不依赖，
		// 原先一个接一个等十几个 shell，首页和日志页都要等完整一串。
		const fetchMarkers = async () => {
			// 5 个标记文件一次 ls 全拿回来本地判断，不再每个各跑一次 shell
			const listing = await fetchModuleDirListing();
			if(router_state.settingsPageParams.killConnections == null)
				router_state.settingsPageParams.killConnections = listing.includes("kill_connections");

			if(router_state.settingsPageParams.initcwndInitrwnd == null)
				router_state.settingsPageParams.initcwndInitrwnd = listing.includes("initcwnd_initrwnd");

			if(router_state.settingsPageParams.wifiPowersaveOff == null)
				router_state.settingsPageParams.wifiPowersaveOff = listing.includes("wifi_powersave_off");

			if(router_state.adblockPageParams.adblockHosts == null)
				router_state.adblockPageParams.adblockHosts = listing.includes("adblock_hosts");

			if(router_state.adblockPageParams.privateDns == null)
				router_state.adblockPageParams.privateDns = await fetchPrivateDnsMarker(listing);
		};

		// First Read
		await Promise.all([
			updateModuleStatus(),
			read_log_file(),
			fetchMarkers(),
		]);

		if(currentPageStyle != null)
		{
			switch(router_state.current_active_page)
			{
				case 'home':
					updateHomeUI();
					break;
					
				case 'logs':
					updateLogsUI();
					break;
			}
		}
		
		// 轮询用自调度的 setTimeout：上一轮没跑完不启动下一轮。
		// 之前 setInterval 不等上一轮，dumpsys/ping 慢的时候几轮叠在一起跑，
		// 越叠越慢，设置页的 exec 全堵在后面。
		const scheduleTick = () => {
			setTimeout(async () => {
				try {
					await Promise.all([
						updateModuleStatus(),
						read_log_file(),
					]);
					if(currentPageStyle != null)
					{
						switch(router_state.current_active_page)
						{
							case 'home':
								updateHomeUI();
								break;
							
							case 'logs':
							updateLogsUI();
							break;
						}
					}
				} catch (error) {
					console.error('Error in update tick: ', error);
				}
				scheduleTick();
			}, 5000);
		};
		scheduleTick();
	} catch (error) {
		console.error('Error setting update loop: ', error);
		addLog('设置更新循环出错。');
	}
};

document.addEventListener('DOMContentLoaded', async () => {
	const navLinks = document.querySelectorAll('.footer-nav .nav-item');
	fullScreen(true);

	let pageGeneration = 0; // 切页代号：用户点得快、两次切页撞在一起时，
	// 旧的那次直接作废，不让它的 init 在新页面上跑——之前这样能把
	// isInitializing 卡在 true，日志/首页就再也不刷新了。
	function loadPage(pageName) {
		const generation = ++pageGeneration;
		return new Promise(async (resolve, reject) => {
			const currentPage = document.getElementById('current-page');
			const contentContainer = document.getElementById('page-content');
			
			// Start exit animation
			currentPage.classList.remove('active');
			currentPage.style.transition = 'opacity 0.4s ease';
			
			setTimeout(() => {
				if (generation !== pageGeneration) { resolve(); return; }
				fetch(`./pages/${pageName}.html`)
				.then(response => response.text())
				.then(html => {
					if (generation !== pageGeneration) { resolve(); return; }
					router_state.isInitializing = true;
					router_state.current_active_page = pageName;
					
					currentPage.innerHTML = html;
					setCSS(pageName);
					
					if (!router_state.moduleInformation) {
						updateModuleInformation().then(res => {});
					}
					
					// Load page-specific script
					import(`./${pageName}.js`).then(module => {
						if (generation !== pageGeneration) { resolve(); return; }
						switch (pageName) {
							case 'home':
								module.initHome();
								break;
							case 'settings':
								module.initSettings();
								break;
							case 'adblock':
								module.initAdblock();
								break;
							case 'logs':
								module.initLogs();
								break;
						}
						
						// Trigger entry animation
						currentPage.classList.add('active');
						resolve();
					}).catch(err => {
					  console.error("Failed to load page script:", err);
					  contentContainer.innerHTML = `
					  <div style="display: flex; justify-content: center; align-items: center; height: 100%; flex-direction: column;">
						<p>⚠️⚠️⚠️ 页面加载出错 ⚠️⚠️⚠️</p>
					  </div>`;
					reject(err);
					});
				  })
				  .catch(err => {
					console.error("Failed to load page content:", err);
					contentContainer.innerHTML = `
					  <div style="display: flex; justify-content: center; align-items: center; height: 100%; flex-direction: column;">
						<p>⚠️⚠️⚠️ 页面加载出错 ⚠️⚠️⚠️</p>
					  </div>`;
					reject(err);
				  });
			}, 400); // Wait for exit animation to finish
		});
	}

	// Set default page
	loadPage('home').then(() => {
		realtimeUpdater();
		// Add click event to nav links
		navLinks.forEach(link => {
			link.addEventListener('click', (e) => {
				e.preventDefault();
				const page = e.currentTarget.dataset.page;
				navLinks.forEach(l => l.classList.remove('active'));
				e.currentTarget.classList.add('active');
				loadPage(page);
			});
		  });
	});
});

export default router_state;

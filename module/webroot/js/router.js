import { updateModuleInformation, fetchIsConfigFile } from './common.js';
import { updateModuleStatus, initHome, updateHomeUI } from './home.js';
import { initLogs } from './logs.js';
import { initSettings } from './settings.js';
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
	},
	settingsPageParams: {
		wlanAlgo: null,
		wlanQdisc: null,
		rmnetAlgo: null,
		rmnetQdisc: null,
		killConnections: null,
		initcwndInitrwnd: null,
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
		// First Read
		await updateModuleStatus();
		await read_log_file();
		
		// Fetch Settings Value
		if(router_state.settingsPageParams.killConnections == null)
			router_state.settingsPageParams.killConnections = await fetchIsConfigFile("kill_connections");
		
		if(router_state.settingsPageParams.initcwndInitrwnd == null)
			router_state.settingsPageParams.initcwndInitrwnd = await fetchIsConfigFile("initcwnd_initrwnd");

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
		
		setInterval(async () => {
			await updateModuleStatus();
			await read_log_file();
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
		}, "5000");
	} catch (error) {
		console.error('Error setting update loop: ', error);
		addLog('设置更新循环出错。');
	}
};

document.addEventListener('DOMContentLoaded', async () => {
	const navLinks = document.querySelectorAll('.footer-nav .nav-item');
	fullScreen(true);

	function loadPage(pageName) {
		return new Promise(async (resolve, reject) => {
			const currentPage = document.getElementById('current-page');
			const contentContainer = document.getElementById('page-content');
			
			// Start exit animation
			currentPage.classList.remove('active');
			currentPage.style.transition = 'opacity 0.4s ease';
			
			setTimeout(() => {
				fetch(`./pages/${pageName}.html`)
				.then(response => response.text())
				.then(html => {
					router_state.isInitializing = true;
					router_state.current_active_page = pageName;
					
					currentPage.innerHTML = html;
					setCSS(pageName);
					
					if (!router_state.moduleInformation) {
						updateModuleInformation().then(res => {});
					}
					
					// Load page-specific script
					import(`./${pageName}.js`).then(module => {
						switch (pageName) {
							case 'home':
								module.initHome();
								break;
							case 'settings':
								module.initSettings();
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

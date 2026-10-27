// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum ClashStrings {
    static func text(_ key: String, _ language: AppLanguage) -> String {
        let simplified: [String: String] = [
            "coreRunning": "核心运行中", "coreStopped": "核心已停止", "starting": "正在启动…", "stopping": "正在停止…", "tunChanging": "正在切换虚拟网卡…", "start": "启动", "stop": "停止",
            "connection": "连接", "systemProxy": "系统代理", "mode": "模式", "routes": "线路",
            "testAllRoutes": "测试全部线路", "subscription": "订阅", "subscriptionURL": "订阅链接",
            "paste": "粘贴", "updateSubscription": "更新订阅", "ports": "端口",
            "mixedPort": "混合端口", "controllerPort": "控制器端口",
            "separatePortsNote": "这些端口与 FlClash 默认端口分开。", "upload": "上传",
            "download": "下载", "proxySettings": "代理设置", "showProxyMenuBar": "在菜单栏显示代理",
            "showProxyMenuBarHint": "显示或隐藏独立的代理状态图标；不会停止核心或更改系统代理。", "testLatency": "测试延迟",
            "proxyGroups": "代理组", "noSubscription": "尚未配置订阅，或核心未运行。",
            "configureSubscription": "配置订阅", "rule": "规则", "global": "全局", "direct": "直连",
            "configError": "代理配置错误", "missingConfig": "找不到代理配置文件，请先更新订阅。",
            "missingCore": "找不到 Mihomo 核心，请确认核心文件已安装。",
            "repairConfig": "无法修复代理配置，请更新订阅后重试。",
            "validateConfig": "无法验证代理配置", "startFailed": "无法启动代理核心",
            "invalidURL": "请输入有效的订阅链接", "updating": "正在更新订阅…",
            "updated": "订阅更新成功", "updateFailed": "订阅更新失败",
            "dashboard": "仪表盘", "network": "网络", "virtualNIC": "虚拟网卡 (TUN)",
            "tunRestartNote": "切换会重启代理核心；首次开启虚拟网卡时 macOS 会请求一次管理员授权。",
            "tunAuthorizationFailed": "无法授权虚拟网卡核心。请确认应用已安装在“应用程序”目录并使用管理员账户。",
            "tunStoragePermissionFailed": "无法为虚拟网卡核心设置安全的数据目录权限。",
            "tunStack": "网络栈", "stackSystem": "系统", "stackGVisor": "gVisor", "stackMixed": "混合",
            "autoRoute": "自动配置路由", "autoDetectInterface": "自动检测网络接口", "dnsHijack": "DNS 劫持",
            "tunOptions": "虚拟网卡选项",
            "localIP": "局域网 IP", "trafficUsage": "流量用量", "usedTotal": "已用 / 总量",
            "remaining": "剩余", "expires": "到期时间", "latencyUnknown": "未测速",
            "unreachable": "超时", "connected": "可用", "testing": "正在测速…",
            "noUsage": "订阅服务未提供流量信息", "trafficSession": "本次运行流量",
            "controllerUnavailable": "代理核心未能启动，控制器未就绪；系统代理保持原样。",
            "dnsSection": "DNS", "dnsEnabled": "启用 DNS", "dnsPort": "DNS 监听端口",
            "dnsNote": "DNS 解析器和规则继续使用订阅配置；本地监听端口与 FlClash 分开。",
            "dnsAdvanced": "DNS 高级设置", "dnsHijackManaged": "TUN DNS 拦截目标由核心自动配置。",
            "existingCoreControllerUnavailable": "已发现 Developer 核心进程，但控制器未就绪；没有重复启动核心。",
            "coreStopFailed": "核心未能正常停止。请保持应用打开并重试，以便释放虚拟网卡。",
        ]
        let traditional: [String: String] = [
            "coreRunning": "核心執行中", "coreStopped": "核心已停止", "starting": "正在啟動…", "stopping": "正在停止…", "tunChanging": "正在切換虛擬網卡…", "start": "啟動", "stop": "停止",
            "connection": "連線", "systemProxy": "系統代理", "mode": "模式", "routes": "線路",
            "testAllRoutes": "測試所有線路", "subscription": "訂閱", "subscriptionURL": "訂閱連結",
            "paste": "貼上", "updateSubscription": "更新訂閱", "ports": "連接埠",
            "mixedPort": "混合連接埠", "controllerPort": "控制器連接埠",
            "separatePortsNote": "這些連接埠與 FlClash 預設連接埠不同。", "upload": "上傳",
            "download": "下載", "proxySettings": "代理設定", "showProxyMenuBar": "在選單列顯示代理",
            "showProxyMenuBarHint": "顯示或隱藏獨立的代理狀態圖示；不會停止核心或變更系統代理。", "testLatency": "測試延遲",
            "proxyGroups": "代理群組", "noSubscription": "尚未設定訂閱，或核心未執行。",
            "configureSubscription": "設定訂閱", "rule": "規則", "global": "全域", "direct": "直連",
            "configError": "代理設定錯誤", "missingConfig": "找不到代理設定檔，請先更新訂閱。",
            "missingCore": "找不到 Mihomo 核心，請確認核心檔案已安裝。",
            "repairConfig": "無法修復代理設定，請更新訂閱後重試。",
            "validateConfig": "無法驗證代理設定", "startFailed": "無法啟動代理核心",
            "invalidURL": "請輸入有效的訂閱連結", "updating": "正在更新訂閱…",
            "updated": "訂閱更新成功", "updateFailed": "訂閱更新失敗",
            "dashboard": "儀表板", "network": "網路", "virtualNIC": "虛擬網卡 (TUN)",
            "tunRestartNote": "切換會重新啟動代理核心；首次開啟虛擬網卡時 macOS 會要求一次管理員授權。",
            "tunAuthorizationFailed": "無法授權虛擬網卡核心。請確認應用已安裝在「應用程式」資料夾並使用管理員帳戶。",
            "tunStoragePermissionFailed": "無法為虛擬網卡核心設定安全的資料目錄權限。",
            "tunStack": "網路堆疊", "stackSystem": "系統", "stackGVisor": "gVisor", "stackMixed": "混合",
            "autoRoute": "自動設定路由", "autoDetectInterface": "自動偵測網路介面", "dnsHijack": "DNS 劫持",
            "tunOptions": "虛擬網卡選項",
            "localIP": "區域網路 IP", "trafficUsage": "流量用量", "usedTotal": "已用 / 總量",
            "remaining": "剩餘", "expires": "到期時間", "latencyUnknown": "未測速",
            "unreachable": "逾時", "connected": "可用", "testing": "正在測速…",
            "noUsage": "訂閱服務未提供流量資訊", "trafficSession": "本次執行流量",
            "controllerUnavailable": "代理核心未能啟動，控制器尚未就緒；系統代理保持原樣。",
            "dnsSection": "DNS", "dnsEnabled": "啟用 DNS", "dnsPort": "DNS 監聽連接埠",
            "dnsNote": "DNS 解析器和規則繼續使用訂閱設定；本機監聽連接埠與 FlClash 分開。",
            "dnsAdvanced": "DNS 進階設定", "dnsHijackManaged": "TUN DNS 攔截目標由核心自動設定。",
            "existingCoreControllerUnavailable": "已發現 Developer 核心進程，但控制器尚未就緒；沒有重複啟動核心。",
            "coreStopFailed": "核心未能正常停止。請保持應用開啟並重試，以釋放虛擬網卡。",
        ]
        switch language {
        case .zhHans: return simplified[key] ?? key
        case .zhTW, .zhHK: return traditional[key] ?? simplified[key] ?? key
        default: return english[key] ?? key
        }
    }

    private static let english: [String: String] = [
        "coreRunning": "Core Running", "coreStopped": "Core Stopped", "starting": "Starting…", "stopping": "Stopping…", "tunChanging": "Switching virtual network…", "start": "Start", "stop": "Stop",
        "connection": "Connection", "systemProxy": "System Proxy", "mode": "Mode", "routes": "Routes",
        "testAllRoutes": "Test All Routes", "subscription": "Subscription", "subscriptionURL": "Subscription URL",
        "paste": "Paste", "updateSubscription": "Update Subscription", "ports": "Ports",
        "mixedPort": "Mixed Port", "controllerPort": "Controller Port",
        "separatePortsNote": "These ports are separate from FlClash's default ports.", "upload": "Upload",
        "download": "Download", "proxySettings": "Proxy Settings", "showProxyMenuBar": "Show Proxy in Menu Bar",
        "showProxyMenuBarHint": "Show or hide the proxy status item without stopping the core or changing system proxy settings.", "testLatency": "Test Latency",
        "proxyGroups": "Proxy Groups", "noSubscription": "No subscription is configured, or the core is stopped.",
        "configureSubscription": "Configure Subscription", "rule": "Rule", "global": "Global", "direct": "Direct",
        "configError": "Configuration error", "missingConfig": "Proxy configuration is missing. Update the subscription first.",
        "missingCore": "Mihomo core was not found. Check that the core is installed.",
        "repairConfig": "Could not repair the proxy configuration. Update the subscription and try again.",
        "validateConfig": "Could not validate the proxy configuration", "startFailed": "Could not start the proxy core",
        "invalidURL": "Enter a valid subscription URL", "updating": "Updating subscription…",
        "updated": "Subscription updated", "updateFailed": "Subscription update failed",
        "dashboard": "Dashboard", "network": "Network", "virtualNIC": "Virtual NIC (TUN)",
        "tunRestartNote": "Changing this restarts the core. macOS requests administrator authorization once when TUN is first enabled.",
        "tunAuthorizationFailed": "Could not authorize the TUN core. Install the app in Applications and use an administrator account.",
        "tunStoragePermissionFailed": "Could not set safe data-directory permissions for the TUN core.",
        "tunStack": "Network Stack", "stackSystem": "System", "stackGVisor": "gVisor", "stackMixed": "Mixed",
        "autoRoute": "Set system routes automatically", "autoDetectInterface": "Detect network interface automatically",
        "dnsHijack": "DNS Hijack", "tunOptions": "Virtual NIC Options",
        "localIP": "LAN IP", "trafficUsage": "Traffic Usage", "usedTotal": "Used / Total",
        "remaining": "Remaining", "expires": "Expires", "latencyUnknown": "Not tested",
        "unreachable": "Timeout", "connected": "Available", "testing": "Testing…",
        "noUsage": "The subscription server did not provide usage information", "trafficSession": "Session Traffic",
        "controllerUnavailable": "The core did not start; its controller never became ready. The system proxy was left unchanged.",
        "dnsSection": "DNS", "dnsEnabled": "Enable DNS", "dnsPort": "DNS Listen Port",
        "dnsNote": "Resolver lists and policies still come from the subscription. The local listener uses a separate port from FlClash.",
        "dnsAdvanced": "Advanced DNS Settings", "dnsHijackManaged": "TUN DNS interception targets are managed by the core.",
        "existingCoreControllerUnavailable": "A Developer core process was found, but its controller is not ready. No duplicate core was started.",
        "coreStopFailed": "The core did not stop cleanly. Keep the app open and retry so the virtual NIC can be released.",
    ]

    static func proxy(_ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "代理"
        case .zhTW, .zhHK: return "代理"
        default: return "Proxy"
        }
    }

    static func description(_ language: AppLanguage) -> String {
        switch language {
        case .zhHans: return "管理订阅、代理线路和连接状态。核心由你手动启动。"
        case .zhTW, .zhHK: return "管理訂閱、代理線路和連線狀態。核心由你手動啟動。"
        default: return "Manage subscriptions, routes, and connection status. Start the core when you need it."
        }
    }
}

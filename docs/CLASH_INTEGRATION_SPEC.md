# Vorssaint 内嵌独立 Clash (Mihomo) 代理模块开发文档

本文档定义了在 **Vorssaint** 菜单栏工具中内嵌完整独立代理服务（基于 Mihomo / Clash.Meta 内核）的需求规格、系统架构设计与落地开发计划。

---

## 1. 项目背景与目标

### 1.1 背景
目前 macOS 上的代理客户端（如 FlClash、Clash Verge、Clash for Windows 等）多数采用 Flutter 或 Electron 等跨平台框架开发，常驻内存占用普遍在 200MB ~ 600MB，且以独立窗口应用形式存在，操作不够轻量。

### 1.2 目标
在保持 Vorssaint **轻量、原生（Swift/SwiftUI）、低资源占用、模块化** 的理念下，内嵌代理内核：
* **完全独立运行**：无需安装或后台常驻任何第三方 GUI 代理软件；
* **极度轻量低功耗**：仅常驻轻量 Mihomo Go 二进制与原生 Swift 进程通信，内存开销减少 80% 以上；
* **顺手的一体化交互**：直接在顶部菜单栏查看实时网速、一键开关代理、切换节点与分流模式；
* **稳定与安全**：具备完善的异常退出保护，避免程序关闭后系统代理未还原导致浏览器“断网”。

---

## 2. 核心功能需求清单 (Functional Requirements)

| 编号 | 模块 | 功能项 | 详细描述 | 优先级 |
| :--- | :--- | :--- | :--- | :---: |
| **F-01** | **内核管理** | 内核守护与生命周期 | 内置/下载 `mihomo` darwin-arm64 二进制，以子进程方式拉起并监控健康状态，支持重启与停止 | P0 |
| **F-02** | **系统代理** | 免 Root 系统代理接管 | 调用 macOS `/usr/sbin/networksetup` 自动识别活跃网卡（Wi-Fi/以太网），一键开启/关闭 HTTP、HTTPS 及 SOCKS5 系统代理 | P0 |
| **F-03** | **配置与订阅** | 订阅解析与配置注入 | 支持用户输入 Clash 订阅链接，自动下载 `config.yaml`，使用与 FlClash 分开的本地端口 | P0 |
| **F-04** | **API 通信** | 内核 REST API 对接 | 通过独立的本地控制端口与内核通信：获取 `/traffic` 吞吐、读取 `/proxies` 节点信息、测速及切换节点 | P0 |
| **F-05** | **UI 交互** | 菜单栏状态与实时网速 | 菜单栏实时显示当前代理状态指示灯与动态上下行速率（如 `↑ 15KB/s ↓ 2.1MB/s`） | P1 |
| **F-06** | **UI 交互** | 模式与节点快速切换 | 下拉菜单中支持一键切换 `Rule（规则）` / `Global（全局）` / `Direct（直连）`，并按策略组展示节点延迟与切换选中节点 | P1 |
| **F-07** | **UI 交互** | 订阅配置与管理面板 | 提供设置弹窗，包含：订阅链接输入、一键立即更新、最后更新时间显示、端口配置等 | P1 |
| **F-08** | **安全防护** | 退出兜底防断网 | 退出时仅恢复仍指向本项目端口的系统代理设置；保留 FlClash 或其他应用后来设置的代理 | P0 |

---

## 3. 系统架构与技术实现方案

```
┌─────────────────────────────────────────────────────────────┐
│                    Vorssaint App (SwiftUI)                  │
├─────────────────────────────────────────────────────────────┤
│  [UI Layer]                                                 │
│    • ClashMenuBarItemView (菜单栏状态/实时网速)               │
│    • ClashMenuView (下拉主卡片: 开关、模式、策略组节点列表)     │
│    • ClashSettingsView (订阅管理、端口设置)                  │
├─────────────────────────────────────────────────────────────┤
│  [Service Layer]                                            │
│    • ClashManager (总控调度中心)                            │
│    • ClashDaemonService (进程生命周期控制: Process / Pipe)   │
│    • ClashConfigManager (订阅抓取、YAML 注入与存储)          │
│    • SystemProxyManager (网络设置: networksetup CLI 封装)   │
│    • MihomoAPIClient (URLSession 对接 127.0.0.1:9090)       │
├─────────────────────────────────────────────────────────────┤
│  [Native Subprocess]                                        │
│    • mihomo (Clash.Meta) 二进制进程                         │
│    • 工作目录: ~/Library/Application Support/Vorssaint/Clash/│
└─────────────────────────────────────────────────────────────┘
```

### 3.1 内核工作目录规划
应用启动时，在用户支持目录下建立专属沙盒目录：
```text
~/Library/Application Support/Vorssaint/Clash/
├── bin/
│   └── mihomo              # 核心可执行文件 (darwin-arm64)
├── config/
│   ├── config.yaml         # 运行中实时加载的合并配置
│   ├── Country.mmdb        # GeoIP 数据库
│   └── geosite.dat         # GeoSite 域名分流库
└── logs/
    └── mihomo.log          # 内核运行输出日志
```

### 3.2 本地运行配置注入规范
拉取到用户的订阅 YAML 后，解析并覆盖关键控制字段，保证与前端通信一致：
```yaml
port: 17890
socks-port: 17891
socks-port: 7891
mixed-port: 17892
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:19092
secret: "" # 绑定在本地回路，无需复杂密码
external-ui: ""
```

### 3.3 系统代理控制指令设计
通过 Swift `Process` 执行系统自带的 `/usr/sbin/networksetup`，不需要管理员权限（普通用户即可修改当前网络代理）：
* **开启代理**：
  ```bash
  networksetup -setwebproxy "Wi-Fi" 127.0.0.1 7890
  networksetup -setsecurewebproxy "Wi-Fi" 127.0.0.1 7890
  networksetup -setsocksfirewallproxy "Wi-Fi" 127.0.0.1 7890
  ```
* **关闭代理**：仅在当前系统代理仍指向 Vorssaint Developer 的端口时，恢复接管前保存的 HTTP、HTTPS 与 SOCKS 设置。若端口已改为 FlClash 使用的 `7890`，不会覆盖该设置。
  ```bash
  networksetup -setwebproxystate "Wi-Fi" off
  networksetup -setsecurewebproxystate "Wi-Fi" off
  networksetup -setsocksfirewallproxystate "Wi-Fi" off
  ```

---

## 4. 目录结构与代码组织

在 `Sources/Vorssaint/` 下新增以下代码文件：

```text
Sources/Vorssaint/
├── Core/
│   └── Clash/
│       ├── ClashModels.swift           # 节点、策略组、流量传输数据模型
│       └── ClashPreferences.swift      # 订阅地址、自启状态等用户配置
├── Services/
│   └── Clash/
│       ├── ClashManager.swift          # Clash 总协调器 (单例/环境对象)
│       ├── ClashDaemonService.swift    # 进程启动、停止、保活
│       ├── ClashConfigManager.swift    # 订阅拉取、写入、规则库准备
│       ├── SystemProxyManager.swift    # networksetup 网络代理调用封装
│       └── MihomoAPIClient.swift       # 127.0.0.1:9090 REST API 与流量轮询
└── UI/
    └── Clash/
        ├── ClashMenuBarView.swift      # 菜单栏微缩显示组件
        ├── ClashMenuView.swift         # 主控制面板与节点抽屉
        └── ClashSettingsView.swift     # 订阅链接录入与设置弹窗
```

---

## 5. 开发里程碑与实施步骤

1. **阶段一：数据模型与底层服务 (P0)**
   * 实现 `ClashPreferences` 与本地持久化存储；
   * 实现 `SystemProxyManager`，完成网络服务的自动探测与系统代理切换；
   * 实现 `ClashConfigManager`，支持通过 URL 拉取配置并自动注入本地控制项。
2. **阶段二：内核守护与 REST 通信 (P0)**
   * 实现 `ClashDaemonService`，下载/部署 `mihomo` 二进制并成功运行内核；
   * 实现 `MihomoAPIClient`，验证模式切换、节点获取、延迟测试与实时网速获取。
3. **阶段三：UI 组件集成 (P1)**
   * 在菜单栏集成实时网速与状态显示；
   * 完成下拉主视图与节点选择面板开发；
   * 提供订阅更新界面与状态反馈。
4. **阶段四：全链路联调与异常防御 (P0)**
   * 注册退出回调，彻底杜绝意外关闭导致的系统断网；
   * 测试断网重连、订阅解析容错与崩溃自愈。

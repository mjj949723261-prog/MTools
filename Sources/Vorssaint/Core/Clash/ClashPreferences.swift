// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine

public final class ClashPreferences: ObservableObject {
    public static let shared = ClashPreferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let subscriptionURL = "vorssaint_clash_subscription_url"
        static let lastUpdatedTime = "vorssaint_clash_last_updated"
        static let mixedPort = "vorssaint_clash_mixed_port"
        static let controllerPort = "vorssaint_clash_controller_port"
        static let controllerSecret = "vorssaint_clash_controller_secret"
        static let autoStartCore = "vorssaint_clash_auto_start"
        static let showProxyMenuBar = "vorssaint_clash_show_proxy_menu_bar"
        static let systemProxyEnabled = "vorssaint_clash_system_proxy_enabled"
        static let selectedMode = "vorssaint_clash_mode"
        static let subscriptionUsage = "vorssaint_clash_subscription_usage"
        static let tunEnabled = "vorssaint_clash_tun_enabled"
        static let tunStack = "vorssaint_clash_tun_stack"
        static let tunAutoRoute = "vorssaint_clash_tun_auto_route"
        static let tunAutoDetectInterface = "vorssaint_clash_tun_auto_detect_interface"
        static let tunDNSHijack = "vorssaint_clash_tun_dns_hijack"
        static let dnsEnabled = "vorssaint_clash_dns_enabled"
        static let dnsListenPort = "vorssaint_clash_dns_listen_port"
        static let ipv6Enabled = "vorssaint_clash_ipv6_enabled"
    }

    @Published public var subscriptionURL: String {
        didSet { defaults.set(subscriptionURL, forKey: Keys.subscriptionURL) }
    }

    @Published public var lastUpdatedTime: Date? {
        didSet { defaults.set(lastUpdatedTime, forKey: Keys.lastUpdatedTime) }
    }

    @Published public var mixedPort: Int {
        didSet { defaults.set(mixedPort, forKey: Keys.mixedPort) }
    }

    @Published public var controllerPort: Int {
        didSet { defaults.set(controllerPort, forKey: Keys.controllerPort) }
    }

    @Published public private(set) var controllerSecret: String {
        didSet { defaults.set(controllerSecret, forKey: Keys.controllerSecret) }
    }

    @Published public var autoStartCore: Bool {
        didSet { defaults.set(autoStartCore, forKey: Keys.autoStartCore) }
    }

    @Published public var showProxyMenuBar: Bool {
        didSet { defaults.set(showProxyMenuBar, forKey: Keys.showProxyMenuBar) }
    }

    @Published public var systemProxyEnabled: Bool {
        didSet { defaults.set(systemProxyEnabled, forKey: Keys.systemProxyEnabled) }
    }

    @Published public var selectedMode: ClashMode {
        didSet { defaults.set(selectedMode.rawValue, forKey: Keys.selectedMode) }
    }

    @Published public var subscriptionUsage: SubscriptionUsage? {
        didSet {
            if let data = try? JSONEncoder().encode(subscriptionUsage) {
                defaults.set(data, forKey: Keys.subscriptionUsage)
            } else {
                defaults.removeObject(forKey: Keys.subscriptionUsage)
            }
        }
    }

    @Published public var tunEnabled: Bool {
        didSet { defaults.set(tunEnabled, forKey: Keys.tunEnabled) }
    }

    @Published public var tunStack: ClashTunStack {
        didSet { defaults.set(tunStack.rawValue, forKey: Keys.tunStack) }
    }

    @Published public var tunAutoRoute: Bool {
        didSet { defaults.set(tunAutoRoute, forKey: Keys.tunAutoRoute) }
    }

    @Published public var tunAutoDetectInterface: Bool {
        didSet { defaults.set(tunAutoDetectInterface, forKey: Keys.tunAutoDetectInterface) }
    }

    @Published public var tunDNSHijack: String {
        didSet { defaults.set(tunDNSHijack, forKey: Keys.tunDNSHijack) }
    }

    @Published public var dnsEnabled: Bool {
        didSet { defaults.set(dnsEnabled, forKey: Keys.dnsEnabled) }
    }

    @Published public var dnsListenPort: Int {
        didSet { defaults.set(dnsListenPort, forKey: Keys.dnsListenPort) }
    }

    @Published public var ipv6Enabled: Bool {
        didSet { defaults.set(ipv6Enabled, forKey: Keys.ipv6Enabled) }
    }

    private init() {
        self.subscriptionURL = defaults.string(forKey: Keys.subscriptionURL) ?? ""
        self.lastUpdatedTime = defaults.object(forKey: Keys.lastUpdatedTime) as? Date

        let savedMixedPort = defaults.integer(forKey: Keys.mixedPort)
        let mixedPort = savedMixedPort > 0 ? savedMixedPort : 17892
        let resolvedMixedPort = mixedPort == 7892 ? 17892 : mixedPort
        self.mixedPort = resolvedMixedPort
        if resolvedMixedPort != savedMixedPort, savedMixedPort > 0 {
            defaults.set(resolvedMixedPort, forKey: Keys.mixedPort)
        }

        let savedControllerPort = defaults.integer(forKey: Keys.controllerPort)
        let controllerPort = savedControllerPort > 0 ? savedControllerPort : 19092
        let resolvedControllerPort = controllerPort == 9092 ? 19092 : controllerPort
        self.controllerPort = resolvedControllerPort
        if resolvedControllerPort != savedControllerPort, savedControllerPort > 0 {
            defaults.set(resolvedControllerPort, forKey: Keys.controllerPort)
        }

        let controllerSecret = defaults.string(forKey: Keys.controllerSecret)
            ?? Self.makeControllerSecret()
        self.controllerSecret = controllerSecret
        defaults.set(controllerSecret, forKey: Keys.controllerSecret)

        self.autoStartCore = defaults.bool(forKey: Keys.autoStartCore)
        self.showProxyMenuBar = defaults.object(forKey: Keys.showProxyMenuBar) == nil
            ? true : defaults.bool(forKey: Keys.showProxyMenuBar)
        self.systemProxyEnabled = defaults.bool(forKey: Keys.systemProxyEnabled)
        self.subscriptionUsage = defaults.data(forKey: Keys.subscriptionUsage)
            .flatMap { try? JSONDecoder().decode(SubscriptionUsage.self, from: $0) }
        self.tunEnabled = defaults.bool(forKey: Keys.tunEnabled)
        // Match FlClash's desktop Mihomo profile defaults where they are
        // compatible with this app's isolated ports and manually controlled TUN.
        self.tunStack = defaults.string(forKey: Keys.tunStack).flatMap(ClashTunStack.init(rawValue:)) ?? .mixed
        self.tunAutoRoute = defaults.object(forKey: Keys.tunAutoRoute) == nil
            ? false : defaults.bool(forKey: Keys.tunAutoRoute)
        self.tunAutoDetectInterface = defaults.object(forKey: Keys.tunAutoDetectInterface) == nil
            ? true : defaults.bool(forKey: Keys.tunAutoDetectInterface)
        self.tunDNSHijack = defaults.string(forKey: Keys.tunDNSHijack) ?? "any:53"
        self.dnsEnabled = defaults.object(forKey: Keys.dnsEnabled) == nil ? true : defaults.bool(forKey: Keys.dnsEnabled)
        let savedDNSPort = defaults.integer(forKey: Keys.dnsListenPort)
        // Keep the Developer resolver isolated from FlClash's local DNS ports.
        self.dnsListenPort = savedDNSPort > 0 && savedDNSPort != 7874 && savedDNSPort != 1053 ? savedDNSPort : 17774
        self.ipv6Enabled = defaults.bool(forKey: Keys.ipv6Enabled)

        if let modeRaw = defaults.string(forKey: Keys.selectedMode),
           let mode = ClashMode(rawValue: modeRaw) {
            self.selectedMode = mode
        } else {
            self.selectedMode = .rule
        }
    }

    private static func makeControllerSecret() -> String {
        (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
}

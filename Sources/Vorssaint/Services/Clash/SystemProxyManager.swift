// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Changes only the primary network service and restores its previous proxy
/// settings only while the active values still belong to this core.
public final class SystemProxyManager {
    public static let shared = SystemProxyManager()
    private let operationQueue = DispatchQueue(label: "com.vorssaint.clash.system-proxy", qos: .userInitiated)
    private static let snapshotKey = "vorssaint_clash_system_proxy_snapshot_v2"
    private static let schemes: [(name: String, set: String, get: String, state: String)] = [
        ("web", "-setwebproxy", "-getwebproxy", "-setwebproxystate"),
        ("secureweb", "-setsecurewebproxy", "-getsecurewebproxy", "-setsecurewebproxystate"),
        ("socksfirewall", "-setsocksfirewallproxy", "-getsocksfirewallproxy", "-setsocksfirewallproxystate"),
    ]

    private struct ProxyState: Codable {
        var enabled: Bool
        var server: String
        var port: Int
    }

    private struct Snapshot: Codable {
        var service: String
        var states: [String: ProxyState]
    }

    private init() {}

    public func getAvailableNetworkServices() -> [String] {
        let lines = runCommand("/usr/sbin/networksetup", ["-listallnetworkservices"]).components(separatedBy: .newlines)
        return lines.compactMap { line in
            let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("*"), !name.contains("An asterisk") else { return nil }
            return name
        }
    }

    public func getPrimaryNetworkService() -> String {
        let services = getAvailableNetworkServices()
        return services.first(where: { $0 == "Wi-Fi" }) ?? services.first ?? "Wi-Fi"
    }

    public func enableSystemProxy(host: String = "127.0.0.1", port: Int = 17892) {
        let service = getPrimaryNetworkService()
        var snapshot = loadSnapshot()
        if snapshot == nil || snapshot?.service != service {
            snapshot = Snapshot(service: service, states: Dictionary(uniqueKeysWithValues: Self.schemes.map {
                ($0.name, readState(scheme: $0, service: service))
            }))
            saveSnapshot(snapshot)
        }

        for scheme in Self.schemes {
            _ = runCommand("/usr/sbin/networksetup", [scheme.set, service, host, String(port)])
            _ = runCommand("/usr/sbin/networksetup", [scheme.state, service, "on"])
        }
    }

    public func enableSystemProxyAsync(port: Int, completion: @escaping () -> Void) {
        operationQueue.async {
            self.enableSystemProxy(port: port)
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// Restore the captured configuration only for proxy types still pointing
    /// at our loopback port. A change to another port (such as FlClash's 7890)
    /// is treated as a newer owner and is left untouched.
    public func disableSystemProxy() {
        guard let snapshot = loadSnapshot() else { return }
        let ownPort = ClashPreferences.shared.mixedPort
        for scheme in Self.schemes {
            let current = readState(scheme: scheme, service: snapshot.service)
            guard current.enabled, current.server == "127.0.0.1", current.port == ownPort else { continue }
            if let previous = snapshot.states[scheme.name], previous.enabled,
               !previous.server.isEmpty, previous.port > 0 {
                _ = runCommand("/usr/sbin/networksetup", [scheme.set, snapshot.service,
                                                           previous.server, String(previous.port)])
                _ = runCommand("/usr/sbin/networksetup", [scheme.state, snapshot.service, "on"])
            } else {
                _ = runCommand("/usr/sbin/networksetup", [scheme.state, snapshot.service, "off"])
            }
        }
        saveSnapshot(nil)
    }

    public func disableSystemProxyAsync(completion: (() -> Void)? = nil) {
        operationQueue.async {
            self.disableSystemProxy()
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    public func isSystemProxyEnabled() -> Bool {
        guard let web = Self.schemes.first(where: { $0.name == "web" }) else { return false }
        return readState(scheme: web, service: getPrimaryNetworkService()).enabled
    }

    public func isProxyUsingPortAsync(_ port: Int, completion: @escaping (Bool) -> Void) {
        operationQueue.async {
            let service = self.getPrimaryNetworkService()
            let enabled = Self.schemes.allSatisfy { scheme in
                let state = self.readState(scheme: scheme, service: service)
                return state.enabled && state.server == "127.0.0.1" && state.port == port
            }
            DispatchQueue.main.async { completion(enabled) }
        }
    }

    private func readState(scheme: (name: String, set: String, get: String, state: String), service: String) -> ProxyState {
        let output = runCommand("/usr/sbin/networksetup", [scheme.get, service])
        func value(_ key: String) -> String? {
            output.components(separatedBy: .newlines).first(where: { $0.hasPrefix(key + ":") })?
                .split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return ProxyState(enabled: value("Enabled")?.lowercased() == "yes",
                          server: value("Server") ?? "",
                          port: Int(value("Port") ?? "") ?? 0)
    }

    private func loadSnapshot() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func saveSnapshot(_ snapshot: Snapshot?) {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else {
            UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.snapshotKey)
    }

    @discardableResult
    private func runCommand(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

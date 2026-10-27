// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

public final class ClashConfigManager {
    public static let shared = ClashConfigManager()

    public var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = Bundle.main.bundleIdentifier == "com.vorssaint.utils.dev"
            ? "Vorssaint Developer/Clash" : "Vorssaint/Clash"
        return appSupport.appendingPathComponent(directory, isDirectory: true)
    }

    public var configDirectory: URL {
        baseDirectory.appendingPathComponent("config", isDirectory: true)
    }

    public var configFileURL: URL {
        configDirectory.appendingPathComponent("config.yaml")
    }

    public var mihomoExecutableURL: URL {
        ClashPreferences.shared.tunEnabled ? tunMihomoExecutableURL : regularMihomoExecutableURL
    }

    public var regularMihomoExecutableURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Mihomo/mihomo")
    }

    public var tunMihomoExecutableURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Mihomo/mihomo-tun")
    }

    private init() {
        createDirectoriesIfNeeded()
    }

    public func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        migrateSharedDeveloperConfigIfNeeded()
    }

    /// Earlier Developer builds shared the official app's support directory.
    /// Copy once into the isolated Developer directory; never write back to the
    /// official app's config.
    private func migrateSharedDeveloperConfigIfNeeded() {
        guard Bundle.main.bundleIdentifier == "com.vorssaint.utils.dev" else { return }
        let shared = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Vorssaint/Clash", isDirectory: true)
        let sharedConfig = shared.appendingPathComponent("config/config.yaml")
        if !FileManager.default.fileExists(atPath: configFileURL.path),
           let yaml = try? String(contentsOf: sharedConfig, encoding: .utf8) {
            let normalized = applyingLocalSettings(to: yaml)
            try? normalized.write(to: configFileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Rewrites only local root-level controls, removing older duplicate keys
    /// first. Nested keys such as DNS or TUN settings remain untouched.
    private func applyingLocalSettings(to yaml: String) -> String {
        let mixedPort = ClashPreferences.shared.mixedPort
        let overrides = [
            "port: \(mixedPort - 2)",
            "socks-port: \(mixedPort - 1)",
            "mixed-port: \(mixedPort)",
            "allow-lan: false",
            "mode: \(ClashPreferences.shared.selectedMode.rawValue)",
            "log-level: info",
            "external-controller: 127.0.0.1:\(ClashPreferences.shared.controllerPort)",
            "secret: \"\(ClashPreferences.shared.controllerSecret)\"",
        ]
        var keys = Set(overrides.compactMap { $0.split(separator: ":", maxSplits: 1).first.map(String.init) })
        // Subscription templates often carry 7892/7893 redirect listeners.
        // This app uses a mixed port and TUN, so keeping those listeners can
        // collide with the separately installed FlClash core.
        keys.formUnion(["redir-port", "tproxy-port"])
        let rawLines = yaml.components(separatedBy: .newlines)
        let body = rawLines.filter { line in
            guard !line.isEmpty, !line.first!.isWhitespace, !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: ":") else { return true }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            return !keys.contains(key)
        }
        let preferences = ClashPreferences.shared
        let configuredBody = Self.configuringTun(in: body,
                                                enabled: preferences.tunEnabled,
                                                stack: preferences.tunStack,
                                                autoRoute: preferences.tunAutoRoute,
                                                autoDetectInterface: preferences.tunAutoDetectInterface,
                                                dnsHijack: preferences.tunDNSHijack)
            .joined(separator: "\n")
        let finalBody = Self.configuringDNS(in: configuredBody.components(separatedBy: .newlines),
                                            enabled: preferences.dnsEnabled,
                                            listenPort: preferences.dnsListenPort,
                                            ipv6: preferences.ipv6Enabled)
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return overrides.joined(separator: "\n") + "\n\n" + finalBody + "\n"
    }

    /// Keep FlClash-style DNS controls editable while preserving subscription
    /// resolver lists and policies. The listener uses a Developer-only port.
    private static func configuringDNS(in lines: [String], enabled: Bool, listenPort: Int, ipv6: Bool) -> [String] {
        var prefix: [String] = []
        var block: [String] = []
        var suffix: [String] = []
        var found = false
        var ended = false
        for line in lines {
            let isRoot = !line.isEmpty && !line.first!.isWhitespace && !line.hasPrefix("#")
            let isDNS = isRoot && line.split(separator: ":", maxSplits: 1).first.map(String.init) == "dns"
            if isDNS, !found {
                found = true
                block = ["dns:"]
                ended = false
                continue
            }
            if found && !ended {
                if isRoot { ended = true; suffix.append(line) }
                else { block.append(line) }
            } else if found { suffix.append(line) }
            else { prefix.append(line) }
        }
        if !found { block = ["dns:"] }
        let controlled: Set<String> = ["enable", "listen", "ipv6"]
        var preserved: [String] = []
        for line in block.dropFirst() {
            let indent = line.prefix(while: \.isWhitespace).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 2, let colon = trimmed.firstIndex(of: ":"), controlled.contains(String(trimmed[..<colon])) { continue }
            preserved.append(line)
        }
        block = ["dns:", "  enable: \(enabled ? "true" : "false")", "  listen: 127.0.0.1:\(listenPort)", "  ipv6: \(ipv6 ? "true" : "false")"]
            + Self.isolatingProxyServerNameserver(preserved)
        return prefix + block + suffix
    }

    /// Subscription profiles generated for FlClash can point proxy-node DNS
    /// at FlClash's local resolver (7874). Developer has its own resolver and
    /// must remain usable when FlClash is stopped, so resolve proxy servers
    /// through the same public DoT providers already used by this profile.
    private static func isolatingProxyServerNameserver(_ lines: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let indent = line.prefix(while: \.isWhitespace).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let key = trimmed.split(separator: ":", maxSplits: 1).first.map(String.init)
            guard indent == 2, key == "proxy-server-nameserver" else {
                result.append(line)
                index += 1
                continue
            }

            var end = index + 1
            while end < lines.count {
                let candidate = lines[end]
                let candidateIndent = candidate.prefix(while: \.isWhitespace).count
                if !candidate.isEmpty && candidateIndent <= 2 && !candidate.hasPrefix("#") { break }
                end += 1
            }
            let nameserverBlock = lines[index..<end]
            let usesFlClashDNS = nameserverBlock.contains { candidate in
                candidate.localizedCaseInsensitiveContains("127.0.0.1:7874")
                    || candidate.localizedCaseInsensitiveContains("localhost:7874")
            }
            if usesFlClashDNS {
                result.append("  proxy-server-nameserver:")
                result.append("    - tls://119.29.29.29")
                result.append("    - tls://223.5.5.5")
                index = end
            } else {
                result.append(contentsOf: nameserverBlock)
                index = end
            }
        }
        return result
    }

    private static func configuringTun(in lines: [String],
                                       enabled: Bool,
                                       stack: ClashTunStack,
                                       autoRoute: Bool,
                                       autoDetectInterface: Bool,
                                       dnsHijack: String) -> [String] {
        var prefix: [String] = []
        var tunBlock: [String] = []
        var suffix: [String] = []
        var found = false
        var afterBlock = false
        for line in lines {
            let isRoot = !line.isEmpty && !line.first!.isWhitespace && !line.hasPrefix("#")
            let isTun = isRoot && line.split(separator: ":", maxSplits: 1).first.map(String.init) == "tun"
            if isTun, !found {
                found = true
                tunBlock.append("tun:")
                afterBlock = false
                continue
            }
            if found && !afterBlock {
                if isRoot {
                    afterBlock = true
                    suffix.append(line)
                } else {
                    tunBlock.append(line)
                }
            } else if found {
                suffix.append(line)
            } else {
                prefix.append(line)
            }
        }
        guard enabled || found else { return lines }
        if !found {
            tunBlock = ["tun:"]
        }

        let controlledKeys: Set<String> = [
            "enable", "device", "stack", "auto-route", "auto-detect-interface", "dns-hijack",
        ]
        var preserved: [String] = []
        var skippingDNSChildren = false
        for line in tunBlock.dropFirst() {
            let indent = line.prefix(while: \.isWhitespace).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                if !skippingDNSChildren { preserved.append(line) }
                continue
            }
            if indent <= 2 { skippingDNSChildren = false }
            if indent == 2, let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon])
                if controlledKeys.contains(key) {
                    skippingDNSChildren = key == "dns-hijack"
                    continue
                }
            }
            if !skippingDNSChildren { preserved.append(line) }
        }
        let configuredDNSEntries = dnsHijack.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let dnsEntries = configuredDNSEntries.isEmpty ? ["any:53"] : configuredDNSEntries
        tunBlock = [
            "tun:",
            "  enable: \(enabled ? "true" : "false")",
            "  stack: \(stack.rawValue)",
            "  auto-route: \(autoRoute ? "true" : "false")",
            "  auto-detect-interface: \(autoDetectInterface ? "true" : "false")",
            "  dns-hijack:",
        ] + dnsEntries.map { "    - \(Self.yamlQuoted($0))" } + preserved
        return prefix + tunBlock + suffix
    }

    private static func yamlQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Repair configs generated by older builds before asking Mihomo to load
    /// them. This is called only for the current app variant's own directory.
    @discardableResult
    public func normalizeExistingConfig() -> Bool {
        guard let yaml = try? String(contentsOf: configFileURL, encoding: .utf8) else { return false }
        let normalized = applyingLocalSettings(to: yaml)
        guard normalized != yaml else { return true }
        do {
            try normalized.write(to: configFileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Downloads subscription from the provided URL, injects local port configs, and saves config.yaml
    public func updateSubscription(from urlString: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            completion(.failure(NSError(domain: "ClashConfigManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid subscription URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("ClashMeta/v1.18.0 mihomo/v1.18.0 Clash/1.18.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure(NSError(domain: "ClashConfigManager", code: http.statusCode,
                                            userInfo: [NSLocalizedDescriptionKey: "Subscription server returned HTTP \(http.statusCode)"])))
                return
            }

            guard let data = data, var rawYaml = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "ClashConfigManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Empty or invalid response from subscription"])))
                return
            }

            // Check if returned content is Base64 encoded or direct YAML
            if !rawYaml.contains("proxies:") && !rawYaml.contains("proxy-groups:") {
                // If it's pure Base64 (rare for Clash URL requests with Clash UA), check decoded
                if let decodedData = Data(base64Encoded: rawYaml.trimmingCharacters(in: .whitespacesAndNewlines)),
                   let decodedString = String(data: decodedData, encoding: .utf8),
                   decodedString.contains("proxies:") {
                    rawYaml = decodedString
                }
            }

            let finalYaml = self.applyingLocalSettings(to: rawYaml)

            if let http = response as? HTTPURLResponse,
               let usageHeader = http.allHeaderFields.first(where: {
                   String(describing: $0.key).caseInsensitiveCompare("subscription-userinfo") == .orderedSame
               })?.value as? String,
               let usage = SubscriptionUsage.parse(header: usageHeader) {
                DispatchQueue.main.async { ClashPreferences.shared.subscriptionUsage = usage }
            }

            do {
                try finalYaml.write(to: self.configFileURL, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    ClashPreferences.shared.lastUpdatedTime = Date()
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }
}

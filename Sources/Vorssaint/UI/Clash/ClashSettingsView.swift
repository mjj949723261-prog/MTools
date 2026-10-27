// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

public struct ClashSettingsView: View {
    @ObservedObject private var manager = ClashManager.shared
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var addressService = NetworkAddressService()
    @State private var subscriptionURLInput = ""

    public init() {}

    private var currentRoute: String {
        manager.apiClient.currentRouteName
    }

    public var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Circle()
                        .fill(manager.daemon.isRunning ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ClashStrings.text(manager.daemon.isRunning ? "coreRunning" : "coreStopped", l10n.language))
                            .font(.headline)
                        Text(manager.daemon.isRunning ? currentRoute : ClashStrings.description(l10n.language))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button(ClashStrings.text(manager.daemon.isStarting ? "starting" : manager.daemon.isStopping ? "stopping" : manager.daemon.isRunning ? "stop" : "start", l10n.language)) {
                        manager.toggleCore()
                    }
                    .disabled(manager.daemon.isStarting || manager.daemon.isStopping || manager.isChangingTun)
                    .buttonStyle(.borderedProminent)
                    .tint(manager.daemon.isRunning ? .red : .accentColor)
                }
                .padding(.vertical, 4)

                if manager.daemon.isRunning {
                    HStack(spacing: 10) {
                        metricCard(ClashStrings.text("upload", l10n.language), manager.apiClient.currentTraffic.formattedUp, "arrow.up", .orange)
                        metricCard(ClashStrings.text("download", l10n.language), manager.apiClient.currentTraffic.formattedDown, "arrow.down", .blue)
                    }
                    HStack {
                        Text(ClashStrings.text("trafficSession", l10n.language)).foregroundStyle(.secondary)
                        Spacer()
                        Text("↑ \(TrafficRate.formatBytes(manager.apiClient.totalUploaded))  ↓ \(TrafficRate.formatBytes(manager.apiClient.totalDownloaded))")
                            .font(.caption.monospacedDigit())
                    }
                }
            } header: {
                Text(ClashStrings.proxy(l10n.language))
            }

            if manager.daemon.isRunning {
                Section(ClashStrings.text("connection", l10n.language)) {
                    Toggle(ClashStrings.text("systemProxy", l10n.language), isOn: Binding(
                        get: { manager.preferences.systemProxyEnabled },
                        set: { _ in manager.toggleSystemProxy() }
                    ))
                    .disabled(manager.isChangingSystemProxy || manager.daemon.isStarting || manager.daemon.isStopping || manager.isChangingTun)
                    Picker(ClashStrings.text("mode", l10n.language), selection: Binding(
                        get: { manager.preferences.selectedMode },
                        set: { manager.apiClient.setMode($0) }
                    )) {
                        ForEach(ClashMode.allCases, id: \.self) { mode in
                            Text(ClashStrings.text(mode.rawValue, l10n.language)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(ClashStrings.text("network", l10n.language)) {
                    LabeledContent(ClashStrings.text("localIP", l10n.language), value: addressService.localAddresses.joined(separator: ", ").isEmpty ? "—" : addressService.localAddresses.joined(separator: ", "))
                }

                if !manager.apiClient.proxyGroups.isEmpty {
                    Section(ClashStrings.text("routes", l10n.language)) {
                        ForEach(manager.apiClient.proxyGroups) { group in
                            DisclosureGroup {
                                ForEach(group.all, id: \.self) { node in
                                    let delay = manager.apiClient.nodeDelay(node)
                                    Button { manager.apiClient.switchNode(in: group.name, to: node) } label: {
                                        HStack(spacing: 10) {
                                            let tested = manager.apiClient.testedDelayNodes.contains(node)
                                            let unavailable = manager.apiClient.unreachableNodes.contains(node)
                                            Circle().fill(unavailable ? Color.red : tested ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                                            if let flag = Self.regionFlag(for: node) { Text(flag).font(.system(size: 13)) }
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(node).lineLimit(1).font(.system(size: 12, weight: node == group.now ? .semibold : .regular))
                                                Text(unavailable ? ClashStrings.text("unreachable", l10n.language) : tested ? ClashStrings.text("connected", l10n.language) : ClashStrings.text("latencyUnknown", l10n.language))
                                                    .font(.caption2).foregroundStyle(unavailable ? Color.red : tested ? Color.green : Color.secondary)
                                            }
                                            Spacer(minLength: 4)
                                            Text(delay.map { "\($0) ms" } ?? "—")
                                                .font(.caption.monospacedDigit()).foregroundStyle(unavailable ? Color.red : tested ? Color.green : Color.secondary)
                                            if node == group.now { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                                        }
                                        .padding(.vertical, 4).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            } label: {
                                LabeledContent(group.name, value: group.now)
                            }
                        }
                        Button {
                            manager.apiClient.testAllDelays()
                        } label: {
                            if manager.apiClient.isTestingDelays { ProgressView().controlSize(.small) }
                            else { Text(ClashStrings.text("testAllRoutes", l10n.language)) }
                        }
                        .disabled(manager.apiClient.isTestingDelays)
                    }
                }
            }

            Section(ClashStrings.text("connection", l10n.language)) {
                Toggle(ClashStrings.text("virtualNIC", l10n.language), isOn: Binding(
                    get: { manager.preferences.tunEnabled },
                    set: { manager.setTunEnabled($0) }
                ))
                .disabled(manager.daemon.isStarting || manager.daemon.isStopping || manager.isChangingTun)
                Text(ClashStrings.text("tunRestartNote", l10n.language))
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(ClashStrings.text("tunOptions", l10n.language)) {
                    Picker(ClashStrings.text("tunStack", l10n.language), selection: $manager.preferences.tunStack) {
                        Text(ClashStrings.text("stackSystem", l10n.language)).tag(ClashTunStack.system)
                        Text(ClashStrings.text("stackGVisor", l10n.language)).tag(ClashTunStack.gvisor)
                        Text(ClashStrings.text("stackMixed", l10n.language)).tag(ClashTunStack.mixed)
                    }
                    .disabled(manager.daemon.isRunning || manager.isChangingTun)
                    Toggle(ClashStrings.text("autoRoute", l10n.language), isOn: $manager.preferences.tunAutoRoute)
                        .disabled(manager.daemon.isRunning || manager.isChangingTun)
                    Toggle(ClashStrings.text("autoDetectInterface", l10n.language), isOn: $manager.preferences.tunAutoDetectInterface)
                        .disabled(manager.daemon.isRunning || manager.isChangingTun)
                    Text(ClashStrings.text("dnsHijackManaged", l10n.language))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(ClashStrings.text("dnsSection", l10n.language)) {
                DisclosureGroup(ClashStrings.text("dnsAdvanced", l10n.language)) {
                    Toggle(ClashStrings.text("dnsEnabled", l10n.language), isOn: $manager.preferences.dnsEnabled)
                        .disabled(manager.daemon.isRunning || manager.isChangingTun)
                    LabeledContent(ClashStrings.text("dnsPort", l10n.language)) {
                        TextField("17774", value: $manager.preferences.dnsListenPort, format: .number)
                            .frame(width: 90).multilineTextAlignment(.trailing)
                            .disabled(manager.daemon.isRunning || manager.isChangingTun)
                    }
                    Toggle("IPv6", isOn: $manager.preferences.ipv6Enabled)
                        .disabled(manager.daemon.isRunning || manager.isChangingTun)
                    Text(ClashStrings.text("dnsNote", l10n.language))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(ClashStrings.text("trafficUsage", l10n.language)) {
                if let usage = manager.preferences.subscriptionUsage {
                    if let used = usage.used, let total = usage.total {
                        ProgressView(value: usage.fractionUsed ?? 0)
                        LabeledContent(ClashStrings.text("usedTotal", l10n.language), value: "\(TrafficRate.formatBytes(used)) / \(TrafficRate.formatBytes(total))")
                        if let remaining = usage.remaining {
                            LabeledContent(ClashStrings.text("remaining", l10n.language), value: TrafficRate.formatBytes(remaining))
                        }
                    }
                    if let expires = usage.expiresAt {
                        LabeledContent(ClashStrings.text("expires", l10n.language), value: expires.formatted(date: .abbreviated, time: .omitted))
                    }
                } else {
                    Text(ClashStrings.text("noUsage", l10n.language)).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(ClashStrings.text("subscription", l10n.language)) {
                HStack {
                    TextField(ClashStrings.text("subscriptionURL", l10n.language), text: $subscriptionURLInput)
                        .textFieldStyle(.roundedBorder)
                    Button(ClashStrings.text("paste", l10n.language)) {
                        if let value = NSPasteboard.general.string(forType: .string) {
                            subscriptionURLInput = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                HStack {
                    Button {
                        manager.updateSubscription(url: subscriptionURLInput)
                    } label: {
                        if manager.isUpdatingSubscription { ProgressView().controlSize(.small) }
                        else { Text(ClashStrings.text("updateSubscription", l10n.language)) }
                    }
                    .disabled(manager.isUpdatingSubscription || subscriptionURLInput.isEmpty)
                    Spacer()
                    if let updated = manager.preferences.lastUpdatedTime {
                        Text(updated, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section(ClashStrings.text("ports", l10n.language)) {
                LabeledContent(ClashStrings.text("mixedPort", l10n.language)) {
                    TextField("", value: $manager.preferences.mixedPort, format: .number)
                        .frame(width: 90).multilineTextAlignment(.trailing)
                }
                LabeledContent(ClashStrings.text("controllerPort", l10n.language)) {
                    TextField("", value: $manager.preferences.controllerPort, format: .number)
                        .frame(width: 90).multilineTextAlignment(.trailing)
                }
                Text(ClashStrings.text("separatePortsNote", l10n.language))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let status = manager.statusMessage ?? manager.daemon.lastErrorMessage {
                Section {
                    Label(status, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { subscriptionURLInput = manager.preferences.subscriptionURL; addressService.refreshLocalAddresses() }
    }

    private func metricCard(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private static func regionFlag(for name: String) -> String? {
        let value = name.lowercased()
        let tokens = Set(value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if tokens.contains("jp") || value.contains("日本") || value.contains("东京") || value.contains("大阪") { return "🇯🇵" }
        if tokens.contains("hk") || value.contains("香港") { return "🇭🇰" }
        if tokens.contains("tw") || value.contains("台湾") { return "🇹🇼" }
        if tokens.contains("sg") || value.contains("新加坡") { return "🇸🇬" }
        if tokens.contains("us") || value.contains("美国") || value.contains("洛杉矶") { return "🇺🇸" }
        if tokens.contains("kr") || value.contains("韩国") || value.contains("首尔") { return "🇰🇷" }
        return nil
    }
}

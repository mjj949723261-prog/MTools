// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

public struct ClashMenuView: View {
    @ObservedObject private var manager = ClashManager.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var showingSettings: Bool = false
    @State private var selectedGroupIndex: Int = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Header: Status & Master Toggles
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ClashStrings.proxy(l10n.language))
                        .font(.headline)
                    Text(ClashStrings.text(manager.isChangingTun ? "tunChanging" : manager.daemon.isStarting ? "starting" : manager.daemon.isStopping ? "stopping" : manager.daemon.isRunning ? "coreRunning" : "coreStopped", l10n.language))
                        .font(.caption)
                        .foregroundColor(manager.daemon.isRunning ? .green : .secondary)
                }

                Spacer()

                Button(action: {
                    manager.toggleCore()
                }) {
                    Text(ClashStrings.text(manager.daemon.isStarting ? "starting" : manager.daemon.isStopping ? "stopping" : manager.daemon.isRunning ? "stop" : "start", l10n.language))
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                    .disabled(manager.daemon.isStarting || manager.daemon.isStopping || manager.isChangingTun)
                .tint(manager.daemon.isRunning ? .red : .blue)

                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            if manager.daemon.isRunning || manager.isChangingTun {
                HStack(spacing: 12) {
                    Label(manager.apiClient.currentTraffic.formattedUp, systemImage: "arrow.up")
                        .foregroundStyle(.orange)
                    Label(manager.apiClient.currentTraffic.formattedDown, systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                    Spacer(minLength: 0)
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 12)
            }

            if manager.daemon.isRunning || manager.isChangingTun {
                // System Proxy Toggle & Mode Picker
                VStack(spacing: 8) {
                    Toggle(ClashStrings.text("systemProxy", l10n.language), isOn: Binding(
                        get: { manager.preferences.systemProxyEnabled },
                        set: { _ in manager.toggleSystemProxy() }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .disabled(manager.isChangingSystemProxy || manager.daemon.isStarting || manager.daemon.isStopping || manager.isChangingTun)

                    Toggle(ClashStrings.text("virtualNIC", l10n.language), isOn: Binding(
                        get: { manager.preferences.tunEnabled },
                        set: { manager.setTunEnabled($0) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .disabled(manager.daemon.isStarting || manager.daemon.isStopping || manager.isChangingTun)

                    Picker(ClashStrings.text("mode", l10n.language), selection: Binding(
                        get: { manager.preferences.selectedMode },
                        set: { newMode in
                            manager.apiClient.setMode(newMode)
                        }
                    )) {
                        ForEach(ClashMode.allCases, id: \.self) { mode in
                            Text(ClashStrings.text(mode.rawValue, l10n.language)).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.horizontal, 12)

                Divider()

                // Proxy Groups & Nodes
                if !manager.apiClient.proxyGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(ClashStrings.text("proxyGroups", l10n.language))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Button(ClashStrings.text("testLatency", l10n.language)) {
                                for node in manager.apiClient.allNodes {
                                    manager.apiClient.testDelay(for: node.name)
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }

                        // Group Picker
                        if manager.apiClient.proxyGroups.count > 1 {
                            Picker("", selection: $selectedGroupIndex) {
                                ForEach(0..<manager.apiClient.proxyGroups.count, id: \.self) { idx in
                                    Text(manager.apiClient.proxyGroups[idx].name).tag(idx)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }

                        let currentGroup = manager.apiClient.proxyGroups[safe: selectedGroupIndex]

                        ScrollView {
                            LazyVStack(spacing: 4) {
                                if let group = currentGroup {
                                    ForEach(group.all, id: \.self) { nodeName in
                                        let isSelected = group.now == nodeName
                                        let nodeDelay = manager.apiClient.allNodes.first(where: { $0.name == nodeName })?.delay

                                        Button(action: {
                                            manager.apiClient.switchNode(in: group.name, to: nodeName)
                                        }) {
                                            HStack {
                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                                                    .font(.system(size: 12))

                                                Text(nodeName)
                                                    .font(.system(size: 12))
                                                    .lineLimit(1)

                                                Spacer()

                                                if let delay = nodeDelay {
                                                    Text("\(delay) ms")
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundColor(delayColor(delay))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(delayColor(delay).opacity(0.1))
                                                        .cornerRadius(4)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(.horizontal, 12)
                }
            } else {
                VStack(spacing: 8) {
                    Text(ClashStrings.text("noSubscription", l10n.language))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(ClashStrings.text("configureSubscription", l10n.language)) {
                        showingSettings = true
                    }
                    .font(.caption)
                }
                .padding(.vertical, 20)
            }

            if let error = manager.daemon.lastErrorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 12).textSelection(.enabled)
            }

            Spacer(minLength: 8)
        }
        .frame(width: 300)
        .sheet(isPresented: $showingSettings) {
            ClashSettingsView()
        }
    }

    private func delayColor(_ delay: Int) -> Color {
        if delay < 300 {
            return .green
        } else if delay < 800 {
            return .orange
        } else {
            return .red
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

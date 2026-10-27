// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchProxyView: View {
    @ObservedObject private var manager = ClashManager.shared
    @ObservedObject private var l10n = L10n.shared
    let size: CGSize

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(manager.daemon.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(statusTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: manager.toggleCore) {
                    Label(startStopTitle, systemImage: manager.daemon.isRunning ? "stop.fill" : "play.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(manager.daemon.isRunning ? .red : .green)
                .controlSize(.small)
                .disabled(manager.daemon.isStarting || manager.daemon.isStopping)
            }

            routeCard

            HStack(spacing: 10) {
                trafficCard(ClashStrings.text("upload", l10n.language),
                            value: manager.apiClient.currentTraffic.formattedUp,
                            symbol: "arrow.up", tint: .orange)
                trafficCard(ClashStrings.text("download", l10n.language),
                            value: manager.apiClient.currentTraffic.formattedDown,
                            symbol: "arrow.down", tint: .cyan)
            }

            HStack(spacing: 10) {
                switchCard(ClashStrings.text("systemProxy", l10n.language), symbol: "network", isOn: Binding(
                    get: { manager.preferences.systemProxyEnabled },
                    set: { _ in manager.toggleSystemProxy() }
                ), enabled: manager.daemon.isRunning && !manager.isChangingSystemProxy && !manager.isChangingTun
                    && !manager.daemon.isStarting && !manager.daemon.isStopping)

                switchCard(ClashStrings.text("virtualNIC", l10n.language), symbol: "point.3.connected.trianglepath.dotted", isOn: Binding(
                    get: { manager.preferences.tunEnabled },
                    set: { manager.setTunEnabled($0) }
                ), enabled: !manager.isChangingTun && !manager.daemon.isStarting && !manager.daemon.isStopping)
            }

            HStack {
                Spacer()
                Button {
                    SettingsRouter.shared.request(FeatureSettingsDestination(.proxy))
                } label: {
                    Label(ClashStrings.text("proxySettings", l10n.language), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var statusTitle: String {
        ClashStrings.text(manager.isChangingTun ? "tunChanging"
            : manager.daemon.isStarting ? "starting"
            : manager.daemon.isStopping ? "stopping"
            : manager.daemon.isRunning ? "coreRunning" : "coreStopped", l10n.language)
    }

    private var startStopTitle: String {
        ClashStrings.text(manager.daemon.isStarting ? "starting"
            : manager.daemon.isStopping ? "stopping"
            : manager.daemon.isRunning ? "stop" : "start", l10n.language)
    }

    private var routeCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.cyan)
            Text(ClashStrings.text("routes", l10n.language))
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 14)
            Text(manager.apiClient.currentRouteName)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private func trafficCard(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private func switchCard(_ title: String, symbol: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        HStack(spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
                .controlSize(.small)
                .fixedSize()
                .disabled(!enabled)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

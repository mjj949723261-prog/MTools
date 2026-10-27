// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A deliberately small, lock-screen-safe summary. Public IP details stay on
/// the expanded proxy page.
struct NotchProxyActivityStrip: View {
    @ObservedObject private var manager = ClashManager.shared
    let size: CGSize

    private var route: String {
        manager.apiClient.currentRouteName
    }

    private var shortRoute: String {
        route.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? route
    }

    private var isCompact: Bool { size.width < 160 }

    var body: some View {
        HStack(spacing: isCompact ? 3 : 6) {
            Circle().fill(manager.daemon.isRunning ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(isCompact ? shortRoute : route)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: isCompact ? 24 : 60, maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
            rate(manager.apiClient.currentTraffic.formattedUp, symbol: "arrow.up")
            rate(manager.apiClient.currentTraffic.formattedDown, symbol: "arrow.down")
        }
        .padding(.horizontal, isCompact ? 6 : 9)
        .frame(width: max(100, size.width), height: max(22, size.height))
        .contentShape(Rectangle())
        .help("\(ClashStrings.proxy(L10n.shared.language)) · \(route) · ↑ \(manager.apiClient.currentTraffic.formattedUp) · ↓ \(manager.apiClient.currentTraffic.formattedDown)")
    }

    private func rate(_ value: String, symbol: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.85))
        }
        .fixedSize()
    }
}

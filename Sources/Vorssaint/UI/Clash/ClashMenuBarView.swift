// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

public struct ClashMenuBarView: View {
    @ObservedObject private var manager = ClashManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(manager.daemon.isRunning ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)

            if manager.daemon.isRunning {
                VStack(alignment: .leading, spacing: 0) {
                    Text("↑ \(manager.apiClient.currentTraffic.formattedUp)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                    Text("↓ \(manager.apiClient.currentTraffic.formattedDown)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                }
            } else {
                Image(systemName: "paperplane")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(.horizontal, 4)
    }
}

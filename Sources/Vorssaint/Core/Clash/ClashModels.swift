// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

public enum ClashMode: String, Codable, CaseIterable {
    case rule = "rule"
    case global = "global"
    case direct = "direct"

    public var displayName: String {
        switch self {
        case .rule: return "Rule"
        case .global: return "Global"
        case .direct: return "Direct"
        }
    }
}

public enum ClashTunStack: String, Codable, CaseIterable, Identifiable {
    case system
    case gvisor
    case mixed

    public var id: String { rawValue }
}

public struct ProxyNode: Identifiable, Codable, Equatable {
    public var id: String { name }
    public let name: String
    public let type: String
    public var delay: Int?
    public var isSelected: Bool = false

    public init(name: String, type: String, delay: Int? = nil, isSelected: Bool = false) {
        self.name = name
        self.type = type
        self.delay = delay
        self.isSelected = isSelected
    }
}

public struct ProxyGroup: Identifiable, Codable {
    public var id: String { name }
    public let name: String
    public let type: String
    public var now: String
    public var all: [String]

    public init(name: String, type: String, now: String, all: [String]) {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
    }
}

public struct TrafficRate: Codable, Equatable {
    public let up: Int64
    public let down: Int64

    public init(up: Int64 = 0, down: Int64 = 0) {
        self.up = up
        self.down = down
    }

    public var formattedUp: String {
        Self.formatBytes(up) + "/s"
    }

    public var formattedDown: String {
        Self.formatBytes(down) + "/s"
    }

    /// Compact binary-rate label for the narrow menu-bar and Dynamic Island
    /// surfaces. The arrows provide direction; full panels use formattedUp/Down.
    public static func compactRate(_ bytesPerSecond: Int64) -> String {
        let bytes = Double(max(0, bytesPerSecond))
        if bytes >= 1024 * 1024 {
            return String(format: "%.1fM", bytes / (1024 * 1024))
        } else if bytes >= 1024 {
            return String(format: "%.1fK", bytes / 1024)
        }
        return String(format: "%.0f", bytes)
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024 {
            return String(format: "%.0f B", b)
        } else if b < 1024 * 1024 {
            return String(format: "%.1f KB", b / 1024.0)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", b / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f GB", b / (1024.0 * 1024.0 * 1024.0))
        }
    }
}

public struct SubscriptionUsage: Codable, Equatable {
    public let upload: Int64?
    public let download: Int64?
    public let total: Int64?
    public let expiresAt: Date?

    public init(upload: Int64?, download: Int64?, total: Int64?, expiresAt: Date?) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expiresAt = expiresAt
    }

    public var used: Int64? {
        guard let upload, let download else { return nil }
        return upload + download
    }

    public var remaining: Int64? {
        guard let total, let used else { return nil }
        return max(0, total - used)
    }

    public var fractionUsed: Double? {
        guard let total, total > 0, let used else { return nil }
        return min(1, Double(used) / Double(total))
    }

    public static func parse(header: String) -> SubscriptionUsage? {
        var values: [String: Int64] = [:]
        for field in header.split(separator: ";") {
            let pair = field.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let value = Int64(pair[1]), value >= 0 else { continue }
            values[pair[0].lowercased()] = value
        }
        guard !values.isEmpty else { return nil }
        let expires = values["expire"].map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return SubscriptionUsage(upload: values["upload"], download: values["download"],
                                 total: values["total"], expiresAt: expires)
    }
}

public struct TrafficSample: Codable, Equatable, Identifiable {
    public let date: Date
    public let upload: Int64
    public let download: Int64
    public var id: Date { date }

    public init(date: Date = .now, upload: Int64, download: Int64) {
        self.date = date
        self.upload = upload
        self.download = download
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import Combine

public final class ClashStatusItemController: NSObject {
    public static let shared = ClashStatusItemController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
    }

    public func setup() {
        guard AppFeature.proxy.isAvailable,
              ClashPreferences.shared.showProxyMenuBar,
              statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageLeading
            button.font = .monospacedSystemFont(ofSize: 10, weight: .medium)

            ClashDaemonService.shared.$isRunning
                .combineLatest(MihomoAPIClient.shared.$currentTraffic)
                .receive(on: RunLoop.main)
                .sink { [weak self] _, _ in self?.updateStatusButton() }
                .store(in: &cancellables)
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 380)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ClashMenuView())

        self.statusItem = item
        self.popover = popover
        updateStatusButton()
    }

    public func tearDown() {
        cancellables.removeAll()
        popover?.performClose(nil)
        popover = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        let daemon = ClashDaemonService.shared
        button.image = NSImage(systemSymbolName: daemon.isRunning ? "arrow.up.arrow.down" : "paperplane",
                               accessibilityDescription: nil)
        button.image?.isTemplate = true
        button.title = daemon.isRunning
            ? "↑ \(MihomoAPIClient.shared.currentTraffic.formattedUp)  ↓ \(MihomoAPIClient.shared.currentTraffic.formattedDown)"
            : ""
        button.toolTip = daemon.isRunning ? ClashStrings.text("coreRunning", L10n.shared.language) : ClashStrings.text("coreStopped", L10n.shared.language)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async {
                guard popover.isShown else { return }
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}

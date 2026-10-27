// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine

public final class ClashManager: ObservableObject {
    public static let shared = ClashManager()

    @Published public var daemon = ClashDaemonService.shared
    @Published public var apiClient = MihomoAPIClient.shared
    @Published public var preferences = ClashPreferences.shared
    @Published public var isUpdatingSubscription: Bool = false
    @Published public var statusMessage: String?
    @Published public private(set) var isChangingSystemProxy = false
    @Published public private(set) var isChangingTun = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        daemon.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        apiClient.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        preferences.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        refreshSystemProxyState()
        Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshSystemProxyState() }
            .store(in: &cancellables)
    }

    private func refreshSystemProxyState() {
        SystemProxyManager.shared.isProxyUsingPortAsync(preferences.mixedPort) { [weak self] enabled in
            guard let self, !self.isChangingSystemProxy,
                  self.preferences.systemProxyEnabled != enabled else { return }
            self.preferences.systemProxyEnabled = enabled
        }
    }

    /// Toggles the proxy core on/off
    public func toggleCore() {
        guard !daemon.isStarting, !daemon.isStopping else { return }
        if daemon.isRunning {
            daemon.stopCore()
        } else {
            daemon.startCore(enableTun: preferences.tunEnabled) { [weak self] success in
                if !success {
                    self?.statusMessage = self?.daemon.lastErrorMessage
                }
            }
        }
    }

    /// Toggles the macOS system proxy on/off
    public func toggleSystemProxy() {
        guard !isChangingSystemProxy else { return }
        let newState = !preferences.systemProxyEnabled
        isChangingSystemProxy = true
        if newState {
            SystemProxyManager.shared.enableSystemProxyAsync(port: preferences.mixedPort) { [weak self] in
                self?.preferences.systemProxyEnabled = true
                self?.isChangingSystemProxy = false
            }
        } else {
            SystemProxyManager.shared.disableSystemProxyAsync { [weak self] in
                self?.preferences.systemProxyEnabled = false
                self?.isChangingSystemProxy = false
            }
        }
    }

    /// TUN requires the core to run with administrator privileges. Changing
    /// it while running restarts only this app's core and preserves the
    /// independent system-proxy switch.
    public func setTunEnabled(_ enabled: Bool) {
        guard !isChangingTun, !daemon.isStarting, !daemon.isStopping,
              preferences.tunEnabled != enabled else { return }
        guard daemon.isRunning else {
            preferences.tunEnabled = enabled
            return
        }

        let previousValue = preferences.tunEnabled
        let systemProxyWasEnabled = preferences.systemProxyEnabled
        isChangingTun = true
        statusMessage = nil
        daemon.stopCore(preservingSystemProxy: true) { [weak self] in
            guard let self else { return }
            self.preferences.tunEnabled = enabled
            self.daemon.startCore(enableTun: enabled) { [weak self] success in
                guard let self else { return }
                if success {
                    self.isChangingTun = false
                    return
                }

                let switchError = self.daemon.lastErrorMessage
                self.preferences.tunEnabled = previousValue
                self.daemon.startCore(enableTun: previousValue) { [weak self] restored in
                    guard let self else { return }
                    self.isChangingTun = false
                    self.statusMessage = restored
                        ? switchError
                        : "\(switchError ?? ClashStrings.text("startFailed", L10n.shared.language)) · \(ClashStrings.text("coreStopped", L10n.shared.language))"
                    if !restored && systemProxyWasEnabled {
                        SystemProxyManager.shared.disableSystemProxyAsync {
                            self.preferences.systemProxyEnabled = false
                        }
                    }
                }
            }
        }
    }

    /// Updates the subscription config
    public func updateSubscription(url: String) {
        guard !url.isEmpty else {
            statusMessage = ClashStrings.text("invalidURL", L10n.shared.language)
            return
        }

        isUpdatingSubscription = true
        statusMessage = ClashStrings.text("updating", L10n.shared.language)

        ClashConfigManager.shared.updateSubscription(from: url) { [weak self] result in
            DispatchQueue.main.async {
                self?.isUpdatingSubscription = false
                switch result {
                case .success:
                    self?.preferences.subscriptionURL = url
                    self?.statusMessage = ClashStrings.text("updated", L10n.shared.language)
                    if self?.daemon.isRunning == true {
                        // Keep the user's explicit system-proxy choice while
                        // the updated profile is applied.
                        let tunEnabled = self?.preferences.tunEnabled ?? false
                        self?.daemon.stopCore(preservingSystemProxy: true) {
                            self?.daemon.startCore(enableTun: tunEnabled)
                        }
                    }
                case .failure(let error):
                    self?.statusMessage = "\(ClashStrings.text("updateFailed", L10n.shared.language)): \(error.localizedDescription)"
                }
            }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine
import AppKit

public final class ClashDaemonService: ObservableObject {
    public static let shared = ClashDaemonService()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isStarting: Bool = false
    @Published public private(set) var isStopping: Bool = false
    @Published public var lastErrorMessage: String?

    private var process: Process?
    private var outputLogHandle: FileHandle?
    private var startCancelled = false
    private var privilegedPID: Int32?
    private var adoptedPID: Int32?
    private var adoptedProcessIsRoot = false
    private let controllerSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    private init() {
        registerTerminationHooks()
        adoptExistingDeveloperCoreIfPresent()
    }

    /// Reconnect to this app's bundled core if it outlived the GUI process.
    private func adoptExistingDeveloperCoreIfPresent() {
        let configManager = ClashConfigManager.shared
        // Resolve preferences and paths before leaving the main thread. The
        // menu-bar controller initializes ClashManager during app launch; if
        // this background block wins ClashPreferences' static initialization,
        // UserDefaults/Combine initialization can synchronously wait on the
        // main run loop while the main thread waits for this once token.
        let binaryPath = configManager.mihomoExecutableURL.path
        let configPath = configManager.configDirectory.path
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self,
                  let (pid, uid) = Self.findRunningCore(binary: binaryPath,
                                                       configDirectory: configPath) else { return }
            DispatchQueue.main.async {
                guard !self.isRunning, !self.isStarting else { return }
                self.adoptedPID = pid
                self.adoptedProcessIsRoot = uid == 0
                self.privilegedPID = uid == 0 ? pid : nil
                self.waitForControllerReady(attemptsRemaining: 5) { ready in
                    guard ready else {
                        self.adoptedPID = nil
                        self.adoptedProcessIsRoot = false
                        self.privilegedPID = nil
                        return
                    }
                    self.isRunning = true
                    self.lastErrorMessage = nil
                    MihomoAPIClient.shared.startPolling()
                    self.refreshIslandActivity()
                }
            }
        }
    }

    private static func findRunningCore(binary: String,
                                        configDirectory: String) -> (pid: Int32, uid: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,uid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let listing = String(data: output, encoding: .utf8) else { return nil }
            let marker = "\(binary) -d \(configDirectory)"
            for line in listing.split(whereSeparator: \.isNewline) {
                let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                guard fields.count == 3,
                      let pid = Int32(fields[0]),
                      let uid = Int32(fields[1]),
                      fields[2].hasPrefix(marker) else { continue }
                return (pid, uid)
            }
        } catch { }
        return nil
    }

    deinit {
        stopCore()
    }

    private func registerTerminationHooks() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // applicationShouldTerminate waits for stopCore before allowing a
            // normal quit. Keep this notification observer as a fallback.
            self?.stopCore()
            SystemProxyManager.shared.disableSystemProxyAsync()
        }
    }

    /// Starts the mihomo core process
    public func startCore(enableTun: Bool = false,
                          completion: ((Bool) -> Void)? = nil) {
        guard !isRunning else {
            completion?(true)
            return
        }
        guard !isStarting else { return }
        // Ordinary Start always stays unprivileged. TUN can only be enabled
        // through the explicit virtual-NIC action, which passes enableTun.
        ClashPreferences.shared.tunEnabled = enableTun
        // This service owns only the Developer Mihomo config directory and
        // its own proxy snapshot. FlClash is deliberately never inspected,
        // stopped, reopened, or otherwise managed here.
        let configManager = ClashConfigManager.shared
        if let (pid, uid) = Self.findRunningCore(binary: configManager.mihomoExecutableURL.path,
                                                 configDirectory: configManager.configDirectory.path) {
            // A prior start can leave a healthy process behind even when the
            // UI missed its readiness callback. Adopt it instead of launching
            // a duplicate on the same controller and proxy ports.
            isStarting = true
            adoptedPID = pid
            adoptedProcessIsRoot = uid == 0
            privilegedPID = uid == 0 ? pid : nil
            waitForControllerReady(attemptsRemaining: 10) { [weak self] ready in
                guard let self else { return }
                guard ready else {
                    self.adoptedPID = nil
                    self.adoptedProcessIsRoot = false
                    self.privilegedPID = nil
                    self.finishStartFailure(ClashStrings.text("existingCoreControllerUnavailable", L10n.shared.language), completion: completion)
                    return
                }
                self.isRunning = true
                self.isStarting = false
                self.lastErrorMessage = nil
                self.finishSuccessfulStart(completion: completion)
            }
            return
        }
        isStarting = true
        startCancelled = false
        lastErrorMessage = nil
        let language = L10n.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let configManager = ClashConfigManager.shared
            configManager.createDirectoriesIfNeeded()
            let mihomoPath = configManager.mihomoExecutableURL.path

            guard FileManager.default.isExecutableFile(atPath: mihomoPath) else {
                self.finishStartFailure("\(ClashStrings.text("missingCore", language)) (\(mihomoPath))", completion: completion)
                return
            }
            guard FileManager.default.fileExists(atPath: configManager.configFileURL.path) else {
                self.finishStartFailure(ClashStrings.text("missingConfig", language), completion: completion)
                return
            }
            guard configManager.normalizeExistingConfig() else {
                self.finishStartFailure(ClashStrings.text("repairConfig", language), completion: completion)
                return
            }

            let validation = Process()
            // Validate as the ordinary bundled core even when the user asked
            // to start the separate setuid TUN copy.
            validation.executableURL = configManager.regularMihomoExecutableURL
            validation.arguments = ["-t", "-d", configManager.configDirectory.path,
                                    "-f", configManager.configFileURL.path]
            let validationPipe = Pipe()
            validation.standardOutput = validationPipe
            validation.standardError = validationPipe
            do {
                try validation.run()
                let output = validationPipe.fileHandleForReading.readDataToEndOfFile()
                validation.waitUntilExit()
                guard validation.terminationStatus == 0 else {
                    let details = String(data: output, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let error = details.flatMap { $0.isEmpty ? nil : $0 }
                        .map { "\(ClashStrings.text("configError", language)): \($0)" }
                        ?? ClashStrings.text("repairConfig", language)
                    self.finishStartFailure(error, completion: completion)
                    return
                }
            } catch {
                self.finishStartFailure("\(ClashStrings.text("validateConfig", language)): \(error.localizedDescription)", completion: completion)
                return
            }

            DispatchQueue.main.async {
                guard !self.startCancelled, AppFeature.proxy.isAvailable else {
                    self.isStarting = false
                    completion?(false)
                    return
                }
                self.launchCore(using: configManager, completion: completion)
            }
        }
    }

    private func finishStartFailure(_ message: String, completion: ((Bool) -> Void)?) {
        DispatchQueue.main.async {
            self.isStarting = false
            self.lastErrorMessage = message
            completion?(false)
        }
    }

    private func launchCore(using configManager: ClashConfigManager,
                            completion: ((Bool) -> Void)?) {
        if ClashPreferences.shared.tunEnabled {
            launchPrivilegedCore(using: configManager, completion: completion)
            return
        }
        launchCoreProcess(executableURL: configManager.regularMihomoExecutableURL,
                          configManager: configManager,
                          completion: completion)
    }

    private func launchCoreProcess(executableURL: URL,
                                   configManager: ClashConfigManager,
                                   completion: ((Bool) -> Void)?) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-d", configManager.configDirectory.path]

        let logURL = configManager.baseDirectory.appendingPathComponent("mihomo-runtime.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            _ = FileManager.default.createFile(atPath: logURL.path, contents: Data())
        }
        let logHandle: FileHandle
        do {
            logHandle = try FileHandle(forWritingTo: logURL)
            try logHandle.seekToEnd()
        } catch {
            self.finishStartFailure("\(ClashStrings.text("startFailed", L10n.shared.language)): \(error.localizedDescription)", completion: completion)
            return
        }
        process.standardOutput = logHandle
        process.standardError = logHandle
        self.outputLogHandle = logHandle

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                let stoppingIntentionally = self.isStopping
                self.isRunning = false
                self.isStarting = false
                self.process = nil
                try? self.outputLogHandle?.close()
                self.outputLogHandle = nil
                MihomoAPIClient.shared.stopPolling()
                if !stoppingIntentionally {
                    SystemProxyManager.shared.disableSystemProxyAsync {
                        ClashPreferences.shared.systemProxyEnabled = false
                    }
                }
                self.refreshIslandActivity()
            }
        }

        do {
            try process.run()
            self.process = process
            self.waitForControllerReady(attemptsRemaining: 10) { ready in
                guard !self.startCancelled else {
                    if process.isRunning { process.terminate() }
                    self.isStarting = false
                    completion?(false)
                    return
                }
                guard ready else {
                    if process.isRunning { process.terminate() }
                    self.finishStartFailure(ClashStrings.text("controllerUnavailable", L10n.shared.language), completion: completion)
                    return
                }
                self.isRunning = true
                self.isStarting = false
                self.lastErrorMessage = nil
                self.finishSuccessfulStart(completion: completion)
            }
        } catch {
            try? logHandle.close()
            self.outputLogHandle = nil
            self.lastErrorMessage = "\(ClashStrings.text("startFailed", L10n.shared.language)): \(error.localizedDescription)"
            self.isRunning = false
            self.isStarting = false
            completion?(false)
        }
    }

    /// TUN uses a separate core copy with FlClash's one-time setuid setup.
    /// The ordinary bundled core is never elevated.
    private func launchPrivilegedCore(using configManager: ClashConfigManager,
                                      completion: ((Bool) -> Void)?) {
        let binaryURL = configManager.tunMihomoExecutableURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard Self.grantUserAccessToCoreData(configManager.baseDirectory) else {
                self.finishStartFailure(ClashStrings.text("tunStoragePermissionFailed", L10n.shared.language), completion: completion)
                return
            }
            guard Self.isSetuidAuthorized(binaryURL) || Self.authorizeSetuidCore(binaryURL) else {
                self.finishStartFailure(ClashStrings.text("tunAuthorizationFailed", L10n.shared.language), completion: completion)
                return
            }
            DispatchQueue.main.async {
                guard !self.startCancelled else {
                    self.isStarting = false
                    completion?(false)
                    return
                }
                self.launchCoreProcess(executableURL: binaryURL,
                                       configManager: configManager,
                                       completion: completion)
            }
        }
    }

    private static func isSetuidAuthorized(_ executableURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              attributes[.ownerAccountName] as? String == "root",
              attributes[.groupOwnerAccountName] as? String == "admin",
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue else { return false }
        return (permissions & 0o4000) != 0 && (permissions & 0o001) == 0
    }

    private static func authorizeSetuidCore(_ executableURL: URL) -> Bool {
        let groups = Process()
        groups.executableURL = URL(fileURLWithPath: "/usr/bin/id")
        groups.arguments = ["-Gn"]
        let output = Pipe()
        groups.standardOutput = output
        groups.standardError = Pipe()
        do {
            try groups.run()
            let groupList = output.fileHandleForReading.readDataToEndOfFile()
            groups.waitUntilExit()
            guard groups.terminationStatus == 0,
                  String(data: groupList, encoding: .utf8)?.split(whereSeparator: \.isWhitespace).contains("admin") == true else {
                return false
            }

            let binary = shellQuoted(executableURL.path)
            let shell = "chown root:admin \(binary) && chmod 4750 \(binary)"
            let script = "do shell script \(appleScriptQuoted(shell)) with administrator privileges"
            let authorization = Process()
            authorization.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            authorization.arguments = ["-e", script]
            authorization.standardOutput = Pipe()
            authorization.standardError = Pipe()
            try authorization.run()
            authorization.waitUntilExit()
            return authorization.terminationStatus == 0 && isSetuidAuthorized(executableURL)
        } catch {
            return false
        }
    }

    /// Root-effective Mihomo creates cache/provider files. An inherited ACL
    /// keeps this app's user able to update its own isolated Clash directory.
    private static func grantUserAccessToCoreData(_ directory: URL) -> Bool {
        let marker = directory.appendingPathComponent(".tun-user-acl-v1")
        if FileManager.default.fileExists(atPath: marker.path) { return true }
        let account = NSUserName()
        guard !account.isEmpty else { return false }
        let permissions = "list,search,add_file,add_subdirectory,delete_child,read,write,append,readattr,writeattr,readextattr,writeextattr,readsecurity,execute,delete,file_inherit,directory_inherit"
        let acl = "user:\(account) allow \(permissions)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", acl, directory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            return FileManager.default.createFile(atPath: marker.path, contents: Data())
        } catch { return false }
    }

    private func finishSuccessfulStart(completion: ((Bool) -> Void)?) {
        DispatchQueue.main.async {
            guard self.isRunning, !self.isStopping, AppFeature.proxy.isAvailable else {
                completion?(false)
                return
            }
            MihomoAPIClient.shared.startPolling()
            self.refreshIslandActivity()
            // Claim the macOS system-proxy slot with this core's local port.
            // SystemProxyManager snapshots the prior settings and restores
            // them on stop only while they still point at this core.
            SystemProxyManager.shared.enableSystemProxyAsync(port: ClashPreferences.shared.mixedPort) {
                ClashPreferences.shared.systemProxyEnabled = true
                completion?(true)
            }
        }
    }

    /// Do not claim the core is running or change macOS proxy settings until
    /// its own controller answers with the configured mixed port.
    private func waitForControllerReady(attemptsRemaining: Int,
                                        completion: @escaping (Bool) -> Void) {
        let url = URL(string: "http://127.0.0.1:\(ClashPreferences.shared.controllerPort)/configs")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        request.setValue("Bearer \(ClashPreferences.shared.controllerSecret)", forHTTPHeaderField: "Authorization")
        controllerSession.dataTask(with: request) { data, response, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let reportedPort = (json?["mixed-port"] as? NSNumber)?.intValue
            let ready = (response as? HTTPURLResponse)?.statusCode == 200
                && reportedPort == ClashPreferences.shared.mixedPort
            DispatchQueue.main.async {
                if ready {
                    completion(true)
                } else if attemptsRemaining > 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.waitForControllerReady(attemptsRemaining: attemptsRemaining - 1,
                                                    completion: completion)
                    }
                } else {
                    completion(false)
                }
            }
        }.resume()
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Stops Mihomo. During a TUN reconfiguration the caller can keep the
    /// system-proxy settings in place while the same local port is restarted.
    public func stopCore(preservingSystemProxy: Bool = false,
                         completion: (() -> Void)? = nil) {
        if isStopping {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { completion?(); return }
                self.stopCore(preservingSystemProxy: preservingSystemProxy, completion: completion)
            }
            return
        }
        if isStarting {
            startCancelled = true
            isStarting = false
            let startingProcess = process
            let startingPID = privilegedPID
            process = nil
            privilegedPID = nil
            DispatchQueue.global(qos: .userInitiated).async {
                if let startingProcess, startingProcess.isRunning {
                    startingProcess.terminate()
                    startingProcess.waitUntilExit()
                }
                if let startingPID { Self.terminateUserCoreAndWait(pid: startingPID) }
                DispatchQueue.main.async { completion?() }
            }
            return
        }
        guard isRunning || process != nil || privilegedPID != nil else {
            let configManager = ClashConfigManager.shared
            guard let (pid, _) = Self.findRunningCore(binary: configManager.mihomoExecutableURL.path,
                                                      configDirectory: configManager.configDirectory.path) else {
                completion?()
                return
            }
            isStopping = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                // The setuid core retains the launching user's real UID, so
                // the owning app can send SIGTERM without an administrator
                // prompt even when `ps` reports its effective UID as root.
                let stopped = Self.terminateUserCoreAndWait(pid: pid)
                DispatchQueue.main.async {
                    guard let self else { completion?(); return }
                    self.isRunning = !stopped
                    self.isStarting = false
                    self.isStopping = false
                    if !stopped {
                        self.lastErrorMessage = ClashStrings.text("coreStopFailed", L10n.shared.language)
                    }
                    if preservingSystemProxy {
                        completion?()
                    } else {
                        SystemProxyManager.shared.disableSystemProxyAsync {
                            ClashPreferences.shared.systemProxyEnabled = false
                            completion?()
                        }
                    }
                }
            }
            return
        }
        isStopping = true
        MihomoAPIClient.shared.stopPolling()
        let localProcess = process
        let rootPID = privilegedPID
        let adoptedPID = adoptedPID
        let adoptedIsRoot = adoptedProcessIsRoot
        process = nil
        privilegedPID = nil
        self.adoptedPID = nil
        adoptedProcessIsRoot = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let localProcess, localProcess.isRunning {
                localProcess.terminate()
                localProcess.waitUntilExit()
            }
            let rootStopped = rootPID.map { Self.terminateUserCoreAndWait(pid: $0) } ?? true
            if let adoptedPID, !adoptedIsRoot {
                Self.terminateUserCoreAndWait(pid: adoptedPID)
            }
            let completeStop = {
                guard let self else { return }
                self.isRunning = !rootStopped
                self.isStarting = false
                self.isStopping = false
                if !rootStopped {
                    self.lastErrorMessage = ClashStrings.text("coreStopFailed", L10n.shared.language)
                }
                if !preservingSystemProxy {
                    ClashPreferences.shared.systemProxyEnabled = false
                }
                self.refreshIslandActivity()
                completion?()
            }
            if preservingSystemProxy {
                DispatchQueue.main.async(execute: completeStop)
            } else {
                SystemProxyManager.shared.disableSystemProxyAsync {
                    ClashPreferences.shared.systemProxyEnabled = false
                    completeStop()
                }
            }
        }
    }

    @discardableResult
    private static func terminateUserCoreAndWait(pid: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-TERM", String(pid)]
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return !isProcessAlive(pid: pid) }
            for _ in 0..<25 {
                if !isProcessAlive(pid: pid) { return true }
                Thread.sleep(forTimeInterval: 0.2)
            }
            return !isProcessAlive(pid: pid)
        } catch { return false }
    }

    private static func isProcessAlive(pid: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-0", String(pid)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch { return false }
    }

    private func refreshIslandActivity() {
        guard AppFeature.proxy.isAvailable, AppFeature.notch.isAvailable else { return }
        NotchService.shared.syncWithPreferences()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine

public final class MihomoAPIClient: ObservableObject {
    public static let shared = MihomoAPIClient()

    @Published public var currentTraffic = TrafficRate()
    @Published public private(set) var totalUploaded: Int64 = 0
    @Published public private(set) var totalDownloaded: Int64 = 0
    @Published public var proxyGroups: [ProxyGroup] = []
    @Published public var allNodes: [ProxyNode] = []
    @Published public var isTestingDelays = false
    @Published public private(set) var testedDelayNodes: Set<String> = []
    @Published public private(set) var unreachableNodes: Set<String> = []

    public var currentRouteName: String {
        let byName = Dictionary(uniqueKeysWithValues: proxyGroups.map { ($0.name, $0) })
        let root = proxyGroups.first(where: {
            ["proxies", "global"].contains($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }) ?? (proxyGroups.count == 1 ? proxyGroups.first : nil)
        guard let group = root else { return proxyGroups.isEmpty ? "Disconnected" : "—" }
        var route = group.now
        var visited = Set<String>()
        while let nested = byName[route], visited.insert(route).inserted {
            route = nested.now
        }
        return route
    }

    private var trafficSocket: URLSessionWebSocketTask?
    private var trafficReconnectWorkItem: DispatchWorkItem?
    private var trafficGeneration = 0
    private var cancellables = Set<AnyCancellable>()
    private let apiSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    private var baseURL: URL {
        let port = ClashPreferences.shared.controllerPort
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    private func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(ClashPreferences.shared.controllerSecret)",
                         forHTTPHeaderField: "Authorization")
        return request
    }

    private init() {}

    public func startPolling() {
        DispatchQueue.main.async {
            self.stopPollingOnMain()
            self.totalUploaded = 0
            self.totalDownloaded = 0
            let generation = self.trafficGeneration
            self.openTrafficSocket(generation: generation)
            self.fetchProxies()
        }
    }

    public func stopPolling() {
        DispatchQueue.main.async {
            self.stopPollingOnMain()
        }
    }

    private func stopPollingOnMain() {
        trafficGeneration &+= 1
        trafficReconnectWorkItem?.cancel()
        trafficReconnectWorkItem = nil
        trafficSocket?.cancel(with: .goingAway, reason: nil)
        trafficSocket = nil
        currentTraffic = TrafficRate()
    }

    private func openTrafficSocket(generation: Int) {
        guard generation == trafficGeneration else { return }
        var components = URLComponents()
        components.scheme = "ws"
        components.host = "127.0.0.1"
        components.port = ClashPreferences.shared.controllerPort
        components.path = "/traffic"
        guard let url = components.url else {
            scheduleTrafficReconnect(generation: generation)
            return
        }
        let socket = apiSession.webSocketTask(with: authorizedRequest(url: url))
        trafficSocket = socket
        socket.resume()
        receiveTraffic(from: socket, generation: generation)
    }

    private func receiveTraffic(from socket: URLSessionWebSocketTask, generation: Int) {
        socket.receive { [weak self, weak socket] result in
            DispatchQueue.main.async {
                guard let self, let socket, generation == self.trafficGeneration,
                      self.trafficSocket === socket else { return }
                switch result {
                case .failure:
                    self.trafficSocket = nil
                    self.scheduleTrafficReconnect(generation: generation)
                case .success(let message):
                    let data: Data?
                    switch message {
                    case .string(let value): data = value.data(using: .utf8)
                    case .data(let value): data = value
                    @unknown default: data = nil
                    }
                    if let data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let up = (json["up"] as? NSNumber)?.int64Value,
                       let down = (json["down"] as? NSNumber)?.int64Value {
                        self.currentTraffic = TrafficRate(up: up, down: down)
                        if let total = (json["upTotal"] as? NSNumber)?.int64Value {
                            self.totalUploaded = total
                        } else {
                            self.totalUploaded += max(0, up)
                        }
                        if let total = (json["downTotal"] as? NSNumber)?.int64Value {
                            self.totalDownloaded = total
                        } else {
                            self.totalDownloaded += max(0, down)
                        }
                    }
                    self.receiveTraffic(from: socket, generation: generation)
                }
            }
        }
    }

    private func scheduleTrafficReconnect(generation: Int) {
        guard generation == trafficGeneration else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.openTrafficSocket(generation: generation)
        }
        trafficReconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    public func fetchProxies(completion: (() -> Void)? = nil) {
        let url = baseURL.appendingPathComponent("proxies")
        var request = authorizedRequest(url: url)
        request.timeoutInterval = 3.0

        apiSession.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let proxiesDict = json["proxies"] as? [String: [String: Any]] else {
                completion?()
                return
            }

            var groups: [ProxyGroup] = []
            var nodes: [ProxyNode] = []

            for (name, item) in proxiesDict {
                let type = (item["type"] as? String) ?? "Unknown"
                if let all = item["all"] as? [String], let now = item["now"] as? String {
                    groups.append(ProxyGroup(name: name, type: type, now: now, all: all))
                } else if type != "Direct" && type != "Reject" && type != "Pass" {
                    var delay: Int? = nil
                    if let history = item["history"] as? [[String: Any]], let last = history.last {
                        delay = last["delay"] as? Int
                    }
                    nodes.append(ProxyNode(name: name, type: type, delay: delay))
                }
            }

            DispatchQueue.main.async {
                self.proxyGroups = groups
                self.allNodes = nodes
                completion?()
            }
        }.resume()
    }

    public func switchNode(in groupName: String, to nodeName: String, completion: ((Bool) -> Void)? = nil) {
        guard let encodedGroup = groupName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            completion?(false)
            return
        }
        let url = baseURL.appendingPathComponent("proxies/\(encodedGroup)")
        var request = authorizedRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": nodeName])

        apiSession.dataTask(with: request) { [weak self] _, response, _ in
            let success = (response as? HTTPURLResponse)?.statusCode == 204
            if success {
                self?.fetchProxies()
            }
            DispatchQueue.main.async {
                completion?(success)
            }
        }.resume()
    }

    public func setMode(_ mode: ClashMode, completion: ((Bool) -> Void)? = nil) {
        let url = baseURL.appendingPathComponent("configs")
        var request = authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["mode": mode.rawValue])

        apiSession.dataTask(with: request) { _, response, _ in
            let success = (response as? HTTPURLResponse)?.statusCode == 204
            DispatchQueue.main.async {
                if success {
                    ClashPreferences.shared.selectedMode = mode
                }
                completion?(success)
            }
        }.resume()
    }

    public func testDelay(for nodeName: String, completion: ((Int?) -> Void)? = nil) {
        guard let encodedNode = nodeName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            completion?(nil)
            return
        }
        let testURL = "http://www.gstatic.com/generate_204"
        guard let url = URL(string: "\(baseURL.absoluteString)/proxies/\(encodedNode)/delay?timeout=5000&url=\(testURL)") else {
            completion?(nil)
            return
        }

        var request = authorizedRequest(url: url)
        request.timeoutInterval = 6.0

        apiSession.dataTask(with: request) { data, _, _ in
            var resultDelay: Int? = nil
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let delay = json["delay"] as? Int {
                resultDelay = delay
            }
            DispatchQueue.main.async {
                completion?(resultDelay)
            }
        }.resume()
    }

    public func testAllDelays() {
        let names = Array(Set(proxyGroups.flatMap(\.all))).filter { $0 != "DIRECT" && $0 != "REJECT" }
        guard !names.isEmpty else { return }
        DispatchQueue.main.async { self.isTestingDelays = true }
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [String: Int?] = [:]
        for name in names {
            group.enter()
            testDelay(for: name) { delay in
                lock.lock(); results[name] = .some(delay); lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.allNodes = self.allNodes.map { node in
                var updated = node
                if let value = results[node.name] {
                    updated.delay = value
                    self.testedDelayNodes.insert(node.name)
                    if value == nil { self.unreachableNodes.insert(node.name) }
                    else { self.unreachableNodes.remove(node.name) }
                }
                return updated
            }
            self.isTestingDelays = false
        }
    }

    public func nodeDelay(_ name: String) -> Int? {
        allNodes.first(where: { $0.name == name })?.delay
    }
}

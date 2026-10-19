import Foundation
import Network
import VacuulaCore

/// Browse first, then resolve the full set before deciding whether to auto-connect.
@MainActor
final class ServerDiscovery: NSObject, @preconcurrency NetServiceDelegate {
    private var browser: NWBrowser?
    private var services = [String: NetService]()
    private var resolved = [String: ServerIdentity]()
    private var failure: String?
    private var ready = false

    func scan() async throws -> [ServerIdentity] {
        stop(); services.removeAll(); resolved.removeAll(); failure = nil; ready = false
        let browser = NWBrowser(for: .bonjour(type: "_vacuula._tcp", domain: "local."), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self, self.browser === browser else { return }
                for result in results {
                    if case let .service(name, type, domain, _) = result.endpoint {
                        self.resolve(name: name, type: type, domain: domain)
                    }
                }
                let names = Set(results.compactMap { result -> String? in
                    if case let .service(name, type, domain, _) = result.endpoint { return name + type + domain }
                    return nil
                })
                for key in Array(self.services.keys) where !names.contains(key) {
                    self.services[key]?.stop(); self.services.removeValue(forKey: key); self.resolved.removeValue(forKey: key)
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.browser === browser else { return }
                switch state {
                case .ready: self.ready = true; self.failure = nil
                case .failed(let error), .waiting(let error):
                    self.failure = "Server discovery couldn’t start. Allow local network access in Settings, check Wi-Fi, then try again. (\(error.localizedDescription))"
                default: break
                }
            }
        }
        browser.start(queue: .main)
        defer { stop() }
        // Permission or browser startup delays must not be mistaken for an empty network.
        for _ in 0..<100 {
            if ready || failure != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        if let failure { throw ClientError.message(failure) }
        guard ready else { throw ClientError.message("Discovery hasn’t started. Check local network access in Settings, then try again.") }
        try await Task.sleep(for: .seconds(5))
        if let failure { throw ClientError.message(failure) }
        // Give already discovered services a bounded chance to finish resolution.
        for _ in 0..<15 where resolved.count < services.count {
            try await Task.sleep(for: .milliseconds(200))
        }
        if !services.isEmpty && resolved.isEmpty { throw ClientError.message("A Vacuula server was found, but its address couldn’t be resolved. Check the server and try again.") }
        return resolved.values.sorted { $0.name < $1.name }
    }

    func remembered(_ identity: ServerIdentity) async throws -> ServerIdentity {
        guard let name = identity.serviceName, let type = identity.serviceType, let domain = identity.serviceDomain else { return identity }
        stop(); services.removeAll(); resolved.removeAll()
        resolve(name: name, type: type, domain: domain)
        defer { stop() }
        for _ in 0..<15 {
            if let result = resolved.values.first { return result }
            try await Task.sleep(for: .milliseconds(200))
        }
        return identity
    }
    private func resolve(name: String, type: String, domain: String) {
        let key = name + type + domain
        guard services[key] == nil else { return }
        let service = NetService(domain: domain, type: type, name: name)
        services[key] = service; service.delegate = self; service.resolve(withTimeout: 3)
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard services[sender.name + sender.type + sender.domain] === sender else { return }
        guard let host = sender.hostName, sender.port > 0 else { return }
        var parts = URLComponents(); parts.scheme = "http"
        parts.host = host.hasSuffix(".") ? String(host.dropLast()) : host
        parts.port = sender.port
        guard let url = parts.url else { return }
        resolved[sender.name + sender.type + sender.domain] = ServerIdentity(origin: url, name: sender.name,
            serviceName: sender.name, serviceType: sender.type, serviceDomain: sender.domain)
    }
    func stop() {
        browser?.browseResultsChangedHandler = nil; browser?.stateUpdateHandler = nil
        browser?.cancel(); browser = nil
        for service in services.values { service.stop() }
    }
}

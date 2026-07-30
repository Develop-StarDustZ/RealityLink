import Foundation
import Network

enum LatencyTester {
    static func measure(host: String, port: Int, timeout: TimeInterval = 5) async -> Int? {
        guard let networkPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        if PhysicalInterfaceProvider.shared.current == nil {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return await withCheckedContinuation { continuation in
            let probe = Probe(continuation: continuation)
            let parameters = NWParameters.tcp
            parameters.requiredInterface = PhysicalInterfaceProvider.shared.current
            let connection = NWConnection(host: NWEndpoint.Host(host), port: networkPort, using: parameters)
            let started = DispatchTime.now()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                    probe.finish(milliseconds: max(1, Int(elapsed / 1_000_000)), connection: connection)
                case .failed, .cancelled:
                    probe.finish(milliseconds: nil, connection: connection)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                probe.finish(milliseconds: nil, connection: connection)
            }
        }
    }

    private final class PhysicalInterfaceProvider: @unchecked Sendable {
        static let shared = PhysicalInterfaceProvider()

        private let lock = NSLock()
        private let monitor = NWPathMonitor()
        private var availableInterface: NWInterface?

        private init() {
            monitor.pathUpdateHandler = { [weak self] path in
                let interface = path.availableInterfaces.first(where: { interface in
                    interface.type == .wiredEthernet || interface.type == .wifi
                })
                self?.lock.lock()
                self?.availableInterface = interface
                self?.lock.unlock()
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }

        var current: NWInterface? {
            lock.lock()
            defer { lock.unlock() }
            return availableInterface
        }
    }

    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int?, Never>?

        init(continuation: CheckedContinuation<Int?, Never>) {
            self.continuation = continuation
        }

        func finish(milliseconds: Int?, connection: NWConnection) {
            lock.lock()
            guard let continuation else {
                lock.unlock()
                return
            }
            self.continuation = nil
            lock.unlock()
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(returning: milliseconds)
        }
    }
}

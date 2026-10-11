import Foundation
import Darwin

enum LocalTextRuntimeError: LocalizedError {
    case runtimeMissing, modelMissing, startupFailed, timedOut, invalidResponse, outputLimit
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing: "The writing engine is missing from this copy of Murmur. Install a complete Murmur release."
        case .modelMissing: "Download and select a writing model in Models before using local writing."
        case .startupFailed: "The local writing engine could not start. Try a smaller model or restart Murmur."
        case .timedOut: "The local writing engine took too long. Your transcript is safe; try again with a shorter passage."
        case .invalidResponse: "The local writing engine returned an unreadable response. Try again."
        case .outputLimit: "The response exceeded the writing limit. Try a shorter passage."
        case .requestFailed(let status): "The local writing engine could not process this passage (\(status)). Try a shorter passage."
        }
    }
}

/// A single monotonic budget shared by queueing, startup, and HTTP work; never reset between stages.
struct LocalTextDeadline: Sendable {
    let instant: ContinuousClock.Instant
    init(seconds: TimeInterval) {
        instant = ContinuousClock.now.advanced(by: .seconds(max(0, seconds)))
    }
    func remainingSeconds() throws -> TimeInterval {
        let remaining = ContinuousClock.now.duration(to: instant).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { throw LocalTextRuntimeError.timedOut }
        return seconds
    }
}

/// One owned, authenticated loopback service. End users never need a system-installed runtime.
/// Requests are serialized across actor suspension points, including model changes.
actor LocalTextRuntime {
    static let shared = LocalTextRuntime()

    nonisolated static var executableURL: URL? {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "murmur-text-server"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    nonisolated static var runtimeAvailable: Bool { executableURL != nil }

    private var process: Process?
    private var loadedModel: URL?
    private var endpoint: URL?
    private var accessToken = ""
    private var requestID: UUID?
    private var busy = false
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
    }

    func complete(modelURL: URL, system: String, user: String, maxTokens: Int,
                  timeoutSeconds: TimeInterval? = nil) async throws -> String {
        let deadline = LocalTextDeadline(seconds: timeoutSeconds ?? (maxTokens <= 1200 ? 8 : 180))
        // Actor isolation alone does not serialize asynchronous HTTP requests.
        while busy {
            try Task.checkCancellation()
            _ = try deadline.remainingSeconds()
            try await Task.sleep(for: .milliseconds(40))
        }
        try Task.checkCancellation()
        _ = try deadline.remainingSeconds()
        busy = true
        let id = UUID()
        requestID = id
        defer { busy = false; requestID = nil }

        return try await withTaskCancellationHandler {
            do {
                try await prepare(modelURL: modelURL, deadline: deadline)
                try Task.checkCancellation()
                guard let endpoint else { throw LocalTextRuntimeError.startupFailed }
                var request = URLRequest(url: endpoint.appendingPathComponent("v1/chat/completions"))
                request.timeoutInterval = try deadline.remainingSeconds()
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = try Self.requestBody(system: system, user: user, maxTokens: maxTokens)
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                _ = try deadline.remainingSeconds() // Never publish a result that arrived after its budget.
                guard let response = response as? HTTPURLResponse else { throw LocalTextRuntimeError.invalidResponse }
                guard response.statusCode == 200 else { throw LocalTextRuntimeError.requestFailed(response.statusCode) }
                return try Self.parseCompletion(data)
            } catch {
                // Abandon timed-out/cancelled work on the server as well as on the client.
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    await stopProcess()
                    throw CancellationError()
                }
                if (error as? URLError)?.code == .timedOut {
                    await stopProcess()
                    throw LocalTextRuntimeError.timedOut
                }
                if case LocalTextRuntimeError.timedOut = error {
                    await stopProcess()
                }
                throw error
            }
        } onCancel: {
            Task { await self.cancelRequest(id) }
        }
    }

    func shutdown() async { await stopProcess() }

    /// Prepares an already-downloaded model. This never starts a download or produces text.
    func warmup(modelURL: URL) async throws {
        while busy {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(40))
        }
        try Task.checkCancellation()
        busy = true
        let id = UUID()
        requestID = id
        defer { busy = false; requestID = nil }
        try await withTaskCancellationHandler {
            do { try await prepare(modelURL: modelURL, deadline: LocalTextDeadline(seconds: 120)) }
            catch {
                await stopProcess()
                throw error
            }
        } onCancel: {
            Task { await self.cancelRequest(id) }
        }
    }

    private func cancelRequest(_ id: UUID) async {
        guard requestID == id else { return }
        await stopProcess()
    }

    private func prepare(modelURL: URL, deadline: LocalTextDeadline) async throws {
        if process?.isRunning == true, loadedModel == modelURL, endpoint != nil { return }
        await stopProcess()
        _ = try deadline.remainingSeconds()
        guard let executable = Self.executableURL else { throw LocalTextRuntimeError.runtimeMissing }
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw LocalTextRuntimeError.modelMissing }
        let port = try Self.availablePort()
        let token = UUID().uuidString + UUID().uuidString
        let alias = "murmur-" + UUID().uuidString
        let child = Process()
        child.executableURL = executable
        child.arguments = [
            "--model", modelURL.path, "--alias", alias, "--host", "127.0.0.1", "--port", String(port),
            "--ctx-size", "8192", "--parallel", "1", "--n-gpu-layers", "99", "--no-context-shift",
            "--no-webui", "--chat-template-kwargs", "{\"enable_thinking\":false}",
            "--reasoning-budget", "0", "--log-disable"
        ]
        var environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        environment["LLAMA_API_KEY"] = token
        // Homebrew's developer build loads backends dynamically. All are relocated in our bundle.
        environment["GGML_BACKEND_PATH"] = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/TextRuntime").path
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        process = child
        accessToken = token
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        endpoint = baseURL
        while ContinuousClock.now < deadline.instant {
            try Task.checkCancellation()
            guard child.isRunning, process === child else { throw LocalTextRuntimeError.startupFailed }
            var health = URLRequest(url: baseURL.appendingPathComponent("health"))
            health.timeoutInterval = min(1, try deadline.remainingSeconds())
            health.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let (_, response) = try? await session.data(for: health),
               (response as? HTTPURLResponse)?.statusCode == 200, child.isRunning {
                // A random alias plus authentication identifies our child after the bind/launch gap.
                var identity = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
                identity.timeoutInterval = min(2, try deadline.remainingSeconds())
                identity.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let (data, response) = try? await session.data(for: identity),
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]],
                   models.contains(where: { $0["id"] as? String == alias }), child.isRunning, process === child {
                    loadedModel = modelURL
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        await stopProcess()
        throw LocalTextRuntimeError.timedOut
    }

    private func stopProcess() async {
        let child = process
        process = nil
        loadedModel = nil
        endpoint = nil
        accessToken = ""
        guard let child, child.isRunning else { return }
        child.terminate()
        for _ in 0..<20 {
            if !child.isRunning { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        // Only this Process's still-running PID, never a name/port-wide pkill.
        if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
    }

    nonisolated static func requestBody(system: String, user: String, maxTokens: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "max_tokens": min(max(maxTokens, 1), 4096), "temperature": 0.1, "stream": false,
            "chat_template_kwargs": ["enable_thinking": false]
        ])
    }

    nonisolated static func parseCompletion(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let choice = response.choices.first, let content = choice.message.content else {
            throw LocalTextRuntimeError.invalidResponse
        }
        if choice.finish_reason == "length" { throw LocalTextRuntimeError.outputLimit }
        let text = content.replacingOccurrences(of: #"^\s*<think>[\s\S]*?</think>\s*"#,
                                               with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalTextRuntimeError.invalidResponse }
        return text
    }

    private nonisolated static func availablePort() throws -> UInt16 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalTextRuntimeError.startupFailed }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw LocalTextRuntimeError.startupFailed }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let fetched = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard fetched == 0 else { throw LocalTextRuntimeError.startupFailed }
        return UInt16(bigEndian: address.sin_port)
    }
}

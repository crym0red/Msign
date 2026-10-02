//
//  LocalZSignAPI.swift
//  Loopback-only Vapor API for the local ZSign engine.
//
//  This is deliberately separate from LocalOTAServer. OTA serves finished
//  packages; this service controls local signing jobs.
//

import Foundation
import SwiftUI
import Vapor
import NIOSSL

nonisolated enum MSignVaporRuntime {
    static let logging: Void = {
        var env = Environment(name: "msign-vapor", arguments: ["mSign"])
        try? LoggingSystem.bootstrap(from: &env)
    }()
}

nonisolated struct LocalZSignSignRequest: Content, Sendable {
    var path: String
    var name: String?
    var bundleID: String?
    var version: String?
    var parallelSigning: Bool?
}

nonisolated struct LocalZSignJobResponse: Content, Sendable {
    var id: String
    var status: String
    var input: String
    var output: String?
    var name: String?
    var bundleID: String?
    var version: String?
    var elapsedSeconds: Double?
    var extractionSeconds: Double?
    var signingSeconds: Double?
    var packagingSeconds: Double?
    var error: String?
    var otaManifest: String?
    var otaDownload: String?
    var installURL: String?
    var otaPublished: Bool
}

nonisolated struct LocalZSignStatusResponse: Content, Sendable {
    var running: Bool
    var https: Bool
    var host: String
    var port: Int
    var engine: String
    var ota: Bool
}

private struct LocalZSignJob: Sendable {
    let id: UUID
    let input: URL
    var status: String
    var output: URL?
    var name: String?
    var bundleID: String?
    var version: String?
    var elapsedSeconds: Double?
    var extractionSeconds: Double?
    var signingSeconds: Double?
    var packagingSeconds: Double?
    var error: String?
    var otaPublished: Bool
}

private actor LocalZSignJobStore {
    private var jobs: [UUID: LocalZSignJob] = [:]

    func insert(_ job: LocalZSignJob) { jobs[job.id] = job }

    func update(_ id: UUID, status: String, output: URL? = nil, name: String? = nil, bundleID: String? = nil, version: String? = nil, elapsedSeconds: Double? = nil, extractionSeconds: Double? = nil, signingSeconds: Double? = nil, packagingSeconds: Double? = nil, error: String? = nil) {
        guard var job = jobs[id] else { return }
        job.status = status
        if let output { job.output = output }
        if let name { job.name = name }
        if let bundleID { job.bundleID = bundleID }
        if let version { job.version = version }
        if let elapsedSeconds { job.elapsedSeconds = elapsedSeconds }
        if let extractionSeconds { job.extractionSeconds = extractionSeconds }
        if let signingSeconds { job.signingSeconds = signingSeconds }
        if let packagingSeconds { job.packagingSeconds = packagingSeconds }
        if let error { job.error = error }
        jobs[id] = job
    }

    func get(_ id: UUID) -> LocalZSignJob? { jobs[id] }
    func all() -> [LocalZSignJob] { Array(jobs.values) }
    func update(_ id: UUID, mutate: (inout LocalZSignJob) -> Void) {
        guard var job = jobs[id] else { return }
        mutate(&job)
        jobs[id] = job
    }
}

nonisolated final class LocalZSignAPI: @unchecked Sendable {
    static let shared = LocalZSignAPI()

    static func host() -> String { ServerConfig.installHost }

    let host: String
    let port = 8799
    private let tokenKey = "local-zsign-api-token"
    private let jobs = LocalZSignJobStore()
    private let lock = NSLock()
    private var application: Application?
    private var otaServers: [UUID: LocalOTAServer] = [:]
    private var started = false

    private init() {
        host = Self.host()
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return started
    }

    var token: String {
        if let existing = Keychain.get(tokenKey), !existing.isEmpty { return existing }
        let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        _ = Keychain.set(tokenKey, generated)
        return generated
    }

    func startIfNeeded() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        do {
            _ = MSignVaporRuntime.logging
            let app = Application(.production)
            app.http.server.configuration.tlsConfiguration = try Self.tlsConfiguration()
            app.http.server.configuration.hostname = Self.host()
            app.http.server.configuration.address = .hostname("127.0.0.1", port: port)
            app.http.server.configuration.port = port
            app.http.server.configuration.tcpNoDelay = true
            app.routes.defaultMaxBodySize = "512mb"

            app.get("ota", ":id", ":resource") { [weak self] req async throws -> Response in
                guard let self else { throw Abort(.serviceUnavailable) }
                guard let rawID = req.parameters.get("id"), let id = UUID(uuidString: rawID),
                      let resource = req.parameters.get("resource") else {
                    throw Abort(.notFound)
                }
                guard let ota = self.otaServer(id: id) else { throw Abort(.notFound) }
                return try ota.response(for: resource, request: req)
            }

            app.get("v1", "status") { [weak self] req async -> LocalZSignStatusResponse in
                guard let self else { return .init(running: false, https: true, host: ServerConfig.installHost, port: 8799, engine: "unavailable", ota: false) }
                guard self.authorized(req) else { return .init(running: false, https: true, host: self.host, port: self.port, engine: "unauthorized", ota: true) }
                return .init(running: self.isRunning, https: true, host: self.host, port: self.port, engine: "ZSign", ota: true)
            }

            app.post("v1", "sign") { [weak self] req async throws -> LocalZSignJobResponse in
                guard let self else { throw Abort(.serviceUnavailable) }
                try self.requireAuthorization(req)
                let body = try req.content.decode(LocalZSignSignRequest.self)
                return try await self.submit(body)
            }

            app.get("v1", "jobs") { [weak self] req async throws -> [LocalZSignJobResponse] in
                guard let self else { throw Abort(.serviceUnavailable) }
                try self.requireAuthorization(req)
                return await self.jobs.all().map(self.response)
            }

            app.get("v1", "jobs", ":id") { [weak self] req async throws -> LocalZSignJobResponse in
                guard let self else { throw Abort(.serviceUnavailable) }
                try self.requireAuthorization(req)
                guard let raw = req.parameters.get("id"), let id = UUID(uuidString: raw), let job = await self.jobs.get(id) else {
                    throw Abort(.notFound)
                }
                return self.response(job)
            }

            app.post("v1", "sign-and-install") { [weak self] req async throws -> LocalZSignJobResponse in
                guard let self else { throw Abort(.serviceUnavailable) }
                try self.requireAuthorization(req)
                return try await self.submit(try req.content.decode(LocalZSignSignRequest.self), publishOTA: true)
            }

            app.get("v1", "jobs", ":id", "download") { [weak self] req async throws -> Response in
                guard let self else { throw Abort(.serviceUnavailable) }
                try self.requireAuthorization(req)
                guard let raw = req.parameters.get("id"), let id = UUID(uuidString: raw), let job = await self.jobs.get(id), let output = job.output else {
                    throw Abort(.notFound)
                }
                guard FileManager.default.fileExists(atPath: output.path) else { throw Abort(.notFound) }
                return req.fileio.streamFile(at: output.path)
            }

            try app.server.start()
            lock.lock()
            application = app
            lock.unlock()
        } catch {
            lock.lock()
            started = false
            lock.unlock()
        }
    }

    func registerOTAServer(_ server: LocalOTAServer) throws {
        lock.lock()
        guard application != nil, started else {
            lock.unlock()
            throw Abort(.serviceUnavailable, reason: "Local mSign HTTPS service is not running.")
        }
        otaServers[server.id] = server
        lock.unlock()
    }

    func removeOTAServer(_ id: UUID) {
        lock.lock()
        otaServers.removeValue(forKey: id)
        lock.unlock()
    }

    private func otaServer(id: UUID) -> LocalOTAServer? {
        lock.lock(); defer { lock.unlock() }
        return otaServers[id]
    }

    private static func tlsConfiguration() throws -> TLSConfiguration {
        if ServerConfig.certMode == "local" {
            guard LocalCAManager.hasLeaf else { throw ZefvCert.CertError.unavailable }
            return try LocalCAManager.withLeafKeyFile { keyFile in
                try .makeServerConfiguration(
                    certificateChain: NIOSSLCertificate.fromPEMFile(LocalCAManager.leafCertURL.path).map { NIOSSLCertificateSource.certificate($0) },
                    privateKey: .privateKey(try NIOSSLPrivateKey(file: keyFile.path, format: .pem))
                )
            }
        }
        guard let crt = ZefvCert.crtURL, let key = ZefvCert.keyURL else { throw ZefvCert.CertError.unavailable }
        return try .makeServerConfiguration(
            certificateChain: NIOSSLCertificate.fromPEMFile(crt.path).map { NIOSSLCertificateSource.certificate($0) },
            privateKey: .privateKey(try NIOSSLPrivateKey(file: key.path, format: .pem))
        )
    }

    func shutdown() {
        lock.lock()
        let app = application
        application = nil
        otaServers.removeAll()
        started = false
        lock.unlock()
        app?.server.shutdown()
        app?.shutdown()
    }

    private func authorized(_ req: Request) -> Bool {
        req.headers.first(name: "X-mSign-Local-Token") == token
    }

    private func requireAuthorization(_ req: Request) throws {
        guard authorized(req) else { throw Abort(.unauthorized) }
    }

    private func submit(_ request: LocalZSignSignRequest, publishOTA: Bool = false) async throws -> LocalZSignJobResponse {
        let input = try resolveInput(request.path)
        guard input.pathExtension.lowercased() == "ipa" else { throw Abort(.badRequest, reason: "Only .ipa inputs are accepted.") }
        guard FileManager.default.fileExists(atPath: input.path) else { throw Abort(.notFound, reason: "IPA not found.") }

        let id = UUID()
        let job = LocalZSignJob(id: id, input: input, status: "queued", output: nil,
                                name: nil, bundleID: nil, version: nil, elapsedSeconds: nil,
                                extractionSeconds: nil, signingSeconds: nil, packagingSeconds: nil, error: nil, otaPublished: false)
        await jobs.insert(job)

        Task.detached(priority: .userInitiated) { [weak self, jobs] in
            guard let self else { return }
            await jobs.update(id, status: "signing")
            let started = ContinuousClock.now
            do {
                let material = try await MainActor.run { try CertificateStore.shared.activeMaterial() }
                var options = SignOptions()
                options.name = request.name
                options.bundleID = request.bundleID
                options.version = request.version
                options.parallelSigning = request.parallelSigning ?? true
                let outcome = try await Signer.signDetached(ipaURL: input, material: material, options: options, captureOutput: false)

                let outDir = AppPaths.dir("local-api-signed")
                let safeName = outcome.name.replacingOccurrences(of: "/", with: "-")
                let output = outDir.appendingPathComponent("\(safeName)-\(id.uuidString).ipa")
                try? FileManager.default.removeItem(at: output)
                try FileManager.default.copyItem(at: outcome.ipaURL, to: output)
                try? FileManager.default.removeItem(at: outcome.ipaURL)

                let elapsed = Self.elapsed(started)
                await jobs.update(
                    id,
                    status: "completed",
                    output: output,
                    name: outcome.name,
                    bundleID: outcome.bundleID,
                    version: outcome.version,
                    elapsedSeconds: elapsed,
                    error: nil
                )
                await jobs.update(id, mutate: { $0.otaPublished = false })

                if publishOTA {
                    let icon = (try? IPAMeta.read(output).iconPNG) ?? nil
                    let imageSmall = OTAInstaller.otaIconPNG(icon, side: 57)
                    let imageLarge = OTAInstaller.otaIconPNG(icon, side: 512)
                    _ = try LocalOTAServer(package: output,
                                            metadata: InstallAppData(id: outcome.bundleID, version: outcome.version, name: outcome.name),
                                            imageSmall: imageSmall,
                                            imageLarge: imageLarge)
                    await jobs.update(id, mutate: { $0.otaPublished = true })
                }
            } catch {
                await jobs.update(id, status: "failed", elapsedSeconds: Self.elapsed(started), error: error.localizedDescription)
            }
        }

        return response(await jobs.get(id)!)
    }

    private static func elapsed(_ started: ContinuousClock.Instant) -> Double {
        let d = started.duration(to: .now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private func resolveInput(_ path: String) throws -> URL {
        let raw = URL(fileURLWithPath: path).standardizedFileURL
        let allowedRoots = [
            AppPaths.documents.standardizedFileURL,
            FileManager.default.temporaryDirectory.standardizedFileURL
        ]
        guard allowedRoots.contains(where: { raw.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }) else {
            throw Abort(.forbidden, reason: "The local API can only access mSign Documents or temporary files.")
        }
        return raw
    }

    private func response(_ job: LocalZSignJob) -> LocalZSignJobResponse {
        let base = "https://\(host):\(port)"
        let otaID = job.id.uuidString
        let manifest = job.otaPublished ? "\(base)/ota/\(otaID)/manifest.plist" : nil
        let download = job.otaPublished ? "\(base)/ota/\(otaID)/app.ipa" : nil
        let install = manifest.map { "itms-services://?action=download-manifest&url=\($0)" }
        return .init(id: job.id.uuidString, status: job.status, input: job.input.lastPathComponent,
                     output: job.output?.lastPathComponent, name: job.name, bundleID: job.bundleID,
                     version: job.version, elapsedSeconds: job.elapsedSeconds,
                     extractionSeconds: job.extractionSeconds, signingSeconds: job.signingSeconds,
                     packagingSeconds: job.packagingSeconds, error: job.error,
                     otaManifest: manifest, otaDownload: download, installURL: install,
                     otaPublished: job.otaPublished)
    }
}

struct LocalZSignAPISettingsView: SwiftUI.View {
    @State private var copied = false

    private var api: LocalZSignAPI { .shared }

    var body: some SwiftUI.View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card {
                        Text("LOCAL ZSIGN API")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .kerning(1.2)
                            .foregroundStyle(Theme.subtle)
                        Text("https://\(api.host):\(api.port)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 4)
                        Text("Loopback only. The API controls the same local ZSign engine used by mSign; no signing request leaves this device.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.subtle)
                            .padding(.top, 4)
                    }

                    Card {
                        HStack {
                            Text("Status").foregroundStyle(Theme.subtle)
                            Spacer()
                            Text(api.isRunning ? "RUNNING" : "STOPPED")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundStyle(api.isRunning ? .green : .orange)
                        }
                        HStack {
                            Text("Engine").foregroundStyle(Theme.subtle)
                            Spacer()
                            Text("ZSign")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.text)
                        }
                        .padding(.top, 8)
                    }

                    Card {
                        Text("LOCAL TOKEN")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Theme.subtle)
                        Text(api.token)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .padding(.top, 5)
                        Button {
                            UIPasteboard.general.string = api.token
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy token", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.accent)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }

                    Card {
                        Text("ENDPOINTS")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Theme.subtle)
                        Text("POST /v1/sign\nGET /v1/jobs/:id\nGET /v1/jobs/:id/download\nGET /v1/status")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .padding(.top, 6)
                    }
                }
                .padding(16)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TabTitleBar(title: "Local ZSign API") { Text("LOOPBACK").font(.caption.monospaced()).foregroundStyle(Theme.subtle) }
        }
        .task { api.startIfNeeded() }
    }
}
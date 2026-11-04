// Sends an uploaded build to a public TestFlight group through the App Store
// Connect API, and submits it for Beta App Review. Scripts/upload.sh runs this.
//
//   swift Scripts/distribute.swift <bundle id>                     check the key, app and group
//   swift Scripts/distribute.swift <bundle id> <version> <build>   wait for the build, then send it
//
// Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH and BORMA_TESTFLIGHT_GROUP in
// the environment.

import CryptoKit
import Foundation

// MARK: - API responses

enum ProcessingState: String, Decodable {
    case processing = "PROCESSING"
    case failed = "FAILED"
    case invalid = "INVALID"
    case valid = "VALID"
}

struct Resource<Attributes: Decodable>: Decodable {
    let id: String
    let attributes: Attributes
}

struct Page<Attributes: Decodable>: Decodable {
    let data: [Resource<Attributes>]
}

struct AppAttributes: Decodable {
    let bundleId: String
}

struct BuildAttributes: Decodable {
    let processingState: ProcessingState
}

struct GroupAttributes: Decodable {
    let name: String
    let publicLinkEnabled: Bool?
}

struct ErrorResponse: Decodable {
    struct Item: Decodable {
        let title: String?
        let detail: String?
    }
    let errors: [Item]
}

// MARK: - Failures

enum Failure: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case appNotFound(String)
    case groupNotFound(String, available: [String])
    case groupNotPublic(String)
    case buildRejected(ProcessingState)
    case buildNeverAppeared(version: String, build: String)
    case api(status: Int, message: String)

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            "Set \(name) in the environment."
        case .appNotFound(let bundleID):
            "App Store Connect has no app with bundle id \(bundleID)."
        case .groupNotFound(let name, let available):
            "No TestFlight group named \"\(name)\". Groups: \(available.joined(separator: ", "))"
        case .groupNotPublic(let name):
            "The TestFlight group \"\(name)\" has no public link enabled."
        case .buildRejected(let state):
            "Apple finished processing the build with state \(state.rawValue)."
        case .buildNeverAppeared(let version, let build):
            "Gave up waiting for \(version) (\(build)) to finish processing."
        case .api(let status, let message):
            "App Store Connect returned \(status): \(message)"
        }
    }
}

// MARK: - Client

struct Client {
    let baseURL: URL
    let keyID: String
    let issuerID: String
    let key: P256.Signing.PrivateKey

    /// A fresh token for each request, since waiting for processing can outlast
    /// a token's lifetime.
    private func token() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = try encoded(["alg": "ES256", "kid": keyID, "typ": "JWT"])
        let payload = try encoded([
            "iss": issuerID,
            "iat": now,
            "exp": now + 600,
            "aud": "appstoreconnect-v1",
        ])
        let signingInput = "\(header).\(payload)"
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    private func encoded(_ object: [String: Any]) throws -> String {
        base64URL(try JSONSerialization.data(withJSONObject: object))
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let item = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.errors.first
            throw Failure.api(status: status, message: item?.detail ?? item?.title ?? "no details")
        }
        return data
    }

    func list<Attributes>(_ path: String, query: [String: String]) async throws -> [Resource<Attributes>] {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let data = try await send(URLRequest(url: components.url!))
        return try JSONDecoder().decode(Page<Attributes>.self, from: data).data
    }

    func post(_ path: String, body: [String: Any]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(request)
    }
}

// MARK: - Steps

func findApp(_ bundleID: String, _ client: Client) async throws -> Resource<AppAttributes> {
    let apps: [Resource<AppAttributes>] = try await client.list("/v1/apps", query: ["filter[bundleId]": bundleID])
    guard let app = apps.first(where: { $0.attributes.bundleId == bundleID }) else {
        throw Failure.appNotFound(bundleID)
    }
    return app
}

func findGroup(named name: String, appID: String, _ client: Client) async throws -> Resource<GroupAttributes> {
    let groups: [Resource<GroupAttributes>] = try await client.list(
        "/v1/betaGroups",
        query: ["filter[app]": appID, "limit": "200"]
    )
    guard let group = groups.first(where: { $0.attributes.name == name }) else {
        throw Failure.groupNotFound(name, available: groups.map(\.attributes.name))
    }
    guard group.attributes.publicLinkEnabled != false else {
        throw Failure.groupNotPublic(name)
    }
    return group
}

func waitForBuild(
    version: String,
    build: String,
    appID: String,
    _ client: Client
) async throws -> Resource<BuildAttributes> {
    let deadline = Date().addingTimeInterval(60 * 60)
    print("Waiting for Apple to process \(version) (\(build))...")
    while true {
        let builds: [Resource<BuildAttributes>] = try await client.list("/v1/builds", query: [
            "filter[app]": appID,
            "filter[version]": build,
            "filter[preReleaseVersion.version]": version,
        ])
        if let found = builds.first {
            switch found.attributes.processingState {
            case .valid:
                return found
            case .failed, .invalid:
                throw Failure.buildRejected(found.attributes.processingState)
            case .processing:
                break
            }
        }
        guard Date() < deadline else {
            throw Failure.buildNeverAppeared(version: version, build: build)
        }
        try await Task.sleep(for: .seconds(30))
    }
}

func submitForReview(buildID: String, _ client: Client) async throws {
    do {
        try await client.post("/v1/betaAppReviewSubmissions", body: [
            "data": [
                "type": "betaAppReviewSubmissions",
                "relationships": ["build": ["data": ["type": "builds", "id": buildID]]],
            ],
        ])
        print("Submitted for Beta App Review. Testers get it once Apple approves it.")
    } catch Failure.api(status: 409, let message) {
        // Apple refuses a second submission, or one the build doesn't need.
        print("Not submitted for review: \(message)")
    }
}

// MARK: - Main

func required(_ name: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        throw Failure.missingEnvironment(name)
    }
    return value
}

func run(bundleID: String, release: (version: String, build: String)?) async throws {
    let groupName = try required("BORMA_TESTFLIGHT_GROUP")
    let pem = try String(contentsOfFile: required("ASC_KEY_PATH"), encoding: .utf8)
    let client = Client(
        baseURL: URL(string: "https://api.appstoreconnect.apple.com")!,
        keyID: try required("ASC_KEY_ID"),
        issuerID: try required("ASC_ISSUER_ID"),
        key: try P256.Signing.PrivateKey(pemRepresentation: pem)
    )

    let app = try await findApp(bundleID, client)
    let group = try await findGroup(named: groupName, appID: app.id, client)

    guard let release else {
        print("App Store Connect is ready: \(bundleID), group \"\(groupName)\".")
        return
    }

    let build = try await waitForBuild(
        version: release.version,
        build: release.build,
        appID: app.id,
        client
    )

    try await client.post(
        "/v1/betaGroups/\(group.id)/relationships/builds",
        body: ["data": [["type": "builds", "id": build.id]]]
    )
    print("Added \(release.version) (\(release.build)) to \"\(groupName)\".")

    try await submitForReview(buildID: build.id, client)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let release: (version: String, build: String)?
switch arguments.count {
case 1:
    release = nil
case 3:
    release = (arguments[1], arguments[2])
default:
    fputs("usage: distribute.swift <bundle id> [<version> <build>]\n", stderr)
    exit(2)
}

do {
    try await run(bundleID: arguments[0], release: release)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

import Foundation
import TypeWhisperPluginSDK

struct TestEventBus: EventBusProtocol {
    func subscribe(handler: @escaping @Sendable (TypeWhisperEvent) async -> Void) -> UUID { UUID() }
    func unsubscribe(id: UUID) {}
}
struct TestHost: HostServices {
    let pluginDataDirectory: URL
    var activeAppBundleId: String? { nil }
    var activeAppName: String? { nil }
    var availableRuleNames: [String] { [] }
    var eventBus: any EventBusProtocol { TestEventBus() }
    func storeSecret(key: String, value: String) throws {}
    func loadSecret(key: String) -> String? { nil }
    func userDefault(forKey: String) -> Any? { nil }
    func setUserDefault(_ value: Any?, forKey: String) {}
    func notifyCapabilitiesChanged() {}
    func setStreamingDisplayActive(_ active: Bool) {}
}

func makeTestHost() throws -> TestHost {
    let directory = ProcessInfo.processInfo.environment["PHONON_TEST_DATA_DIR"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("phonon-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return TestHost(pluginDataDirectory: directory)
}

func waitForPlugin(_ plugin: any TranscriptionEnginePlugin) async throws {
    let deadline = Date().addingTimeInterval(1200)
    while !plugin.isConfigured {
        guard Date() < deadline else { throw NSError(domain: "Plugin readiness timeout", code: 1) }
        if let activity = (plugin as? any PluginSettingsActivityReporting)?.currentSettingsActivity, activity.isError {
            throw NSError(domain: activity.message, code: 2)
        }
        try await Task.sleep(for: .milliseconds(250))
    }
}

func cleanupTestHost(_ host: TestHost) {
    if ProcessInfo.processInfo.environment["PHONON_TEST_DATA_DIR"] == nil {
        try? FileManager.default.removeItem(at: host.pluginDataDirectory)
    }
}

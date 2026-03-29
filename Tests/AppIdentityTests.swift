import Testing
@testable import mrml

@Suite("AppIdentity Tests")
struct AppIdentityTests {

    @Test("Production bundle identity remains stable")
    func productionIdentity() {
        #expect(AppIdentity.isDevelopmentBuild(bundleIdentifier: "com.mrml.app") == false)
        #expect(AppIdentity.applicationSupportDirectoryName(bundleIdentifier: "com.mrml.app") == "Murmeln")
        #expect(AppIdentity.keychainServiceName(bundleIdentifier: "com.mrml.app") == "com.murmeln.apikeys")
        #expect(AppIdentity.loggerSubsystem(bundleIdentifier: "com.mrml.app") == "com.murmeln.app")
    }

    @Test("Development bundle identity uses isolated names")
    func developmentIdentity() {
        #expect(AppIdentity.isDevelopmentBuild(bundleIdentifier: "com.mrml.app.dev") == true)
        #expect(AppIdentity.applicationSupportDirectoryName(bundleIdentifier: "com.mrml.app.dev") == "Murmeln Dev")
        #expect(AppIdentity.keychainServiceName(bundleIdentifier: "com.mrml.app.dev") == "com.mrml.app.dev.apikeys")
        #expect(AppIdentity.loggerSubsystem(bundleIdentifier: "com.mrml.app.dev") == "com.murmeln.app.dev")
    }

    @Test("Nil bundle identifier falls back to production identity")
    func nilBundleIdentifierFallback() {
        #expect(AppIdentity.isDevelopmentBuild(bundleIdentifier: nil) == false)
        #expect(AppIdentity.applicationSupportDirectoryName(bundleIdentifier: nil) == "Murmeln")
        #expect(AppIdentity.keychainServiceName(bundleIdentifier: nil) == "com.murmeln.apikeys")
    }
}

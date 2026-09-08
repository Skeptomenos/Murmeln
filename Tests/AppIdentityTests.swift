import Foundation
import Testing
@testable import mrml

@Suite("AppIdentity Tests")
struct AppIdentityTests {

    @Test("Signing identity distinguishes builds that share a version and build number")
    func signingIdentityDistinguishesBuilds() {
        let first = Data((0..<20).map(UInt8.init))
        let second = Data(repeating: 255, count: 20)
        #expect(AppIdentity.codeHash(signingIdentifier: first) == "000102030405060708090a0b0c0d0e0f10111213")
        #expect(AppIdentity.codeHash(signingIdentifier: second) == String(repeating: "ff", count: 20))
        #expect(AppIdentity.codeHash(signingIdentifier: first) != AppIdentity.codeHash(signingIdentifier: second))
    }

    @Test("Unavailable or unexpected signing data stays unknown")
    func unavailableSigningIdentity() {
        #expect(AppIdentity.codeHash(signingIdentifier: nil) == nil)
        #expect(AppIdentity.codeHash(signingIdentifier: Data()) == nil)
        #expect(AppIdentity.codeHash(signingIdentifier: Data("not signature".utf8)) == nil)
        #expect(AppIdentity.codeHash(signingIdentifier: Data(repeating: 0, count: 21)) == nil)
    }

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

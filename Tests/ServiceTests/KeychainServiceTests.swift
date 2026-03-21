import Testing
import Foundation
@testable import mrml

@Suite("KeychainService Tests")
struct KeychainServiceTests {
    
    @Test("KeychainService is Sendable")
    func keychainServiceSendable() {
        let _: any Sendable = KeychainService.shared
        #expect(true)
    }
    
    @Test("KeychainService singleton is accessible")
    func keychainServiceSingleton() {
        let service = KeychainService.shared
        #expect(service === KeychainService.shared)
    }
    
    @Test("Save and retrieve value")
    func saveAndRetrieve() throws {
        let testKey = "test_key_\(UUID().uuidString)"
        let testValue = "test_value_123"
        
        // Save
        try KeychainService.shared.save(testValue, forKey: testKey)
        
        // Retrieve
        let retrieved = KeychainService.shared.retrieve(forKey: testKey)
        #expect(retrieved == testValue)
        
        // Cleanup
        try KeychainService.shared.delete(forKey: testKey)
    }
    
    @Test("Retrieve returns nil for non-existent key")
    func retrieveNonExistent() {
        let nonExistentKey = "non_existent_key_\(UUID().uuidString)"
        let result = KeychainService.shared.retrieve(forKey: nonExistentKey)
        #expect(result == nil)
    }
    
    @Test("Delete removes value")
    func deleteValue() throws {
        let testKey = "test_delete_\(UUID().uuidString)"
        let testValue = "value_to_delete"
        
        // Save
        try KeychainService.shared.save(testValue, forKey: testKey)
        #expect(KeychainService.shared.retrieve(forKey: testKey) == testValue)
        
        // Delete
        try KeychainService.shared.delete(forKey: testKey)
        
        // Verify deleted
        #expect(KeychainService.shared.retrieve(forKey: testKey) == nil)
    }
    
    @Test("Delete non-existent key does not throw")
    func deleteNonExistent() throws {
        let nonExistentKey = "non_existent_delete_\(UUID().uuidString)"
        // Should not throw
        try KeychainService.shared.delete(forKey: nonExistentKey)
        #expect(true)
    }
    
    @Test("Exists returns true for existing key")
    func existsTrue() throws {
        let testKey = "test_exists_\(UUID().uuidString)"
        let testValue = "exists_value"
        
        try KeychainService.shared.save(testValue, forKey: testKey)
        #expect(KeychainService.shared.exists(forKey: testKey) == true)
        
        // Cleanup
        try KeychainService.shared.delete(forKey: testKey)
    }
    
    @Test("Exists returns false for non-existent key")
    func existsFalse() {
        let nonExistentKey = "non_existent_exists_\(UUID().uuidString)"
        #expect(KeychainService.shared.exists(forKey: nonExistentKey) == false)
    }
    
    @Test("Overwrite existing value")
    func overwriteValue() throws {
        let testKey = "test_overwrite_\(UUID().uuidString)"
        let originalValue = "original"
        let newValue = "updated"
        
        // Save original
        try KeychainService.shared.save(originalValue, forKey: testKey)
        #expect(KeychainService.shared.retrieve(forKey: testKey) == originalValue)
        
        // Overwrite
        try KeychainService.shared.save(newValue, forKey: testKey)
        #expect(KeychainService.shared.retrieve(forKey: testKey) == newValue)
        
        // Cleanup
        try KeychainService.shared.delete(forKey: testKey)
    }
    
    @Test("Unicode value preservation")
    func unicodeValue() throws {
        let testKey = "test_unicode_\(UUID().uuidString)"
        let unicodeValue = "API🔑Key_日本語_émojis"
        
        try KeychainService.shared.save(unicodeValue, forKey: testKey)
        let retrieved = KeychainService.shared.retrieve(forKey: testKey)
        #expect(retrieved == unicodeValue)
        
        // Cleanup
        try KeychainService.shared.delete(forKey: testKey)
    }
    
    @Test("Empty string value")
    func emptyStringValue() throws {
        let testKey = "test_empty_\(UUID().uuidString)"
        let emptyValue = ""
        
        try KeychainService.shared.save(emptyValue, forKey: testKey)
        let retrieved = KeychainService.shared.retrieve(forKey: testKey)
        #expect(retrieved == emptyValue)
        
        // Cleanup
        try KeychainService.shared.delete(forKey: testKey)
    }
    
    @Test("Long API key value")
    func longValue() throws {
        let testKey = "test_long_\(UUID().uuidString)"
        let longValue = String(repeating: "a", count: 1000)
        
        try KeychainService.shared.save(longValue, forKey: testKey)
        let retrieved = KeychainService.shared.retrieve(forKey: testKey)
        #expect(retrieved == longValue)
        
        // Cleanup
        try KeychainService.shared.delete(forKey: testKey)
    }
}

@Suite("KeychainError Tests")
struct KeychainErrorTests {
    
    @Test("KeychainError has localized descriptions")
    func errorDescriptions() {
        let saveError = KeychainError.saveFailed(-25299)
        let deleteError = KeychainError.deleteFailed(-25300)
        let unexpectedData = KeychainError.unexpectedData
        let notFound = KeychainError.itemNotFound
        
        #expect(saveError.errorDescription != nil)
        #expect(deleteError.errorDescription != nil)
        #expect(unexpectedData.errorDescription != nil)
        #expect(notFound.errorDescription != nil)
    }
    
    @Test("Save failed error includes status code")
    func saveFailedStatus() {
        let error = KeychainError.saveFailed(-25299)
        #expect(error.errorDescription?.contains("-25299") == true)
    }
    
    @Test("Delete failed error includes status code")
    func deleteFailedStatus() {
        let error = KeychainError.deleteFailed(-25300)
        #expect(error.errorDescription?.contains("-25300") == true)
    }
}

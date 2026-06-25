import XCTest
@testable import DesktopTodo

final class KeychainServiceTests: XCTestCase {
    override func tearDown() async throws {
        try? KeychainService.shared.deleteAPIKey()
    }

    func testSaveAndLoadAPIKey() throws {
        try KeychainService.shared.save(apiKey: "sk-test-key-123")
        XCTAssertEqual(KeychainService.shared.loadAPIKey(), "sk-test-key-123")
    }

    func testOverwriteExistingKey() throws {
        try KeychainService.shared.save(apiKey: "sk-first")
        try KeychainService.shared.save(apiKey: "sk-second")
        XCTAssertEqual(KeychainService.shared.loadAPIKey(), "sk-second")
    }

    func testLoadMissingKeyReturnsNil() throws {
        try KeychainService.shared.deleteAPIKey()
        XCTAssertNil(KeychainService.shared.loadAPIKey())
    }

    func testDeleteNonExistentKeyDoesNotThrow() {
        XCTAssertNoThrow(try KeychainService.shared.deleteAPIKey())
    }
}

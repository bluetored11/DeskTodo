import Foundation
import Security

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:       return "无法编码 API Key"
        case .saveFailed(let s):    return "保存失败（错误码 \(s)）"
        case .deleteFailed(let s):  return "删除失败（错误码 \(s)）"
        }
    }
}

final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()
    private init() {}

    private let service = "DesktopTodo.OpenAI"
    private let account = "openai-api-key"

    func save(apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    func loadAPIKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    func deleteAPIKey() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

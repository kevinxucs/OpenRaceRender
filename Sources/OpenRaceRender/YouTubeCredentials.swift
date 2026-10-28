import Foundation
import Security
import RaceCore
import CryptoKit

@MainActor protocol YouTubeCredentialStore {
  func read(_ account:String) throws -> Data?
  func write(_ value:Data?,account:String) throws
}
@MainActor final class YouTubeKeychainStore:YouTubeCredentialStore {
  private let service = "org.openracerender.youtube"
  func read(_ account:String) throws -> Data? {
    var result:CFTypeRef?
    let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
    let status = SecItemCopyMatching(query as CFDictionary,&result)
    if status == errSecItemNotFound {return nil}
    guard status == errSecSuccess else {throw RaceError.invalid("Could not read OpenRaceRender’s YouTube Keychain item (\(status)).")}
    return result as? Data
  }
  func write(_ value:Data?,account:String) throws {
    let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
    let status:OSStatus
    if let value {
      let attributes:[String:Any] = [kSecValueData as String:value,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
      let update = SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
      if update == errSecItemNotFound {status = SecItemAdd(query.merging(attributes){_,new in new} as CFDictionary,nil)}
      else {status = update}
    } else {status = SecItemDelete(query as CFDictionary)}
    guard status == errSecSuccess || (value == nil && status == errSecItemNotFound) else {throw RaceError.invalid("Could not save OpenRaceRender’s YouTube Keychain item (\(status)).")}
  }
}

import Foundation

enum TxChatPublicLocalContract {
    static let protocolIdentifier = "txchat.public-local.v1"
    static let sessionPath = "/public-local/v1/session"
    static let refreshPath = "/public-local/v1/session/refresh"
    static let accountPath = "/public-local/v1/account"
    static let logoutPath = "/public-local/v1/logout"
    static let dictationPath = "/public-local/v1/dictation"
    static let audioMaxDurationSeconds = 300
}

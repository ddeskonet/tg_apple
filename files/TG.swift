import Foundation
import UIKit
import UserNotifications
import TDLibKit

enum Stage { case loading, api, phone, code, password, ready }

struct Msg: Identifiable, Codable {
    let id: Int64
    let chatId: Int64
    var text: String
    var out: Bool
    var date: Int
    var deleted = false
}

@MainActor
final class TG: ObservableObject {
    static let apiId = 0
    static let apiHash = ""

    @Published var stage = Stage.loading
    @Published var error = ""
    @Published var chats: [Int64: Chat] = [:]
    @Published var users: [Int64: User] = [:]
    @Published var files: [Int: String] = [:]
    @Published var me: User?
    @Published var bio = ""
    @Published private var log: [String: Msg] = [:]

    private var client: TDLibClient!
    private let manager = TDLibClientManager()
    private let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("log.json")

    init() {
        if let d = try? Data(contentsOf: logURL), let l = try? JSONDecoder().decode([String: Msg].self, from: d) { log = l }
        client = manager.createClient(updateHandler: { [weak self] data, client in
            guard let u = try? client.decoder.decode(Update.self, from: data) else { return }
            Task { @MainActor in self?.handle(u) }
        })
    }

    // MARK: обновления
    func handle(_ u: Update) {
        switch u {
        case .updateAuthorizationState(let s): auth(s.authorizationState)
        case .updateNewChat(let c): chats[c.chat.id] = c.chat; fetchPhoto(c.chat.photo?.small)
        case .updateChatLastMessage(let c): refreshChat(c.chatId)
        case .updateChatReadInbox(let c): refreshChat(c.chatId)
        case .updateChatTitle(let c): refreshChat(c.chatId)
        case .updateUser(let c): users[c.user.id] = c.user; fetchPhoto(c.user.profilePhoto?.small)
        case .updateUserStatus(let c): refreshUser(c.userId)
        case .updateFile(let c): if c.file.local.isDownloadingCompleted { files[c.file.id] = c.file.local.path }
        case .updateNewMessage(let c):
            keep(c.message); save()
            if !c.message.isOutgoing, UIApplication.shared.applicationState != .active {
                notify(chats[c.message.chatId]?.title ?? "Telegram", text(c.message))
            }
        case .updateMessageSendSucceeded(let c):
            log[key(c.message.chatId, c.oldMessageId)] = nil
            keep(c.message); save()
        case .updateDeleteMessages(let c):
            guard c.isPermanent else { break }
            for id in c.messageIds { log[key(c.chatId, id)]?.deleted = true }
            save()
        default: break
        }
    }

    func refreshChat(_ id: Int64) {
        Task { if let c = try? await client.getChat(chatId: id) { chats[id] = c } }
    }

    func refreshUser(_ id: Int64) {
        Task { if let u = try? await client.getUser(userId: id) { users[id] = u } }
    }

    func auth(_ s: AuthorizationState) {
        switch s {
        case .authorizationStateWaitTdlibParameters:
            let savedId = UserDefaults.standard.integer(forKey: "tg_api_id")
            let savedHash = UserDefaults.standard.string(forKey: "tg_api_hash") ?? ""
            if savedId > 0 && !savedHash.isEmpty {
                sendApi(id: savedId, hash: savedHash)
            } else if Self.apiId > 0 && !Self.apiHash.isEmpty {
                sendApi(id: Self.apiId, hash: Self.apiHash)
            } else {
                stage = .api
            }
        case .authorizationStateWaitPhoneNumber: stage = .phone
        case .authorizationStateWaitCode: stage = .code
        case .authorizationStateWaitPassword: stage = .password
        case .authorizationStateReady: stage = .ready; run { try await self.start() }
        default: break
        }
    }

    func sendApi(id: Int, hash: String) {
        let cleanHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id > 0, !cleanHash.isEmpty else {
            self.error = "Введите корректные api_id и api_hash"
            self.stage = .api
            return
        }
        UserDefaults.standard.set(id, forKey: "tg_api_id")
        UserDefaults.standard.set(cleanHash, forKey: "tg_api_hash")
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("td").path
        Task {
            do {
                self.error = ""
                _ = try await self.client.setTdlibParameters(
                    apiHash: cleanHash, apiId: id, applicationVersion: "1.0",
                    databaseDirectory: dir, databaseEncryptionKey: Data(),
                    deviceModel: UIDevice.current.model, filesDirectory: "",
                    systemLanguageCode: "ru", systemVersion: UIDevice.current.systemVersion,
                    useChatInfoDatabase: true, useFileDatabase: true,
                    useMessageDatabase: true, useSecretChats: false, useTestDc: false)
            } catch {
                self.error = "\(error)"
                self.stage = .api
            }
        }
    }

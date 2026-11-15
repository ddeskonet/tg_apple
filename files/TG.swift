import Foundation
import UIKit
import UserNotifications
import TDLibKit

enum Stage { case loading, phone, code, password, ready }

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
    // Ключи с my.telegram.org. Не выкладывайте их в публичный репозиторий.
    static let apiId = 0
    static let apiHash = ""

    @Published var stage = Stage.loading
    @Published var error = ""
    @Published var chats: [Int64: Chat] = [:]
    @Published var users: [Int64: User] = [:]
    @Published var files: [Int: String] = [:]
    @Published var me: User?
    @Published var bio = ""
    @Published private var log: [String: Msg] = [:]   // все увиденные сообщения, в том числе удалённые

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
        case .updateChatLastMessage(let c): chats[c.chatId]?.lastMessage = c.lastMessage
        case .updateChatReadInbox(let c): chats[c.chatId]?.unreadCount = c.unreadCount
        case .updateChatTitle(let c): chats[c.chatId]?.title = c.title
        case .updateUser(let c): users[c.user.id] = c.user; fetchPhoto(c.user.profilePhoto?.small)
        case .updateUserStatus(let c): users[c.userId]?.status = c.status
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

    func auth(_ s: AuthorizationState) {
        switch s {
        case .authorizationStateWaitTdlibParameters:
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("td").path
            run {
                _ = try await self.client.setTdlibParameters(
                    apiHash: Self.apiHash, apiId: Self.apiId, applicationVersion: "1.0",
                    databaseDirectory: dir, databaseEncryptionKey: Data(),
                    deviceModel: UIDevice.current.model, filesDirectory: "",
                    systemLanguageCode: "ru", systemVersion: UIDevice.current.systemVersion,
                    useChatInfoDatabase: true, useFileDatabase: true,
                    useMessageDatabase: true, useSecretChats: false, useTestDc: false)
            }
        case .authorizationStateWaitPhoneNumber: stage = .phone
        case .authorizationStateWaitCode: stage = .code
        case .authorizationStateWaitPassword: stage = .password
        case .authorizationStateReady: stage = .ready; run { try await self.start() }
        default: break
        }
    }

    func start() async throws {
        let m = try await client.getMe()
        me = m; users[m.id] = m
        fetchPhoto(m.profilePhoto?.small)
        bio = (try? await client.getUserFullInfo(userId: m.id).bio?.text) ?? ""
        _ = try? await client.loadChats(chatList: .chatListMain, limit: 60)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func run(_ f: @escaping () async throws -> Void) {
        Task { do { try await f() } catch { self.error = "\(error)" } }
    }

    // MARK: вход
    func sendPhone(_ p: String) { run { _ = try await self.client.setAuthenticationPhoneNumber(phoneNumber: p, settings: nil) } }
    func sendCode(_ c: String) { run { _ = try await self.client.checkAuthenticationCode(code: c) } }
    func sendPassword(_ p: String) { run { _ = try await self.client.checkAuthenticationPassword(password: p) } }
    func logout() { run { _ = try await self.client.logOut() } }

    // MARK: чаты и сообщения
    var sortedChats: [Chat] {
        chats.values.filter { $0.lastMessage != nil }.sorted { ($0.lastMessage?.date ?? 0) > ($1.lastMessage?.date ?? 0) }
    }

    func text(_ m: Message) -> String {
        if case .messageText(let t) = m.content { return t.text.text }
        return "[вложение]"
    }
    func key(_ chat: Int64, _ id: Int64) -> String { "\(chat):\(id)" }
    func keep(_ m: Message) {
        let k = key(m.chatId, m.id)
        log[k] = Msg(id: m.id, chatId: m.chatId, text: text(m), out: m.isOutgoing, date: m.date, deleted: log[k]?.deleted ?? false)
    }
    func save() { if let d = try? JSONEncoder().encode(log) { try? d.write(to: logURL) } }

    func thread(_ chat: Int64) -> [Msg] {
        log.values.filter { $0.chatId == chat }.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }
    func open(_ chat: Int64) {
        run {
            let h = try await self.client.getChatHistory(chatId: chat, fromMessageId: 0, limit: 50, offset: 0, onlyLocal: false)
            for m in h.messages ?? [] { self.keep(m) }
            self.save()
        }
    }
    func send(_ chat: Int64, _ t: String) {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        run {
            _ = try await self.client.sendMessage(
                chatId: chat,
                inputMessageContent: .inputMessageText(InputMessageText(clearDraft: true, linkPreviewOptions: nil, text: FormattedText(entities: [], text: s))),
                messageThreadId: 0, options: nil, replyMarkup: nil, replyTo: nil)
        }
    }

    // MARK: люди и статусы
    func userOf(_ c: Chat) -> User? {
        if case .chatTypePrivate(let t) = c.type { return users[t.userId] }
        return nil
    }
    func isBot(_ u: User) -> Bool { if case .userTypeBot = u.type { return true }; return false }
    func isOn(_ u: User?) -> Bool { if let u, case .userStatusOnline = u.status { return true }; return false }
    func rank(_ u: User) -> Int {
        let n = Int(Date().timeIntervalSince1970)
        switch u.status {
        case .userStatusOnline: return Int.max
        case .userStatusOffline(let s): return s.wasOnline
        case .userStatusRecently: return n - 3600
        case .userStatusLastWeek: return n - 4 * 86400
        case .userStatusLastMonth: return n - 15 * 86400
        default: return 0
        }
    }
    var people: [User] {
        chats.values.compactMap { userOf($0) }.filter { $0.id != me?.id && !isBot($0) }.sorted { rank($0) > rank($1) }
    }
    func seen(_ u: User?) -> String {
        guard let u else { return "" }
        if isBot(u) { return "бот" }
        switch u.status {
        case .userStatusOnline: return "в сети"
        case .userStatusOffline(let s): return "был(а) " + when(s.wasOnline)
        case .userStatusRecently: return "был(а) недавно"
        case .userStatusLastWeek: return "был(а) на этой неделе"
        case .userStatusLastMonth: return "был(а) в этом месяце"
        default: return "давно не был(а) в сети"
        }
    }
    func when(_ t: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(t)), cal = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"; let hm = f.string(from: d)
        if cal.isDateInToday(d) { return "сегодня в " + hm }
        if cal.isDateInYesterday(d) { return "вчера в " + hm }
        f.dateFormat = "dd.MM"; return f.string(from: d) + " в " + hm
    }

    // MARK: файлы, профиль, уведомления
    func fetchPhoto(_ f: File?) {
        guard let f else { return }
        if f.local.isDownloadingCompleted { files[f.id] = f.local.path }
        else { Task { _ = try? await client.downloadFile(fileId: f.id, limit: 0, offset: 0, priority: 1, synchronous: false) } }
    }
    func saveProfile(first: String, last: String, about: String, username: String) {
        run {
            _ = try await self.client.setName(firstName: first, lastName: last)
            _ = try await self.client.setBio(bio: about)
            if username != (self.me?.usernames?.activeUsernames.first ?? "") { _ = try await self.client.setUsername(username: username) }
            let m = try await self.client.getMe()
            self.me = m; self.users[m.id] = m; self.bio = about
        }
    }
    func setPhoto(_ data: Data) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("avatar.jpg")
        run {
            try data.write(to: url)
            _ = try await self.client.setProfilePhoto(isPublic: false, photo: .inputChatPhotoStatic(InputChatPhotoStatic(photo: .inputFileLocal(InputFileLocal(path: url.path)))))
            let m = try await self.client.getMe()
            self.me = m; self.users[m.id] = m; self.fetchPhoto(m.profilePhoto?.small)
        }
    }
    func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

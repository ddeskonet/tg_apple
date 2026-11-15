import SwiftUI
import PhotosUI
import TDLibKit

enum Theme {
    static let bg = Color(red: 0.043, green: 0.043, blue: 0.043)
    static let card = Color(white: 0.09)
    static let line = Color(white: 0.18)
    static let text = Color(red: 0.96, green: 0.957, blue: 0.933)
    static let muted = Color(red: 0.541, green: 0.541, blue: 0.522)
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
}

struct RootView: View {
    @EnvironmentObject var tg: TG
    var body: some View {
        Group {
            if tg.stage == .ready { MainTabs().transition(.opacity) }
            else { LoginView().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.25), value: tg.stage)
    }
}

struct Avatar: View {
    @EnvironmentObject var tg: TG
    let title: String
    let file: File?
    var size: CGFloat = 52
    var online = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let f = file, let p = tg.files[f.id], let img = UIImage(contentsOfFile: p) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Text(String(title.prefix(1)).uppercased()).font(.system(size: size * 0.42, design: .serif))
                }
            }
            .frame(width: size, height: size).background(Theme.card)
            .clipShape(Circle()).overlay(Circle().stroke(Theme.line))
            if online {
                Circle().fill(Theme.accent).frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var tg: TG
    @State private var text = ""
    var label: String {
        switch tg.stage {
        case .phone: return "Номер телефона"
        case .code: return "Код из Telegram"
        case .password: return "Пароль двухэтапной защиты"
        default: return "Подключаемся…"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Войти").font(.system(size: 40, design: .serif))
            Text(label).foregroundStyle(Theme.muted)
            if tg.stage != .loading {
                Group {
                    if tg.stage == .password { SecureField("", text: $text) }
                    else { TextField("", text: $text).keyboardType(tg.stage == .phone ? .phonePad : .numberPad) }
                }
                .padding().background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                Button {
                    let t = text; text = ""
                    switch tg.stage {
                    case .phone: tg.sendPhone(t)
                    case .code: tg.sendCode(t)
                    case .password: tg.sendPassword(t)
                    default: break
                    }
                } label: {
                    Text("Дальше").bold().frame(maxWidth: .infinity).padding()
                        .background(Theme.accent).foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            Text(tg.error).font(.footnote).foregroundStyle(Theme.accent)
            Spacer()
        }
        .padding(24).padding(.top, 60)
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct MainTabs: View {
    @State private var tab = 1
    var body: some View {
        TabView(selection: $tab) {
            PeopleView().tabItem { Label("Контакты", systemImage: "person.crop.circle") }.tag(0)
            ChatsView().tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }.tag(1)
            SettingsView().tabItem { Label("Настройки", systemImage: "gearshape") }.tag(2)
        }
    }
}

struct ChatsView: View {
    @EnvironmentObject var tg: TG
    var body: some View {
        NavigationStack {
            List(tg.sortedChats, id: \.id) { c in
                NavigationLink(value: c.id) { ChatRowView(chat: c) }
                    .listRowBackground(Theme.bg).listRowSeparatorTint(Theme.line)
            }
            .listStyle(.plain).background(Theme.bg)
            .navigationTitle("Чаты")
            .navigationDestination(for: Int64.self) { ChatView(chatId: $0) }
        }
    }
}

struct ChatRowView: View {
    @EnvironmentObject var tg: TG
    let chat: Chat
    var body: some View {
        HStack(spacing: 14) {
            Avatar(title: chat.title, file: chat.photo?.small, online: tg.isOn(tg.userOf(chat)))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(chat.title).bold().lineLimit(1)
                    Spacer()
                    if let m = chat.lastMessage {
                        Text(Date(timeIntervalSince1970: TimeInterval(m.date)).formatted(date: .omitted, time: .shortened))
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                HStack {
                    Text(chat.lastMessage.map { tg.text($0) } ?? "").foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)").font(.footnote.bold()).foregroundStyle(.black)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.accent).clipShape(Capsule())
                    }
                }
            }
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var tg: TG
    let chatId: Int64
    @State private var text = ""
    var body: some View {
        let msgs = tg.thread(chatId)
        let user = tg.chats[chatId].flatMap { tg.userOf($0) }
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(msgs) { m in
                            Bubble(m: m).id(m.id).transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }.padding(12)
                }
                .onAppear { proxy.scrollTo(msgs.last?.id, anchor: .bottom) }
                .onChange(of: msgs.count) { _ in withAnimation { proxy.scrollTo(msgs.last?.id, anchor: .bottom) } }
            }
            HStack {
                TextField("Сообщение", text: $text).padding(12).background(Theme.card).clipShape(Capsule())
                Button { tg.send(chatId, text); text = "" } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 36))
                }
            }.padding(10)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(tg.chats[chatId]?.title ?? "").font(.headline)
                    if user != nil { Text(tg.seen(user)).font(.caption).foregroundStyle(tg.isOn(user) ? Theme.accent : Theme.muted) }
                }
            }
        }
        .task { tg.open(chatId) }
        .animation(.easeOut(duration: 0.2), value: msgs.count)
    }
}

struct Bubble: View {
    let m: Msg
    var body: some View {
        let fgColor: Color = m.deleted ? Theme.muted : (m.out ? Color.black : Theme.text)
        let bgColor: Color = m.deleted ? Color.clear : (m.out ? Theme.accent : Theme.card)
        HStack {
            if m.out { Spacer(minLength: 50) }
            VStack(alignment: .trailing, spacing: 2) {
                if m.deleted { Text("удалено").font(.caption2).foregroundStyle(Theme.accent) }
                Text(m.text)
                Text(Date(timeIntervalSince1970: TimeInterval(m.date)).formatted(date: .omitted, time: .shortened))
                    .font(.caption2).opacity(0.6)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(fgColor)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .opacity(m.deleted ? 1 : 0)
            )
            if !m.out { Spacer(minLength: 50) }
        }
    }
}

struct PeopleView: View {
    @EnvironmentObject var tg: TG
    var body: some View {
        NavigationStack {
            List(tg.people, id: \.id) { u in
                let fullName = "\(u.firstName) \(u.lastName)".trimmingCharacters(in: .whitespaces)
                HStack(spacing: 14) {
                    Avatar(title: u.firstName, file: u.profilePhoto?.small, online: tg.isOn(u))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fullName).bold()
                        Text(tg.seen(u)).font(.subheadline).foregroundStyle(tg.isOn(u) ? Theme.accent : Theme.muted)
                    }
                }
                .listRowBackground(Theme.bg).listRowSeparatorTint(Theme.line)
            }
            .listStyle(.plain).background(Theme.bg)
            .navigationTitle("Контакты")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var tg: TG
    var fullName: String {
        let f = tg.me?.firstName ?? ""
        let l = tg.me?.lastName ?? ""
        return "\(f) \(l)".trimmingCharacters(in: .whitespaces)
    }
    var subTitle: String {
        let phone = tg.me?.phoneNumber ?? ""
        if let uname = tg.me?.usernames?.activeUsernames.first, !uname.isEmpty {
            return "+\(phone) · @\(uname)"
        }
        return "+\(phone)"
    }
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { ProfileView() } label: {
                    HStack(spacing: 14) {
                        Avatar(title: tg.me?.firstName ?? "", file: tg.me?.profilePhoto?.small, size: 72)
                        VStack(alignment: .leading) {
                            Text(fullName).font(.system(size: 22, design: .serif))
                            Text(subTitle).font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }.listRowBackground(Theme.card)
                Button("Выйти на этом устройстве", role: .destructive) { tg.logout() }.listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Настройки")
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var tg: TG
    @State private var first = ""
    @State private var last = ""
    @State private var about = ""
    @State private var uname = ""
    @State private var pick: PhotosPickerItem?
    var body: some View {
        let phoneStr = "+\(tg.me?.phoneNumber ?? "")"
        let idStr = "\(tg.me?.id ?? 0)"
        Form {
            Section {
                VStack(spacing: 8) {
                    Avatar(title: first, file: tg.me?.profilePhoto?.small, size: 104)
                    PhotosPicker("Сменить фото", selection: $pick, matching: .images)
                }.frame(maxWidth: .infinity)
            }
            Section {
                TextField("Имя", text: $first)
                TextField("Фамилия", text: $last)
                TextField("О себе", text: $about)
                TextField("Имя пользователя", text: $uname).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section {
                LabeledContent("Телефон", value: phoneStr)
                Button { UIPasteboard.general.string = idStr } label: {
                    LabeledContent("ID (нажмите, чтобы скопировать)", value: idStr)
                }
            }
            Button("Сохранить") { tg.saveProfile(first: first, last: last, about: about, username: uname) }
            if !tg.error.isEmpty { Text(tg.error).font(.footnote).foregroundStyle(Theme.accent) }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Мой профиль")
        .onAppear {
            first = tg.me?.firstName ?? ""
            last = tg.me?.lastName ?? ""
            about = tg.bio
            uname = tg.me?.usernames?.activeUsernames.first ?? ""
        }
        .onChange(of: pick) { _ in
            Task { if let d = try? await pick?.loadTransferable(type: Data.self) { tg.setPhoto(d) } }
        }
    }
}

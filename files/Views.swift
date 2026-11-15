struct LoginView: View {
    @EnvironmentObject var tg: TG
    @State private var text = ""
    @State private var apiIdText = ""
    @State private var apiHashText = ""
    var label: String {
        switch tg.stage {
        case .api: return "Ключи с my.telegram.org"
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
            if tg.stage == .api {
                TextField("App api_id (цифры)", text: $apiIdText)
                    .keyboardType(.numberPad)
                    .padding().background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                TextField("App api_hash (строка)", text: $apiHashText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding().background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                Button {
                    tg.sendApi(id: Int(apiIdText.trimmingCharacters(in: .whitespaces)) ?? 0, hash: apiHashText)
                } label: {
                    Text("Дальше").bold().frame(maxWidth: .infinity).padding()
                        .background(Theme.accent).foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else if tg.stage != .loading {
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

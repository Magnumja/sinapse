import Foundation

/// Um conjunto de apps e sites permitidos, por matéria ou tipo de estudo.
struct Profile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var allowedApps: [String]
    var allowedSites: [String]

    private static let aiApps = ["com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex"]
    private static let aiSites = [
        "claude.ai", "anthropic.com", "chatgpt.com", "openai.com",
        "gemini.google.com", "notebooklm.google.com", "perplexity.ai", "accounts.google.com",
    ]

    static let general = Profile(
        name: "Estudo",
        allowedApps: aiApps + [
            "com.google.Chrome", "com.apple.Safari",
            "md.obsidian", "com.apple.Preview", "com.apple.Notes", "com.apple.calculator",
        ],
        allowedSites: aiSites + ["docs.google.com", "drive.google.com"]
    )

    static let templates = [
        Profile(
            name: "Programação",
            allowedApps: aiApps + [
                "com.google.Chrome", "com.apple.Safari",
                "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode",
                "com.apple.Terminal", "com.googlecode.iterm2", "com.github.GitHubClient",
            ],
            allowedSites: aiSites + [
                "github.com", "stackoverflow.com", "developer.apple.com", "developer.mozilla.org",
                "localhost", "127.0.0.1",
            ]
        ),
        Profile(
            name: "Leitura",
            allowedApps: aiApps + ["com.apple.Preview", "com.apple.iBooksX", "com.apple.Notes", "md.obsidian"],
            allowedSites: aiSites
        ),
    ]
}

struct Config: Codable {
    var profiles: [Profile]
    var activeProfileID: UUID
    var studyMinutes = 60
    var breakMinutes = 10
    var cycles = 3
    var reminderMinutes = 20
    var cancelPhrase = "Estou cancelando meu foco agora e sei que só devo fazer isso numa emergência"

    static let `default` = Config(profiles: [Profile.general] + Profile.templates, activeProfileID: Profile.general.id)

    /// Perfil em uso: o escolhido, ou o primeiro se ele não existir mais.
    var activeProfile: Profile {
        get { profiles.first { $0.id == activeProfileID } ?? profiles[0] }
        set { if let i = profiles.firstIndex(where: { $0.id == newValue.id }) { profiles[i] = newValue } }
    }

    // Atalhos para as listas do perfil em uso.
    var allowedApps: [String] {
        get { activeProfile.allowedApps }
        set { activeProfile.allowedApps = newValue }
    }

    var allowedSites: [String] {
        get { activeProfile.allowedSites }
        set { activeProfile.allowedSites = newValue }
    }
}

extension Config {
    private enum CodingKeys: String, CodingKey {
        case profiles, activeProfileID, studyMinutes, breakMinutes, cycles, reminderMinutes, cancelPhrase
        case allowedApps, allowedSites // formato da 1.0.x, só para leitura
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        studyMinutes = try c.decodeIfPresent(Int.self, forKey: .studyMinutes) ?? d.studyMinutes
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? d.breakMinutes
        cycles = try c.decodeIfPresent(Int.self, forKey: .cycles) ?? d.cycles
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? d.reminderMinutes
        cancelPhrase = try c.decodeIfPresent(String.self, forKey: .cancelPhrase) ?? d.cancelPhrase

        if let saved = try c.decodeIfPresent([Profile].self, forKey: .profiles), !saved.isEmpty {
            profiles = saved
            activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID) ?? saved[0].id
        } else {
            // 1.0.x tinha uma lista só: ela vira o perfil "Estudo", e os modelos entram junto.
            var general = Profile.general
            general.allowedApps = try c.decodeIfPresent([String].self, forKey: .allowedApps) ?? general.allowedApps
            general.allowedSites = try c.decodeIfPresent([String].self, forKey: .allowedSites) ?? general.allowedSites
            profiles = [general] + Profile.templates
            activeProfileID = general.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(activeProfileID, forKey: .activeProfileID)
        try c.encode(studyMinutes, forKey: .studyMinutes)
        try c.encode(breakMinutes, forKey: .breakMinutes)
        try c.encode(cycles, forKey: .cycles)
        try c.encode(reminderMinutes, forKey: .reminderMinutes)
        try c.encode(cancelPhrase, forKey: .cancelPhrase)
    }
}

struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var intention: String
    var studiedMinutes: Int
    var completed: Bool
    var learned: String
    var profile: String?
}

@MainActor
final class Store: ObservableObject {
    @Published var config: Config { didSet { if !demo { Self.save(config, Self.configKey) } } }
    @Published private(set) var history: [SessionRecord] { didSet { if !demo { Self.save(history, Self.historyKey) } } }

    /// Modo demonstração (--preview): nada é salvo.
    private var demo = false
    private static let configKey = "sinapse.config"
    private static let historyKey = "sinapse.history"

    /// Configuração padrão e histórico de exemplo para prints, só em memória.
    func useDemoHistory() {
        demo = true
        config = .default
        let cal = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -daysAgo, to: Date())!)!
        }
        history = [
            SessionRecord(start: at(0, 9), end: at(0, 12), intention: "Cálculo · cap. 3", studiedMinutes: 180, completed: true,
                          learned: "Regra da cadeia\nDerivada implícita\nTaxas relacionadas", profile: "Estudo"),
            SessionRecord(start: at(1, 14), end: at(1, 16), intention: "Inglês · listening", studiedMinutes: 110, completed: true, learned: "", profile: "Estudo"),
            SessionRecord(start: at(2, 19), end: at(2, 19), intention: "Física · cinemática", studiedMinutes: 35, completed: false, learned: "", profile: "Leitura"),
            SessionRecord(start: at(3, 8), end: at(3, 11), intention: "Algoritmos · grafos", studiedMinutes: 180, completed: true,
                          learned: "BFS acha o menor caminho sem pesos\nDijkstra usa fila de prioridade", profile: "Programação"),
        ]
    }

    init() {
        config = Self.load(Self.configKey) ?? .default
        history = Self.load(Self.historyKey) ?? []
        // O app ChatGPT para Mac pode usar qualquer um dos dois identificadores.
        if config.allowedApps.contains("com.openai.chat"), !config.allowedApps.contains("com.openai.codex") {
            config.allowedApps.append("com.openai.codex")
        }
    }

    func add(_ record: SessionRecord) { history.insert(record, at: 0) }

    func setLearned(_ text: String, for id: UUID) {
        if let i = history.firstIndex(where: { $0.id == id }) { history[i].learned = text }
    }

    // MARK: Perfis

    func selectProfile(_ id: UUID) { config.activeProfileID = id }

    /// Cria um perfil copiando o atual, e já passa a usá-lo.
    func addProfile() {
        let names = Set(config.profiles.map(\.name))
        var n = config.profiles.count + 1
        while names.contains("Perfil \(n)") { n += 1 }
        var copy = config.activeProfile
        copy.id = UUID()
        copy.name = "Perfil \(n)"
        config.profiles.append(copy)
        config.activeProfileID = copy.id
    }

    func renameActiveProfile(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { config.activeProfile.name = trimmed }
    }

    /// Apaga o perfil atual (sempre sobra pelo menos um).
    func deleteActiveProfile() {
        guard config.profiles.count > 1 else { return }
        config.profiles.removeAll { $0.id == config.activeProfileID }
        config.activeProfileID = config.profiles[0].id
    }

    var minutesToday: Int {
        history.filter { Calendar.current.isDateInToday($0.start) }.reduce(0) { $0 + $1.studiedMinutes }
    }

    var minutesThisWeek: Int {
        history.filter { Calendar.current.isDate($0.start, equalTo: Date(), toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.studiedMinutes }
    }

    /// Dias seguidos com pelo menos uma sessão (hoje conta se já houver sessão).
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(history.filter { $0.studiedMinutes > 0 }.map { cal.startOfDay(for: $0.start) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

import Foundation

struct Config: Codable {
    var allowedApps: [String]
    var allowedSites: [String]
    var studyMinutes = 60
    var breakMinutes = 10
    var cycles = 3
    var reminderMinutes = 20
    var cancelPhrase = "Estou cancelando meu foco agora e sei que só devo fazer isso numa emergência"

    static let `default` = Config(
        allowedApps: [
            "com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex",
            "com.google.Chrome", "com.apple.Safari",
            "md.obsidian", "com.apple.Preview", "com.apple.Notes", "com.apple.calculator",
        ],
        allowedSites: [
            "claude.ai", "anthropic.com", "chatgpt.com", "openai.com",
            "gemini.google.com", "notebooklm.google.com", "perplexity.ai",
            "accounts.google.com", "docs.google.com", "drive.google.com",
        ]
    )
}

struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var intention: String
    var studiedMinutes: Int
    var completed: Bool
    var learned: String
}

@MainActor
final class Store: ObservableObject {
    @Published var config: Config { didSet { if !demo { Self.save(config, Self.configKey) } } }
    @Published private(set) var history: [SessionRecord] { didSet { if !demo { Self.save(history, Self.historyKey) } } }

    /// Modo demonstração (--preview): nada é salvo.
    private var demo = false
    private static let configKey = "sinapse.config"
    private static let historyKey = "sinapse.history"

    /// Histórico de exemplo para prints, só em memória.
    func useDemoHistory() {
        demo = true
        let cal = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -daysAgo, to: Date())!)!
        }
        history = [
            SessionRecord(start: at(0, 9), end: at(0, 12), intention: "Cálculo · cap. 3", studiedMinutes: 180, completed: true,
                          learned: "Regra da cadeia\nDerivada implícita\nTaxas relacionadas"),
            SessionRecord(start: at(1, 14), end: at(1, 16), intention: "Inglês · listening", studiedMinutes: 110, completed: true, learned: ""),
            SessionRecord(start: at(2, 19), end: at(2, 19), intention: "Física · cinemática", studiedMinutes: 35, completed: false, learned: ""),
            SessionRecord(start: at(3, 8), end: at(3, 11), intention: "Algoritmos · grafos", studiedMinutes: 180, completed: true,
                          learned: "BFS acha o menor caminho sem pesos\nDijkstra usa fila de prioridade"),
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

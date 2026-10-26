import AppKit
import UserNotifications

struct ActiveSession: Codable {
    var intention: String
    var start: Date
    var cycle: Int
    var totalCycles: Int
    var studyMinutes: Int
    var breakMinutes: Int
    var reminderMinutes: Int
    var isBreak: Bool
    var phaseStart: Date
    var phaseEnd: Date
    var studiedSeconds: Double
    var nextReminder: Date?
}

enum Tips {
    static let breaks = [
        "Levanta e alonga as costas e o pescoço.",
        "Bebe um copo d'água.",
        "Olha pela janela, pra algo distante, por 20 segundos.",
        "Dá uma volta pela casa.",
        "Respira fundo 5 vezes, bem devagar.",
        "Lava o rosto e volta renovado.",
    ]
    static let reminders = [
        "Postura: costas retas, ombros relaxados.",
        "Bebe um gole d'água 💧",
        "Pisca bastante e olha pra longe por 20 segundos.",
        "Ainda está no assunto que você se propôs?",
    ]
}

@MainActor
final class FocusEngine: ObservableObject {
    @Published private(set) var session: ActiveSession? { didSet { persist() } }
    @Published private(set) var now = Date()
    /// Navegadores permitidos em que o Sinapse não tem permissão de Automação (ficam sem filtro de sites).
    @Published private(set) var automationProblems: [String] = []

    let store: Store
    /// Modo demonstração (--preview): mostra uma sessão sem fechar apps, filtrar sites nem salvar nada.
    private(set) var dryRun = false
    private var timer: Timer?
    private var lastTick = Date()
    private var lastBrowserCheck = Date.distantPast
    private var lastNotified: [String: Date] = [:]
    private static let sessionKey = "sinapse.activeSession"

    private static let alwaysAllowed: Set<String> = [
        "com.apple.finder", "com.apple.loginwindow", "com.apple.dock",
        "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.notificationcenterui",
    ]

    init(store: Store) {
        self.store = store
        if let data = UserDefaults.standard.data(forKey: Self.sessionKey),
           let saved = try? JSONDecoder().decode(ActiveSession.self, from: data) {
            session = saved
        }

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor in self?.enforce(app) }
            }
        }
    }

    // MARK: - Sessão

    func start(intention: String) {
        let c = store.config
        let n = Date()
        lastTick = n
        session = ActiveSession(
            intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
            start: n, cycle: 1, totalCycles: c.cycles,
            studyMinutes: c.studyMinutes, breakMinutes: c.breakMinutes, reminderMinutes: c.reminderMinutes,
            isBreak: false, phaseStart: n, phaseEnd: n + Double(c.studyMinutes * 60),
            studiedSeconds: 0,
            nextReminder: c.reminderMinutes > 0 ? n + Double(c.reminderMinutes * 60) : nil
        )
        if !dryRun { Notifier.send("Foco iniciado 🎯", "\(c.studyMinutes) min de estudo. Bora!") }
        sweepApps()
    }

    func enableDemo() { dryRun = true }

    /// Sessão de mentira, no meio do 2º ciclo, para prints.
    func startDemo(intention: String) {
        enableDemo()
        start(intention: intention)
        guard var s = session else { return }
        let n = Date()
        s.cycle = 2
        s.phaseStart = n - Double(s.studyMinutes * 60) * 0.62
        s.phaseEnd = s.phaseStart + Double(s.studyMinutes * 60)
        session = s
    }

    func cancel() { finish(completed: false) }

    private func finish(completed: Bool) {
        guard let s = session else { return }
        let record = SessionRecord(
            start: s.start, end: Date(), intention: s.intention,
            studiedMinutes: Int(s.studiedSeconds / 60), completed: completed, learned: ""
        )
        store.add(record)
        session = nil
        Windows.close("break")
        if completed {
            Notifier.send("Sessão concluída 🎉", "Você estudou \(record.studiedMinutes) min.")
            Windows.show("end", title: "Sessão concluída", replace: true) {
                EndView(store: self.store, record: record)
            }
        }
    }

    private func tick() {
        let n = Date()
        let delta = n.timeIntervalSince(lastTick)
        lastTick = n
        now = n
        guard var s = session else { return }

        // Se o Mac dormiu, não conta o tempo dormindo como estudo.
        if !s.isBreak { s.studiedSeconds += min(delta, 2) }

        if n >= s.phaseEnd {
            if s.isBreak {
                s.isBreak = false
                s.cycle += 1
                s.phaseStart = n
                s.phaseEnd = n + Double(s.studyMinutes * 60)
                s.nextReminder = s.reminderMinutes > 0 ? n + Double(s.reminderMinutes * 60) : nil
                session = s
                Windows.close("break")
                Notifier.send("Pausa acabou", "De volta ao foco: ciclo \(s.cycle) de \(s.totalCycles).")
                sweepApps()
            } else if s.cycle >= s.totalCycles {
                session = s
                finish(completed: true)
            } else {
                s.isBreak = true
                s.phaseStart = n
                s.phaseEnd = n + Double(s.breakMinutes * 60)
                session = s
                let tip = Tips.breaks.randomElement()!
                Notifier.send("Hora da pausa ☕", tip)
                Windows.show("break", title: "Pausa", floating: true, dark: true, replace: true) {
                    BreakView(engine: self, tip: tip)
                }
            }
            return
        }

        if !s.isBreak, let r = s.nextReminder, n >= r {
            if s.phaseEnd.timeIntervalSince(n) > 180 { Notifier.send("Lembrete", Tips.reminders.randomElement()!) }
            s.nextReminder = r + Double(s.reminderMinutes * 60)
        }
        session = s

        if !s.isBreak {
            sweepApps()
            if n.timeIntervalSince(lastBrowserCheck) >= 2 {
                lastBrowserCheck = n
                filterBrowsers()
            }
        }
    }

    private func persist() {
        guard !dryRun else { return }
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        }
    }

    // MARK: - Bloqueio

    private var isStudying: Bool { !dryRun && (session.map { !$0.isBreak } ?? false) }

    private func isAllowed(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return true }
        if id == Bundle.main.bundleIdentifier || Self.alwaysAllowed.contains(id) { return true }
        return store.config.allowedApps.contains(id)
    }

    /// Apps abertos agora que seriam fechados ao iniciar o foco.
    func appsThatWillClose() -> [String] {
        if dryRun { return ["WhatsApp", "Discord", "Steam"] }
        return NSWorkspace.shared.runningApplications.filter { !isAllowed($0) }.compactMap(\.localizedName)
    }

    private func enforce(_ app: NSRunningApplication) {
        guard isStudying, !isAllowed(app) else { return }
        block(app)
    }

    private func sweepApps() {
        guard isStudying else { return }
        for app in NSWorkspace.shared.runningApplications where !isAllowed(app) { block(app) }
    }

    private func block(_ app: NSRunningApplication) {
        app.hide()
        app.terminate()
        let name = app.localizedName ?? "App"
        notifyOnce(key: "app:" + (app.bundleIdentifier ?? name), "\(name) foi fechado", "Não está na sua lista de foco.")
    }

    private func filterBrowsers() {
        guard !dryRun else { return }
        var problems: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, BrowserFilter.scriptable.contains(id),
                  store.config.allowedApps.contains(id) else { continue }
            switch BrowserFilter.filter(bundleID: id, sites: store.config.allowedSites) {
            case .success(let hosts):
                for host in hosts where !host.isEmpty {
                    notifyOnce(key: "site:" + host, "Site bloqueado", "\(host) não está na sua lista de foco.")
                }
            case .failure(.notAuthorized):
                problems.append(app.localizedName ?? id)
            case .failure(.other):
                break
            }
        }
        if problems != automationProblems { automationProblems = problems }
    }

    private func notifyOnce(key: String, _ title: String, _ body: String) {
        if let last = lastNotified[key], Date().timeIntervalSince(last) < 30 { return }
        lastNotified[key] = Date()
        Notifier.send(title, body)
    }

    // MARK: - Exibição

    var remainingString: String {
        guard let s = session else { return "" }
        let secs = max(0, Int(s.phaseEnd.timeIntervalSince(now).rounded(.up)))
        let h = secs / 3600, m = (secs % 3600) / 60, sec = secs % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    var phaseProgress: Double {
        guard let s = session else { return 0 }
        let total = s.phaseEnd.timeIntervalSince(s.phaseStart)
        return total > 0 ? min(1, max(0, now.timeIntervalSince(s.phaseStart) / total)) : 0
    }
}

// MARK: - Notificações

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

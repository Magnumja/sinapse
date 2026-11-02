import AppKit
import SwiftUI

// MARK: - Janelas avulsas (o app vive na barra de menu, sem Dock)

@MainActor
enum Windows {
    private static var open: [String: NSWindow] = [:]

    static func show<V: View>(
        _ id: String, title: String, floating: Bool = false, dark: Bool = false, replace: Bool = false,
        @ViewBuilder content: () -> V
    ) {
        if replace { close(id) }
        if let w = open[id] {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = content()
            .background(VisualEffect(material: dark ? .hudWindow : .sidebar).ignoresSafeArea())
        let host = NSHostingController(rootView: root)
        // Tamanho medido uma vez: deixar o SwiftUI redimensionar a janela a cada segundo gera loop de layout.
        host.sizingOptions = []
        let size = host.view.fittingSize
        let w = NSWindow(contentViewController: host)
        w.setContentSize(size)
        w.title = title
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isOpaque = false
        w.backgroundColor = .clear
        w.isReleasedWhenClosed = false
        if dark { w.appearance = NSAppearance(named: .darkAqua) }
        if floating { w.level = .floating }
        w.center()
        open[id] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            Task { @MainActor in if open[id] === w { open[id] = nil } }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close(_ id: String) {
        open.removeValue(forKey: id)?.close()
    }

    /// Salva a janela como PNG (usado só pelo modo --preview).
    static func snapshot(_ id: String, to path: String) {
        guard let view = open[id]?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Menu da barra

struct MenuView: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: FocusEngine
    @State private var intention = ""

    private static let presets: [(study: Int, rest: Int)] = [(25, 5), (50, 10), (60, 10), (90, 15)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LogoMark(size: 22)
                Text("Sinapse").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(store.minutesToday + engine.liveMinutes) min hoje")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            if let s = engine.session {
                active(s)
            } else {
                idle
            }

            Divider().opacity(0.5)

            HStack(spacing: 16) {
                FooterButton(title: "Ajustes", icon: "slider.horizontal.3") {
                    Windows.show("config", title: "Ajustes") { SettingsView(store: store, engine: engine) }
                }
                FooterButton(title: "Histórico", icon: "chart.bar") {
                    Windows.show("history", title: "Histórico") { HistoryView(store: store, engine: engine) }
                }
                Spacer()
                if engine.session == nil {
                    FooterButton(title: "Sair", icon: "power") { NSApp.terminate(nil) }
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: Parado

    private var idle: some View {
        let c = store.config
        let total = c.cycles * c.studyMinutes + (c.cycles - 1) * c.breakMinutes
        let toClose = engine.appsThatWillClose()
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Objetivo")
                TextField("O que você vai estudar?", text: $intention)
                    .textFieldStyle(.plain)
                    .onSubmit(start)
                    .card(padding: 10)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Perfil")
                ProfileChips(store: store)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Ritmo · estudo / pausa")
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.study) { p in
                        Chip(title: "\(p.study)/\(p.rest)", selected: c.studyMinutes == p.study && c.breakMinutes == p.rest) {
                            store.config.studyMinutes = p.study
                            store.config.breakMinutes = p.rest
                        }
                    }
                }
                HStack {
                    Text("\(c.cycles) ciclo\(c.cycles == 1 ? "" : "s")").font(.callout)
                    Text("· \(total) min no total").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Stepper("Ciclos", value: $store.config.cycles, in: 1...10).labelsHidden()
                }
            }

            if !toClose.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.app")
                    Text("Vão fechar: " + toClose.joined(separator: ", "))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: start) {
                Label("Iniciar foco", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func start() {
        engine.start(intention: intention)
        intention = ""
    }

    // MARK: Em sessão

    private func active(_ s: ActiveSession) -> some View {
        VStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: engine.phaseProgress)
                VStack(spacing: 2) {
                    Text(s.isBreak ? "PAUSA" : "ESTUDO")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text(engine.remainingString)
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: 150, height: 150)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            if !s.intention.isEmpty {
                Text(s.intention)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            HStack(spacing: 5) {
                ForEach(1...s.totalCycles, id: \.self) { i in
                    let done = i < s.cycle || (i == s.cycle && s.isBreak)
                    Capsule()
                        .fill(Color.primary.opacity(done ? 1 : i == s.cycle ? 0.45 : 0.12))
                        .frame(width: 18, height: 4)
                }
            }

            Text(s.isBreak ? "Apps liberados até a pausa acabar."
                 : s.profileName.map { "Só apps e sites do perfil \($0)." } ?? "Só apps e sites permitidos estão abertos.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(engine.automationProblems, id: \.self) { name in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Sem permissão para filtrar sites no \(name). Libere em Ajustes do Sistema › Privacidade e Segurança › Automação.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .card(padding: 10)
            }

            Button("Cancelar foco…") {
                Windows.show("cancel", title: "Cancelar foco") {
                    CancelView(engine: engine, phrase: store.config.cancelPhrase)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

// MARK: - Cancelar (precisa digitar a frase)

struct CancelView: View {
    @ObservedObject var engine: FocusEngine
    let phrase: String
    @State private var typed = ""

    private var matches: Bool { Self.normalize(typed) == Self.normalize(phrase) }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "lock")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cancelar o foco?").font(.title3.weight(.semibold))
                    Text("Só se for realmente importante.").font(.callout).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Digite a frase")
                Text(phrase)
                    .font(.callout).italic()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 10)
                HStack(alignment: .top) {
                    TextField("Digite aqui…", text: $typed, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                    Image(systemName: matches ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(matches ? Color.primary : Color.primary.opacity(0.25))
                }
                .card(padding: 10)
            }

            HStack(spacing: 8) {
                Button("Cancelar foco") {
                    engine.cancel()
                    Windows.close("cancel")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!matches)

                Button("Voltar ao foco") { Windows.close("cancel") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .frame(width: 420)
    }
}

// MARK: - Pausa e fim de sessão

struct BreakView: View {
    @ObservedObject var engine: FocusEngine
    let tip: String

    var body: some View {
        VStack(spacing: 16) {
            LogoMark(size: 52)
            VStack(spacing: 6) {
                Text("Hora da pausa").font(.title2.weight(.semibold))
                Text(tip)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ZStack {
                ProgressRing(progress: engine.phaseProgress, lineWidth: 4)
                Text(engine.remainingString)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 120, height: 120)
            Button("Ok, vou fazer isso") { Windows.close("break") }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
        .frame(width: 380)
    }
}

struct EndView: View {
    @ObservedObject var store: Store
    let record: SessionRecord
    @State private var learned = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LogoMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessão concluída").font(.title3.weight(.semibold))
                    Text("\(record.studiedMinutes) min" + (record.intention.isEmpty ? "" : " · \(record.intention)"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("3 coisas que você aprendeu")
                Text("Sem olhar o material: é isso que fixa o conteúdo.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $learned)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(height: 120)
                    .card(padding: 8)
            }

            HStack(spacing: 8) {
                Button("Pular") { Windows.close("end") }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Salvar") {
                    store.setLearned(learned, for: record.id)
                    Windows.close("end")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(learned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .frame(width: 420)
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: FocusEngine
    @State var tab = Tab.general

    enum Tab: String, CaseIterable {
        case general = "Geral", apps = "Apps", sites = "Sites"
    }

    private var locked: Bool { engine.session != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LogoMark(size: 24)
                Text("Ajustes").font(.title3.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Chip(title: t.rawValue, selected: tab == t) { tab = t }
                    }
                }
                .frame(width: 240)
            }

            if locked {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("Travado durante a sessão de foco.")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 10)
            }

            Group {
                switch tab {
                case .general: GeneralTab(store: store)
                case .apps: AppsTab(store: store)
                case .sites: SitesTab(store: store)
                }
            }
            .disabled(locked)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: 560, height: 540)
    }
}

private struct StepperRow: View {
    let title: String
    let value: String
    @Binding var number: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
            Stepper(title, value: $number, in: range, step: step).labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

private struct GeneralTab: View {
    @ObservedObject var store: Store
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Sistema")
                    Button {
                        LoginItem.set(!openAtLogin)
                        openAtLogin = LoginItem.isEnabled
                    } label: {
                        HStack {
                            Text("Abrir ao ligar o Mac")
                            Spacer()
                            Image(systemName: openAtLogin ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(openAtLogin ? Color.primary : Color.primary.opacity(0.25))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!LoginItem.isInstalled)
                    .padding(.vertical, 2)
                    .card(padding: 12)
                    if !LoginItem.isInstalled {
                        Text("Disponível no app instalado em Aplicativos (./build.sh install).")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if LoginItem.needsApproval {
                        Text("Falta aprovar em Ajustes do Sistema › Geral › Itens de Início.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Tempo")
                    VStack(spacing: 0) {
                        StepperRow(title: "Estudo", value: "\(store.config.studyMinutes) min",
                                   number: $store.config.studyMinutes, range: 5...180, step: 5)
                        Divider()
                        StepperRow(title: "Pausa", value: "\(store.config.breakMinutes) min",
                                   number: $store.config.breakMinutes, range: 1...60)
                        Divider()
                        StepperRow(title: "Ciclos por sessão", value: "\(store.config.cycles)",
                                   number: $store.config.cycles, range: 1...10)
                        Divider()
                        HStack {
                            Text("Lembretes de postura e água")
                            Spacer()
                            Picker("Lembretes", selection: $store.config.reminderMinutes) {
                                Text("Desligado").tag(0)
                                ForEach([10, 15, 20, 30, 45], id: \.self) { Text("A cada \($0) min").tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        .padding(.vertical, 6)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .card(padding: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Frase para cancelar")
                    TextField("Frase", text: $store.config.cancelPhrase, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                        .card(padding: 10)
                    Text("Para encerrar uma sessão antes do fim, você vai precisar digitar exatamente esta frase.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Chips para escolher o perfil em uso (o mesmo no menu e nos Ajustes).
struct ProfileChips: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.config.profiles) { p in
                    Chip(title: p.name, selected: p.id == store.config.activeProfile.id) { store.selectProfile(p.id) }
                        .fixedSize()
                }
            }
        }
    }
}

/// Perfis nos Ajustes: escolher, criar (copiando o atual), renomear e apagar.
private struct ProfileBar: View {
    @ObservedObject var store: Store
    @State private var renaming = false
    @State private var deleting = false
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 10) {
            ProfileChips(store: store)
            Button {
                store.addProfile()
                newName = store.config.activeProfile.name
                renaming = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Novo perfil (cópia do atual)")
            Menu {
                Button("Renomear…") {
                    newName = store.config.activeProfile.name
                    renaming = true
                }
                Button("Apagar…", role: .destructive) { deleting = true }
                    .disabled(store.config.profiles.count < 2)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Mais opções do perfil")
        }
        .alert("Nome do perfil", isPresented: $renaming) {
            TextField("Ex.: Cálculo, Inglês, Programação", text: $newName)
            Button("Salvar") { store.renameActiveProfile(newName) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Apagar o perfil “\(store.config.activeProfile.name)”?", isPresented: $deleting) {
            Button("Apagar", role: .destructive) { store.deleteActiveProfile() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("As listas de apps e sites deste perfil serão perdidas.")
        }
    }
}

private struct AppsTab: View {
    @ObservedObject var store: Store
    @State private var apps: [InstalledApp] = []
    @State private var search = ""
    @State private var onlyAllowed = false

    private var filtered: [InstalledApp] {
        apps.filter { app in
            (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
                && (!onlyAllowed || store.config.allowedApps.contains(app.id))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileBar(store: store)
            Text("Durante o estudo com este perfil, só os apps marcados funcionam. O resto é fechado.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar app", text: $search).textFieldStyle(.plain)
                }
                .card(padding: 8)
                Chip(title: "Permitidos (\(apps.filter { store.config.allowedApps.contains($0.id) }.count))",
                     selected: onlyAllowed) { onlyAllowed.toggle() }
                    .fixedSize()
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { app in
                        AppRow(app: app, isOn: store.config.allowedApps.contains(app.id)) { toggle(app.id) }
                    }
                }
                .padding(4)
            }
            .card(padding: 0)
        }
        .onAppear { if apps.isEmpty { apps = AppCatalog.scan() } }
    }

    private func toggle(_ id: String) {
        if store.config.allowedApps.contains(id) {
            store.config.allowedApps.removeAll { $0 == id }
        } else {
            store.config.allowedApps.append(id)
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isOn: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 20, height: 20)
                Text(app.name)
                if BrowserFilter.scriptable.contains(app.id) {
                    Tag(text: "filtra sites")
                } else if BrowserFilter.unfiltered.contains(app.id) {
                    Tag(text: "sem filtro de sites")
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn ? Color.primary : Color.primary.opacity(0.25))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover ? 0.06 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct SitesTab: View {
    @ObservedObject var store: Store
    @State private var newSite = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileBar(store: store)
            Text("Nos navegadores permitidos, só os sites deste perfil (e subdomínios) abrem durante o estudo.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Adicionar site, ex: khanacademy.org", text: $newSite)
                    .textFieldStyle(.plain)
                    .onSubmit(add)
                    .card(padding: 8)
                Button(action: add) { Image(systemName: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 44)
                    .disabled(BrowserFilter.normalizeSite(newSite).isEmpty)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.config.allowedSites, id: \.self) { site in
                        HStack(spacing: 10) {
                            Image(systemName: "globe").foregroundStyle(.secondary)
                            Text(site)
                            Spacer()
                            Button {
                                store.config.allowedSites.removeAll { $0 == site }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Remover")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                    }
                }
                .padding(4)
            }
            .card(padding: 0)
        }
    }

    private func add() {
        let site = BrowserFilter.normalizeSite(newSite)
        if !site.isEmpty, !store.config.allowedSites.contains(site) { store.config.allowedSites.append(site) }
        newSite = ""
    }
}

// MARK: - Histórico

struct HistoryView: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: FocusEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LogoMark(size: 24)
                Text("Histórico").font(.title3.weight(.semibold))
            }

            HStack(spacing: 10) {
                stat("Hoje", "\(store.minutesToday + engine.liveMinutes)", "min")
                stat("Semana", "\(store.minutesThisWeek + engine.liveMinutes)", "min")
                stat("Sequência", "\(store.streakDays)", store.streakDays == 1 ? "dia" : "dias")
            }

            SectionLabel("Sessões")
            if store.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 28, weight: .light))
                    Text("Nenhuma sessão ainda.")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.history) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: r.completed ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundStyle(r.completed ? Color.primary : Color.secondary)
                                    Text(r.intention.isEmpty ? "Sem tema" : r.intention).fontWeight(.semibold)
                                    Spacer()
                                    Text("\(r.studiedMinutes) min").monospacedDigit().foregroundStyle(.secondary)
                                }
                                Text(r.start.formatted(date: .abbreviated, time: .shortened)
                                     + (r.profile.map { " · \($0)" } ?? "")
                                     + (r.completed ? "" : " · cancelada"))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !r.learned.isEmpty {
                                    Text(r.learned).font(.callout).padding(.top, 2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: 460, height: 540)
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

import ServiceManagement
import SwiftUI

/// Abrir o Sinapse ao ligar o Mac (Itens de Início do macOS).
enum LoginItem {
    static var isInstalled: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Sinapse: falha ao alterar item de início: \(error.localizedDescription)")
        }
        // 0 = desligado, 1 = ligado, 2 = falta aprovar, 3 = não encontrado
        UserDefaults.standard.set(SMAppService.mainApp.status.rawValue, forKey: "sinapse.loginItemStatus")
    }

    /// Na primeira vez que roda instalado em /Applications, já liga (dá pra desligar nos Ajustes).
    static func enableOnFirstRun() {
        let key = "sinapse.loginItemSetUp"
        guard isInstalled, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }
}

@main
struct SinapseApp: App {
    @StateObject private var store: Store
    @StateObject private var engine: FocusEngine

    init() {
        let store = Store()
        _store = StateObject(wrappedValue: store)
        let engine = FocusEngine(store: store)
        _engine = StateObject(wrappedValue: engine)
        Notifier.setup()
        LoginItem.enableOnFirstRun()
        Self.openPreviewIfRequested(store: store, engine: engine)
    }

    /// Para conferir o visual sem iniciar sessão: `open build/Sinapse.app --args --preview menu|sessao|ajustes|perfis|historico|pausa|cancelar|fim`
    private static func openPreviewIfRequested(store: Store, engine: FocusEngine) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--preview"), i + 1 < args.count else { return }
        let which = args[i + 1]
        store.useDemoHistory()
        engine.enableDemo()
        DispatchQueue.main.async {
            switch which {
            case "menu": Windows.show("p", title: "Menu") { MenuView(store: store, engine: engine) }
            case "sessao":
                engine.startDemo(intention: "Cálculo · cap. 3")
                Windows.show("p", title: "Sessão") { MenuView(store: store, engine: engine) }
            case "ajustes": Windows.show("p", title: "Ajustes") { SettingsView(store: store, engine: engine) }
            case "perfis": Windows.show("p", title: "Ajustes") { SettingsView(store: store, engine: engine, tab: .sites) }
            case "historico": Windows.show("p", title: "Histórico") { HistoryView(store: store, engine: engine) }
            case "pausa": Windows.show("p", title: "Pausa", dark: true) { BreakView(engine: engine, tip: Tips.breaks[0]) }
            case "cancelar": Windows.show("p", title: "Cancelar") { CancelView(engine: engine, phrase: store.config.cancelPhrase) }
            case "fim":
                let r = SessionRecord(start: Date(), end: Date(), intention: "Cálculo · cap. 3", studiedMinutes: 60, completed: true, learned: "")
                Windows.show("p", title: "Fim") { EndView(store: store, record: r) }
            default: break
            }
            if let j = args.firstIndex(of: "--snapshot"), j + 1 < args.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Windows.snapshot("p", to: args[j + 1]) }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store, engine: engine)
        } label: {
            if let s = engine.session {
                HStack(spacing: 4) {
                    Image(nsImage: Brand.menuIcon)
                    Text((s.isBreak ? "Pausa " : "") + engine.remainingString).monospacedDigit()
                }
            } else {
                Image(nsImage: Brand.menuIcon)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

import AppKit

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}

enum AppCatalog {
    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = [
            "/Applications", "/Applications/Utilities",
            "/System/Applications", "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        var found: [String: InstalledApp] = [:]
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
                guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
                found[id] = InstalledApp(id: id, name: String(item.dropLast(4)), url: url)
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Filtra as abas dos navegadores via AppleScript: qualquer aba fora da lista de sites vira about:blank.
@MainActor
enum BrowserFilter {
    static let scriptable: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]
    /// Navegadores sem suporte a AppleScript de abas: se permitidos, ficam sem filtro de sites.
    static let unfiltered: Set<String> = [
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "org.mozilla.firefox",
    ]

    enum Failure: Error { case notAuthorized, other }

    private static var cache: [String: NSAppleScript] = [:]

    /// Retorna os hosts bloqueados nesta passada.
    static func filter(bundleID: String, sites: [String]) -> Result<[String], Failure> {
        let key = bundleID + "|" + sites.joined(separator: ",")
        let script = cache[key] ?? {
            let s = NSAppleScript(source: source(bundleID: bundleID, sites: sites))!
            cache[key] = s
            return s
        }()
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            return .failure(code == -1743 ? .notAuthorized : .other)
        }
        let text = result.stringValue ?? ""
        return .success(text.split(separator: ",").map(String.init))
    }

    private static func source(bundleID: String, sites: [String]) -> String {
        let doms = sites.map { "\"" + $0.replacingOccurrences(of: "\"", with: "") + "\"" }.joined(separator: ", ")
        return """
        on hostOf(u)
            set oldTID to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "/"
            set h to text item 3 of u
            set AppleScript's text item delimiters to ":"
            set h to text item 1 of h
            set AppleScript's text item delimiters to oldTID
            return h
        end hostOf

        on isAllowed(u, doms)
            if not (u begins with "http://" or u begins with "https://") then return true
            set h to my hostOf(u)
            repeat with d in doms
                set d to d as text
                if h is d or h ends with ("." & d) then return true
            end repeat
            return false
        end isAllowed

        set doms to {\(doms)}
        set blocked to {}
        tell application id "\(bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to ""
                    try
                        set u to (URL of t) as text
                    end try
                    if not (my isAllowed(u, doms)) then
                        set end of blocked to my hostOf(u)
                        set URL of t to "about:blank"
                    end if
                end repeat
            end repeat
        end tell
        set AppleScript's text item delimiters to ","
        return blocked as text
        """
    }

    static func normalizeSite(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://", "www."] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        return s
    }
}

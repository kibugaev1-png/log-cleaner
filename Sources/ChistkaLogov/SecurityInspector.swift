import Foundation

// Одна найденная запись автозапуска.
struct SecurityItem: Identifiable, Hashable {
    let name: String        // имя файла
    let source: String      // где найдено (папка)
    let program: String     // что запускается
    let suspicion: String?  // причина подозрительности (nil = выглядит нормально)
    var id: String { source + "/" + name }
}

// Честная проверка: смотрит места автозапуска, где обычно закрепляются
// нежелательные программы, и помечает подозрительные по набору признаков.
// Это НЕ антивирус — базы вирусов нет; просто показывает, что стартует само,
// и подсвечивает необычное. Всё считается локально, без интернета.
struct SecurityInspector {
    let searchPaths: [URL]

    init(searchPaths: [URL]? = nil) {
        if let searchPaths {
            self.searchPaths = searchPaths
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.searchPaths = [
                home.appendingPathComponent("Library/LaunchAgents"),
                URL(fileURLWithPath: "/Library/LaunchAgents"),
                URL(fileURLWithPath: "/Library/LaunchDaemons")
            ]
        }
    }

    // Чистая логика подозрительности — легко тестируется.
    static func suspicionReason(program: String, exists: Bool) -> String? {
        if program == "—" || program.isEmpty { return nil }
        let lower = program.lowercased()

        if !exists { return "программа не найдена на диске" }

        let badDirs = ["/tmp/", "/private/tmp/", "/var/tmp/",
                       "/downloads/", "/desktop/", "/.trash/"]
        for d in badDirs where lower.contains(d) {
            return "необычное расположение (\(d.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))"
        }

        // Скрытая папка в пути: компонент, начинающийся с точки.
        let comps = program.split(separator: "/").map(String.init)
        if comps.contains(where: { $0.hasPrefix(".") }) {
            return "запуск из скрытой папки"
        }
        return nil
    }

    func inspect() -> [SecurityItem] {
        let fm = FileManager.default
        var items: [SecurityItem] = []
        for base in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "plist" {
                let program = programFromPlist(entry) ?? "—"
                let exists = program != "—" && fm.fileExists(atPath: program)
                let reason = SecurityInspector.suspicionReason(program: program, exists: exists)
                items.append(SecurityItem(
                    name: entry.lastPathComponent,
                    source: base.lastPathComponent,
                    program: program,
                    suspicion: reason
                ))
            }
        }
        // Подозрительные — наверх.
        return items.sorted {
            if ($0.suspicion != nil) != ($1.suspicion != nil) { return $0.suspicion != nil }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func programFromPlist(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        if let program = dict["Program"] as? String { return program }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first { return first }
        return nil
    }
}

import Foundation

// Сканирует каталоги логов и группирует файлы по приложениям.
// searchPaths можно подменить в тестах на временную папку.
struct LogScanner {
    let searchPaths: [URL]

    init(searchPaths: [URL]? = nil) {
        if let searchPaths {
            self.searchPaths = searchPaths
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.searchPaths = [
                home.appendingPathComponent("Library/Logs"),
                URL(fileURLWithPath: "/Library/Logs")
            ]
        }
    }

    func scan() -> [AppLogs] {
        var byApp: [String: [LogFile]] = [:]
        let fm = FileManager.default

        for base in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
                    // Папка приложения: имя папки = имя приложения, файлы берём рекурсивно.
                    let appName = displayName(for: entry.lastPathComponent)
                    let files = filesRecursively(in: entry)
                    if !files.isEmpty {
                        byApp[appName, default: []].append(contentsOf: files)
                    }
                } else {
                    // Одиночный файл лога — группируем по приложению из имени.
                    if let file = logFile(at: entry) {
                        let appName = appNameFromFilename(entry.lastPathComponent)
                        byApp[appName, default: []].append(file)
                    }
                }
            }
        }

        return byApp
            .map { AppLogs(name: $0.key, files: $0.value.sorted { $0.modified > $1.modified }) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - помощники

    private func filesRecursively(in dir: URL) -> [LogFile] {
        let fm = FileManager.default
        var result: [LogFile] = []
        guard let en = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let url as URL in en {
            if let f = logFile(at: url) { result.append(f) }
        }
        return result
    }

    private func logFile(at url: URL) -> LogFile? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let v = try? url.resourceValues(forKeys: keys),
              v.isRegularFile == true else { return nil }
        let size = Int64(v.fileSize ?? 0)
        let modified = v.contentModificationDate ?? .distantPast
        return LogFile(url: url, size: size, modified: modified)
    }

    // "AppName-2024-01-01-...ips" -> "AppName". Иначе — как есть без расширения.
    private func appNameFromFilename(_ filename: String) -> String {
        for sep in ["-", "_", "."] {
            if let idx = filename.firstIndex(of: Character(sep)) {
                let prefix = String(filename[..<idx])
                if prefix.count >= 2 { return displayName(for: prefix) }
            }
        }
        return displayName(for: (filename as NSString).deletingPathExtension)
    }

    // Немного причёсываем имя папки к читаемому виду.
    private func displayName(for raw: String) -> String {
        if raw == "DiagnosticReports" { return "Отчёты о сбоях" }
        return raw
    }
}

import Foundation

// Ищет ВСЕ следы приложений (не только логи): логи, кеш, настройки,
// данные, cookies, веб-данные, состояние окон — и группирует по приложению.
struct TraceScanner {
    let searchPaths: [URL]

    init(searchPaths: [URL]? = nil) {
        if let searchPaths {
            self.searchPaths = searchPaths
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            func h(_ p: String) -> URL { home.appendingPathComponent(p) }
            self.searchPaths = [
                h("Library/Logs"),
                h("Library/Caches"),
                h("Library/Preferences"),
                h("Library/Application Support"),
                h("Library/Saved Application State"),
                h("Library/WebKit"),
                h("Library/HTTPStorages"),
                h("Library/Containers"),
                URL(fileURLWithPath: "/Library/Logs")
            ]
        }
    }

    func scan() -> [AppLogs] {
        var byApp: [String: [LogFile]] = [:]
        let fm = FileManager.default

        for base in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                let key = TraceScanner.mainToken(entry.lastPathComponent)
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let files = isDir ? filesRecursively(in: entry) : [logFile(at: entry)].compactMap { $0 }
                if !files.isEmpty { byApp[key, default: []].append(contentsOf: files) }
            }
        }

        return byApp
            .map { AppLogs(name: TraceScanner.displayName($0.key), files: $0.value.sorted { $0.modified > $1.modified }) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - разбор имени в «ключ приложения»

    // "com.roblox.RobloxPlayer.plist" -> "roblox", "Roblox" -> "roblox", "zoom.us" -> "zoom"
    static func mainToken(_ raw: String) -> String {
        let noExt = (raw as NSString).deletingPathExtension
        let tokens = tokenize(noExt).map { $0.lowercased() }.filter { !$0.isEmpty }
        let stop: Set<String> = ["com","org","io","net","us","ru","co","dev","app","apps","inc",
                                 "player","helper","menubar","channel","agent","service","xos",
                                 "group","shared","the","llc","gmbh"]
        let meaningful = tokens.filter { !stop.contains($0) && $0.count >= 2 }
        if let pick = meaningful.max(by: { $0.count < $1.count }) { return pick }
        return tokens.first ?? noExt.lowercased()
    }

    // Разбивает по разделителям И по camelCase: "RobloxPlayer" -> ["Roblox","Player"]
    static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var prevLower = false
        for ch in s {
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase && prevLower && !current.isEmpty {
                    tokens.append(current); current = ""
                }
                current.append(ch)
                prevLower = ch.isLowercase
            } else {
                if !current.isEmpty { tokens.append(current); current = "" }
                prevLower = false
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func displayName(_ token: String) -> String {
        guard let first = token.first else { return token }
        return first.uppercased() + token.dropFirst()
    }

    // MARK: - сбор файлов

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
        guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { return nil }
        return LogFile(url: url, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate ?? .distantPast)
    }
}

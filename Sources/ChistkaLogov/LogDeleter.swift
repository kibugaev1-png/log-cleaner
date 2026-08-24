import Foundation

// Отчёт об удалении.
struct DeleteReport {
    var deletedCount: Int = 0
    var freedBytes: Int64 = 0
    var errors: [String] = []
}

// Удаляет файлы следов БЕЗВОЗВРАТНО (не в Корзину) и подчищает пустые папки.
struct LogDeleter {
    let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    // roots — базовые папки (Logs, Caches, …), выше которых чистить нельзя.
    func delete(_ files: [LogFile], pruneUnder roots: [URL] = []) -> DeleteReport {
        var report = DeleteReport()
        var touchedDirs = Set<URL>()
        for file in files {
            do {
                try fileManager.removeItem(at: file.url)
                report.deletedCount += 1
                report.freedBytes += file.size
                touchedDirs.insert(file.url.deletingLastPathComponent())
            } catch {
                report.errors.append("\(file.name): \(error.localizedDescription)")
            }
        }
        for dir in touchedDirs { pruneEmptyParents(of: dir, roots: roots) }
        return report
    }

    func delete(app: AppLogs, period: TimePeriod, now: Date = Date(), pruneUnder roots: [URL] = []) -> DeleteReport {
        delete(app.files(in: period, now: now), pruneUnder: roots)
    }

    // Удаляет пустые папки вверх по дереву, пока они строго внутри одного из roots.
    private func pruneEmptyParents(of dir: URL, roots: [URL]) {
        let rootPaths = roots.map { $0.standardizedFileURL.path }
        var cur = dir.standardizedFileURL
        while rootPaths.contains(where: { cur.path.hasPrefix($0 + "/") }) {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: cur.path),
                  contents.isEmpty else { break }
            try? fileManager.removeItem(at: cur)
            cur = cur.deletingLastPathComponent()
        }
    }
}

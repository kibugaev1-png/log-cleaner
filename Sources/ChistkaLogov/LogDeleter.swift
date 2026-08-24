import Foundation

// Отчёт об удалении.
struct DeleteReport {
    var deletedCount: Int = 0
    var freedBytes: Int64 = 0
    var errors: [String] = []
}

// Удаляет файлы логов БЕЗВОЗВРАТНО (не в Корзину).
struct LogDeleter {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func delete(_ files: [LogFile]) -> DeleteReport {
        var report = DeleteReport()
        for file in files {
            do {
                try fileManager.removeItem(at: file.url)
                report.deletedCount += 1
                report.freedBytes += file.size
            } catch {
                report.errors.append("\(file.name): \(error.localizedDescription)")
            }
        }
        return report
    }

    // Удобная обёртка: удалить логи приложения за период.
    func delete(app: AppLogs, period: TimePeriod, now: Date = Date()) -> DeleteReport {
        delete(app.files(in: period, now: now))
    }
}

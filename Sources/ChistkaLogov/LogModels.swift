import Foundation

// Период удаления.
enum TimePeriod: CaseIterable, Identifiable {
    case all, day, week, month
    var id: Self { self }

    var title: String {
        switch self {
        case .all:   return "Удалить всё"
        case .day:   return "Удалить за последний день"
        case .week:  return "Удалить за последнюю неделю"
        case .month: return "Удалить за последний месяц"
        }
    }

    // Файлы новее этой даты попадают под удаление. nil = без ограничения (всё).
    func cutoffDate(now: Date = Date()) -> Date? {
        switch self {
        case .all:   return nil
        case .day:   return now.addingTimeInterval(-24 * 3600)
        case .week:  return now.addingTimeInterval(-7 * 24 * 3600)
        case .month: return now.addingTimeInterval(-30 * 24 * 3600)
        }
    }
}

// Один файл лога.
struct LogFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

// Логи одного приложения.
struct AppLogs: Identifiable, Hashable {
    let name: String
    let files: [LogFile]
    var id: String { name }

    var count: Int { files.count }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    // Файлы, попадающие под выбранный период.
    func files(in period: TimePeriod, now: Date = Date()) -> [LogFile] {
        guard let cutoff = period.cutoffDate(now: now) else { return files }
        return files.filter { $0.modified >= cutoff }
    }
}

// Человекочитаемый размер.
func formatBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB]
    return f.string(fromByteCount: bytes)
}

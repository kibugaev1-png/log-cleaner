import Foundation
import AppKit

// Проверяет, есть ли доступ к папкам логов (косвенно — к «Полному доступу к диску»),
// и умеет открыть нужный раздел системных настроек.
struct PermissionChecker {
    // Пробуем прочитать защищённую папку. Если система не пускает — доступа нет.
    static func hasLogAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probe = home.appendingPathComponent("Library/Logs/DiagnosticReports")
        // Если папки нет вовсе — считаем, что доступ есть (просто пусто).
        if !FileManager.default.fileExists(atPath: probe.path) { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

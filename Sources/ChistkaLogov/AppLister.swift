import Foundation

// Находит установленные приложения (папки .app), чтобы показывать в списке
// даже те, у которых логов нет.
struct AppLister {
    let searchPaths: [URL]

    init(searchPaths: [URL]? = nil) {
        if let searchPaths {
            self.searchPaths = searchPaths
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.searchPaths = [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                home.appendingPathComponent("Applications")
            ]
        }
    }

    // Возвращает имена приложений (без ".app").
    func installedAppNames() -> [String] {
        let fm = FileManager.default
        var names = Set<String>()
        for base in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                names.insert((entry.lastPathComponent as NSString).deletingPathExtension)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

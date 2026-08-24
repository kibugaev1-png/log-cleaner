import Foundation

// Автотест на «песочнице»: проверяет LogScanner и LogDeleter на временной папке
// с фейковыми логами. Запуск: см. run_tests.sh. Не трогает реальные логи.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✅ \(msg)") }
    else { print("  ❌ \(msg)"); failures += 1 }
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("chistka_test_\(UUID().uuidString)")

func makeFile(_ path: String, bytes: Int, ageDays: Double) {
    let url = root.appendingPathComponent(path)
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = Data(repeating: 0x41, count: bytes)
    try? data.write(to: url)
    let date = Date().addingTimeInterval(-ageDays * 24 * 3600)
    try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

// Готовим песочницу.
makeFile("AppA/today.log",     bytes: 100, ageDays: 0.1)   // свежий
makeFile("AppA/threeDays.log", bytes: 200, ageDays: 3)     // на этой неделе
makeFile("AppA/old.log",       bytes: 300, ageDays: 40)    // старше месяца
makeFile("AppB/only.log",      bytes: 50,  ageDays: 10)    // 10 дней
makeFile("MyApp-2024-01-01-crash.ips", bytes: 500, ageDays: 2) // одиночный файл-сбой

print("Песочница: \(root.path)\n")

// --- Сканирование ---
let scanner = LogScanner(searchPaths: [root])
let apps = scanner.scan()
print("Найдено приложений: \(apps.map { $0.name }.sorted())")

check(apps.contains { $0.name == "AppA" }, "AppA найдено")
check(apps.contains { $0.name == "AppB" }, "AppB найдено")
check(apps.contains { $0.name == "MyApp" }, "MyApp (из имени одиночного файла) найдено")

let appA = apps.first { $0.name == "AppA" }!
check(appA.count == 3, "AppA: 3 файла (получено \(appA.count))")
check(appA.totalSize == 600, "AppA: суммарно 600 байт (получено \(appA.totalSize))")

// --- Фильтр по периоду ---
check(appA.files(in: .day).count == 1,   "AppA за день: 1 файл (получено \(appA.files(in: .day).count))")
check(appA.files(in: .week).count == 2,  "AppA за неделю: 2 файла (получено \(appA.files(in: .week).count))")
check(appA.files(in: .month).count == 2, "AppA за месяц: 2 файла (получено \(appA.files(in: .month).count))")
check(appA.files(in: .all).count == 3,   "AppA всё: 3 файла (получено \(appA.files(in: .all).count))")

// --- Удаление за неделю: должно снести 2 свежих, оставить старый ---
let deleter = LogDeleter()
let report = deleter.delete(app: appA, period: .week)
check(report.deletedCount == 2, "Удалено 2 файла за неделю (получено \(report.deletedCount))")
check(report.freedBytes == 300, "Освобождено 300 байт (получено \(report.freedBytes))")
check(report.errors.isEmpty, "Ошибок нет")

check(fm.fileExists(atPath: root.appendingPathComponent("AppA/old.log").path),
      "Старый файл (40 дней) НЕ тронут")
check(!fm.fileExists(atPath: root.appendingPathComponent("AppA/today.log").path),
      "Свежий файл удалён")
check(!fm.fileExists(atPath: root.appendingPathComponent("AppA/threeDays.log").path),
      "Файл 3-дневной давности удалён")
check(fm.fileExists(atPath: root.appendingPathComponent("AppB/only.log").path),
      "Файлы другого приложения (AppB) НЕ тронуты")

// --- Удаление «всё» у AppB ---
let appB = scanner.scan().first { $0.name == "AppB" }!
let r2 = deleter.delete(app: appB, period: .all)
check(r2.deletedCount == 1, "AppB: удалён 1 файл при 'Удалить всё'")
check(!fm.fileExists(atPath: root.appendingPathComponent("AppB/only.log").path), "AppB очищен")

// Убираем песочницу.
try? fm.removeItem(at: root)

print("\n" + (failures == 0 ? "ВСЕ ТЕСТЫ ПРОШЛИ ✅" : "ПРОВАЛЕНО ТЕСТОВ: \(failures) ❌"))
exit(failures == 0 ? 0 : 1)

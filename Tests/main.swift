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

// --- SpeedTester: расчёт Мбит/с ---
print("\n[Скорость]")
check(SpeedTester.megabitsPerSecond(bytes: 12_500_000, seconds: 1) == 100,
      "12.5 МБ за 1 c = 100 Мбит/с (получено \(SpeedTester.megabitsPerSecond(bytes: 12_500_000, seconds: 1)))")
check(SpeedTester.megabitsPerSecond(bytes: 1_000_000, seconds: 0) == 0,
      "Деление на ноль времени = 0 (без краха)")
check(SpeedTester.megabitsPerSecond(bytes: 1_000_000, seconds: 8) == 1.0,
      "1 МБ за 8 c = 1 Мбит/с (получено \(SpeedTester.megabitsPerSecond(bytes: 1_000_000, seconds: 8)))")

// --- IPService: локальные адреса ---
print("\n[IP]")
let locals = IPService.localIPv4Addresses()
check(!locals.contains("127.0.0.1"), "Локальный список не содержит loopback 127.0.0.1")
print("  (для справки локальные адреса: \(locals))")

// --- Логика подозрительности ---
print("\n[Подозрительность]")
check(SecurityInspector.suspicionReason(program: "/usr/bin/normalapp", exists: true) == nil,
      "Обычная программа в /usr/bin — не подозрительна")
check(SecurityInspector.suspicionReason(program: "/tmp/hack", exists: true) != nil,
      "Запуск из /tmp — подозрительно")
check(SecurityInspector.suspicionReason(program: "/Users/x/Downloads/x", exists: true) != nil,
      "Запуск из Загрузок — подозрительно")
check(SecurityInspector.suspicionReason(program: "/Users/x/.hidden/x", exists: true) != nil,
      "Запуск из скрытой папки — подозрительно")
check(SecurityInspector.suspicionReason(program: "/opt/app", exists: false) != nil,
      "Программа отсутствует на диске — подозрительно")

// --- SecurityInspector: чтение автозапуска из песочницы ---
print("\n[Проверка автозапуска]")
let secRoot = fm.temporaryDirectory.appendingPathComponent("sec_test_\(UUID().uuidString)")
try? fm.createDirectory(at: secRoot, withIntermediateDirectories: true)
let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.test.agent</string>
<key>ProgramArguments</key><array><string>/tmp/подозрительное</string></array>
</dict></plist>
"""
try? plist.write(to: secRoot.appendingPathComponent("com.test.agent.plist"), atomically: true, encoding: .utf8)
let inspector = SecurityInspector(searchPaths: [secRoot])
let secItems = inspector.inspect()
check(secItems.count == 1, "Найдена 1 запись автозапуска (получено \(secItems.count))")
check(secItems.first?.program == "/tmp/подозрительное", "Программа автозапуска прочитана верно")
check(secItems.first?.suspicion != nil, "Запись из /tmp помечена подозрительной")
try? fm.removeItem(at: secRoot)

// Убираем песочницу.
try? fm.removeItem(at: root)

print("\n" + (failures == 0 ? "ВСЕ ТЕСТЫ ПРОШЛИ ✅" : "ПРОВАЛЕНО ТЕСТОВ: \(failures) ❌"))
exit(failures == 0 ? 0 : 1)

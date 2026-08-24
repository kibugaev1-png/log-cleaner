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

// Готовим песочницу: следы Roblox разбросаны по «Логам» и «Кешу» (разные папки,
// разные имена — com.roblox.RobloxPlayer и Roblox), плюс отдельный Telegram.
makeFile("Logs/Roblox/today.log",                       bytes: 100, ageDays: 0.1) // свежий
makeFile("Caches/com.roblox.RobloxPlayer/three.dat",    bytes: 200, ageDays: 3)   // на неделе
makeFile("Caches/com.roblox.RobloxPlayer/old.dat",      bytes: 300, ageDays: 40)  // старше месяца
makeFile("Logs/Telegram/only.log",                      bytes: 50,  ageDays: 10)

print("Песочница: \(root.path)\n")

let logsDir = root.appendingPathComponent("Logs")
let cachesDir = root.appendingPathComponent("Caches")

// --- Разбор имён в ключ приложения ---
print("[Имена приложений]")
check(TraceScanner.mainToken("Roblox") == "roblox", "Roblox -> roblox")
check(TraceScanner.mainToken("com.roblox.RobloxPlayer") == "roblox", "com.roblox.RobloxPlayer -> roblox")
check(TraceScanner.mainToken("com.roblox.RobloxPlayer.plist") == "roblox", "...RobloxPlayer.plist -> roblox")
check(TraceScanner.mainToken("zoom.us") == "zoom", "zoom.us -> zoom")

// --- Сканирование: следы Roblox из РАЗНЫХ папок объединяются ---
print("\n[Сканирование следов]")
let scanner = TraceScanner(searchPaths: [logsDir, cachesDir])
let apps = scanner.scan()
print("Найдено приложений: \(apps.map { $0.name }.sorted())")
check(apps.contains { $0.name == "Roblox" }, "Roblox найден")
check(apps.contains { $0.name == "Telegram" }, "Telegram найден")

let roblox = apps.first { $0.name == "Roblox" }!
check(roblox.count == 3, "Roblox: 3 файла из Логов+Кеша (получено \(roblox.count))")
check(roblox.totalSize == 600, "Roblox: суммарно 600 байт (получено \(roblox.totalSize))")

// --- Фильтр по периоду ---
check(roblox.files(in: .day).count == 1,   "Roblox за день: 1 (получено \(roblox.files(in: .day).count))")
check(roblox.files(in: .week).count == 2,  "Roblox за неделю: 2 (получено \(roblox.files(in: .week).count))")
check(roblox.files(in: .month).count == 2, "Roblox за месяц: 2 (получено \(roblox.files(in: .month).count))")
check(roblox.files(in: .all).count == 3,   "Roblox всё: 3 (получено \(roblox.files(in: .all).count))")

// --- Удаление за неделю: снести 2 свежих, оставить старый ---
print("\n[Удаление]")
let deleter = LogDeleter()
let report = deleter.delete(app: roblox, period: .week, pruneUnder: [logsDir, cachesDir])
check(report.deletedCount == 2, "Удалено 2 файла за неделю (получено \(report.deletedCount))")
check(report.freedBytes == 300, "Освобождено 300 байт (получено \(report.freedBytes))")
check(fm.fileExists(atPath: cachesDir.appendingPathComponent("com.roblox.RobloxPlayer/old.dat").path),
      "Старый файл (40 дней) НЕ тронут")
check(!fm.fileExists(atPath: logsDir.appendingPathComponent("Roblox/today.log").path), "Свежий удалён")
check(fm.fileExists(atPath: logsDir.appendingPathComponent("Telegram/only.log").path),
      "Файлы другого приложения (Telegram) НЕ тронуты")

// --- Удаление «всё» у Telegram + чистка пустых папок ---
let telegram = scanner.scan().first { $0.name == "Telegram" }!
let r2 = deleter.delete(app: telegram, period: .all, pruneUnder: [logsDir, cachesDir])
check(r2.deletedCount == 1, "Telegram: удалён 1 файл при 'Удалить всё'")
check(!fm.fileExists(atPath: logsDir.appendingPathComponent("Telegram").path),
      "Пустая папка Telegram удалена (следов не осталось)")
check(fm.fileExists(atPath: logsDir.path), "Базовая папка Logs НЕ удалена")

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

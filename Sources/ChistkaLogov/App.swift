import SwiftUI

// Состояние всего приложения.
// Сводка для дашборда.
struct DashboardStats {
    var totalBytes: Int64 = 0
    var appCount: Int = 0
    var suspiciousCount: Int = 0
    var topApps: [AppLogs] = []      // самые «тяжёлые» — для графика
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase { case consent, menu, logs, ip, security, speed }

    @Published var phase: Phase = .consent
    @Published var apps: [AppLogs] = []
    @Published var hiddenApps: Set<String> = []
    @Published var isScanning = false
    @Published var authError: String?
    @Published var showAll = false

    @Published var stats: DashboardStats?
    @Published var loadingStats = false
    @Published var freedTotal: Int64 = 0     // сколько всего освобождено за сессию

    private let auth = AuthService()
    private let scanner = TraceScanner()
    private let lister = AppLister()
    let deleter = LogDeleter()

    var visibleApps: [AppLogs] {
        apps.filter { !hiddenApps.contains($0.name) }.filter { showAll || $0.count > 0 }
    }
    var hasAccess: Bool { PermissionChecker.hasLogAccess() }

    func confirmOwner() {
        authError = nil
        auth.authenticate { [weak self] ok, err in
            guard let self else { return }
            if ok { self.phase = .menu; self.loadDashboard() } else { self.authError = err }
        }
    }

    // Считает сводку для дашборда в фоне.
    func loadDashboard() {
        loadingStats = true
        let scanner = self.scanner
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = scanner.scan()
            let withTraces = apps.filter { $0.count > 0 }
            let total = withTraces.reduce(Int64(0)) { $0 + $1.totalSize }
            let suspicious = SecurityInspector().inspect().filter { $0.suspicion != nil }.count
            let top = Array(withTraces.prefix(6))
            let s = DashboardStats(totalBytes: total, appCount: withTraces.count,
                                   suspiciousCount: suspicious, topApps: top)
            DispatchQueue.main.async {
                self.apps = apps
                self.stats = s
                self.loadingStats = false
            }
        }
    }

    func openLogs() {
        phase = .logs
        rescan()
    }

    func rescan() {
        isScanning = true
        let scanner = self.scanner
        let lister = self.lister
        DispatchQueue.global(qos: .userInitiated).async {
            let logApps = scanner.scan()
            let installed = lister.installedAppNames()
            let logNames = Set(logApps.map { $0.name.lowercased() })
            let extra = installed
                .filter { !logNames.contains($0.lowercased()) }
                .map { AppLogs(name: $0, files: []) }
            let combined = logApps + extra.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            DispatchQueue.main.async {
                self.apps = combined
                self.isScanning = false
            }
        }
    }

    func hide(_ app: AppLogs) { hiddenApps.insert(app.name) }
}

// MARK: - Корень

@main
struct ChistkaLogovApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 680, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            switch model.phase {
            case .consent:  ConsentView()
            case .menu:     DashboardView()
            case .logs:     AppListView()
            case .ip:       IPView()
            case .security: SecurityView()
            case .speed:    SpeedView()
            }
        }
        .foregroundColor(.black)          // весь текст чёрный
        .tint(.black)
    }
}

// Кнопка «Назад» в меню.
struct BackButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button(action: { model.phase = .menu }) {
            Label("Назад", systemImage: "chevron.left").foregroundColor(.black)
        }
    }
}

// MARK: - Экран 1: согласие

struct ConsentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 64)).foregroundColor(.black)
            Text("Это ваш компьютер?").font(.system(size: 30, weight: .bold))
            Text("Приложите палец (Touch ID) или введите пароль,\nчтобы подтвердить, что вы хозяин этого Mac.")
                .multilineTextAlignment(.center).foregroundColor(.black.opacity(0.6))
                .frame(maxWidth: 440)
            Button(action: { model.confirmOwner() }) {
                Text("Да, это мой компьютер")
                    .font(.headline).foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
            if let err = model.authError {
                Text(err).foregroundColor(.red).font(.callout)
            }
            Spacer()
        }.padding(40)
    }
}

// MARK: - Дашборд

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Image(systemName: "sparkles").font(.title).foregroundColor(.blue)
                    Text("Чистка логов").font(.system(size: 30, weight: .bold)).foregroundColor(.black)
                    Spacer()
                    Button(action: { model.loadDashboard() }) {
                        Label("Обновить", systemImage: "arrow.clockwise").foregroundColor(.black)
                    }
                }
                .padding(.top, 24)

                // Карточки статистики
                if let s = model.stats {
                    HStack(spacing: 14) {
                        StatCard(title: "Следов найдено", value: formatBytes(s.totalBytes),
                                 icon: "internaldrive", color: Color(red: 0.1, green: 0.4, blue: 0.8))
                        StatCard(title: "Приложений", value: "\(s.appCount)",
                                 icon: "app.badge", color: Color(red: 0.1, green: 0.5, blue: 0.2))
                        StatCard(title: "Подозрительных", value: "\(s.suspiciousCount)",
                                 icon: "exclamationmark.shield",
                                 color: s.suspiciousCount > 0 ? Color(red: 0.8, green: 0.1, blue: 0.1)
                                                              : Color(red: 0.1, green: 0.5, blue: 0.2))
                    }

                    if model.freedTotal > 0 { freedBanner }

                    // Мини-график «кто занимает больше всего места»
                    if !s.topApps.isEmpty { SpaceChart(apps: s.topApps) }
                } else if model.loadingStats {
                    ProgressView("Анализирую компьютер…").padding(.vertical, 30)
                }

                // Действия
                VStack(spacing: 12) {
                    menuButton("Очистить следы и логи", "trash", Color(red: 0.1, green: 0.5, blue: 0.2), light: false) { model.openLogs() }
                    HStack(spacing: 12) {
                        smallButton("Мой IP", "network") { model.phase = .ip }
                        smallButton("Проверка", "magnifyingglass") { model.phase = .security }
                        smallButton("Скорость", "speedometer") { model.phase = .speed }
                    }
                }
                Spacer(minLength: 10)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if model.stats == nil && !model.loadingStats { model.loadDashboard() } }
    }

    var freedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.title).foregroundColor(.green)
            VStack(alignment: .leading) {
                Text("Освобождено за сессию").font(.caption).foregroundColor(.black.opacity(0.6))
                CountUpBytes(target: model.freedTotal)
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.green)
            }
            Spacer()
        }
        .padding().background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func menuButton(_ title: String, _ icon: String, _ bg: Color, light: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundColor(light ? .black : .white).frame(width: 28)
                Text(title).font(.headline).foregroundColor(light ? .black : .white)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor((light ? Color.black : .white).opacity(0.5))
            }
            .padding(.horizontal, 18).padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    func smallButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundColor(.black)
                Text(title).font(.subheadline.weight(.medium)).foregroundColor(.black)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color(white: 0.94))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}

// Карточка одной цифры.
struct StatCard: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(value).font(.system(size: 26, weight: .bold)).foregroundColor(color).lineLimit(1)
            Text(title).font(.caption).foregroundColor(.black.opacity(0.6))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// Горизонтальный мини-график «кто занимает место».
struct SpaceChart: View {
    let apps: [AppLogs]
    var maxBytes: Int64 { max(1, apps.map { $0.totalSize }.max() ?? 1) }
    let palette: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.85), Color(red: 0.85, green: 0.45, blue: 0.15),
        Color(red: 0.20, green: 0.60, blue: 0.35), Color(red: 0.60, green: 0.30, blue: 0.70),
        Color(red: 0.85, green: 0.30, blue: 0.45), Color(red: 0.30, green: 0.60, blue: 0.70)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Кто занимает больше всего места").font(.headline).foregroundColor(.black)
            ForEach(Array(apps.enumerated()), id: \.element.id) { i, app in
                HStack(spacing: 10) {
                    Text(app.name).font(.caption).foregroundColor(.black)
                        .frame(width: 90, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.92))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(palette[i % palette.count])
                                .frame(width: max(6, geo.size.width * barFraction(app)))
                        }
                    }.frame(height: 22)
                    Text(formatBytes(app.totalSize)).font(.caption2).foregroundColor(.black.opacity(0.7))
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(Color(white: 0.97)).clipShape(RoundedRectangle(cornerRadius: 14))
    }
    func barFraction(_ app: AppLogs) -> CGFloat {
        CGFloat(Double(app.totalSize) / Double(maxBytes))
    }
}

// Анимированный счётчик байтов (счёт вверх).
struct CountUpBytes: View {
    let target: Int64
    @State private var shown: Int64 = 0
    var body: some View {
        Text(formatBytes(shown))
            .onAppear { run() }
            .onChange(of: target) { _ in run() }
    }
    func run() {
        shown = 0
        guard target > 0 else { return }
        let steps: Int64 = 25
        let inc = max(1, target / steps)
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            shown += inc
            if shown >= target { shown = target; t.invalidate() }
        }
    }
}

// MARK: - Экран: удаление логов

struct AppListView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: AppLogs?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BackButton()
                Text("Очистка следов").font(.system(size: 22, weight: .bold))
                Spacer()
                Toggle("Все приложения", isOn: $model.showAll).toggleStyle(.switch)
                Button(action: { model.rescan() }) {
                    Label("Обновить", systemImage: "arrow.clockwise").foregroundColor(.black)
                }
            }.padding()

            if !model.hasAccess { accessBanner }

            if model.isScanning {
                Spacer(); ProgressView("Ищу логи…").frame(maxWidth: .infinity); Spacer()
            } else if model.visibleApps.isEmpty {
                Spacer(); Text("Логи не найдены.").foregroundColor(.black.opacity(0.5))
                    .frame(maxWidth: .infinity); Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.visibleApps) { app in
                            AppRow(app: app, onYes: { selected = app }, onNo: { model.hide(app) })
                        }
                    }.padding()
                }
            }
        }
        .sheet(item: $selected) { app in AppDetailView(app: app).environmentObject(model) }
    }

    var accessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Нужен полный доступ к диску").font(.headline).foregroundColor(.black)
                Text("Чтобы видеть логи всех приложений, разрешите доступ в настройках.")
                    .font(.caption).foregroundColor(.black.opacity(0.6))
            }
            Spacer()
            Button("Открыть настройки") { PermissionChecker.openFullDiskAccessSettings() }
                .foregroundColor(.black)
        }
        .padding().background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10)).padding(.horizontal)
    }
}

struct AppRow: View {
    let app: AppLogs
    let onYes: () -> Void
    let onNo: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").foregroundColor(.black.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline).foregroundColor(.black)
                Text(app.count > 0 ? "\(app.count) файлов · \(formatBytes(app.totalSize))" : "нет логов")
                    .font(.caption).foregroundColor(.black.opacity(0.6))
            }
            Spacer()
            Button(action: onYes) { pill("Да", app.count > 0 ? .green : Color(white: 0.85)) }
                .buttonStyle(.plain).disabled(app.count == 0)
            Button(action: onNo) { pill("Нет", Color(red: 1, green: 0.5, blue: 0.5)) }.buttonStyle(.plain)
        }
        .padding(12).background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundColor(.black)
            .frame(width: 56, height: 32).background(color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AppDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let app: AppLogs
    @State private var current: AppLogs
    @State private var pending: TimePeriod?
    @State private var lastReport: DeleteReport?
    init(app: AppLogs) { self.app = app; _current = State(initialValue: app) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(current.name).font(.system(size: 22, weight: .bold)).foregroundColor(.black)
                Spacer()
                Button("Закрыть") { dismiss() }.foregroundColor(.black)
            }
            Text("\(current.count) файлов · \(formatBytes(current.totalSize))").foregroundColor(.black.opacity(0.6))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(current.files) { f in
                        HStack {
                            Text(f.name).lineLimit(1).foregroundColor(.black)
                            Spacer()
                            Text(formatBytes(f.size)).foregroundColor(.black.opacity(0.5)).font(.caption)
                            Text(dateStr(f.modified)).foregroundColor(.black.opacity(0.5)).font(.caption)
                        }
                        Divider()
                    }
                }
            }.frame(maxHeight: 200)
            Text("Что удалить:").font(.headline).foregroundColor(.black)
            VStack(spacing: 8) {
                ForEach(TimePeriod.allCases) { period in
                    let n = current.files(in: period).count
                    Button(action: { pending = period }) {
                        HStack {
                            Text(period.title).foregroundColor(.black)
                            Spacer()
                            Text("\(n) файлов").foregroundColor(.black.opacity(0.6)).font(.caption)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity)
                        .background(n == 0 ? Color(white: 0.9) : Color(red: 1, green: 0.6, blue: 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(n == 0)
                }
            }
            if let r = lastReport {
                Text("Удалено \(r.deletedCount) файлов, освобождено \(formatBytes(r.freedBytes))." +
                     (r.errors.isEmpty ? "" : " Ошибок: \(r.errors.count).")).foregroundColor(.green).font(.callout)
            }
        }
        .padding(24).frame(width: 520).foregroundColor(.black).background(Color.white)
        .confirmationDialog(confirmText,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible) {
            Button("Да, стереть насовсем", role: .destructive) { performDelete() }
            Button("Отмена", role: .cancel) { pending = nil }
        } message: { Text("Файлы будут удалены безвозвратно, восстановить их нельзя.") }
    }
    var confirmText: String {
        guard let p = pending else { return "" }
        return "Точно стереть? (\(current.files(in: p).count) файлов)"
    }
    func performDelete() {
        guard let p = pending else { return }
        let scanner = TraceScanner()
        let report = model.deleter.delete(app: current, period: p, pruneUnder: scanner.searchPaths)
        lastReport = report
        model.freedTotal += report.freedBytes
        pending = nil
        let fresh = scanner.scan().first { $0.name == current.name }
        current = fresh ?? AppLogs(name: current.name, files: [])
        model.rescan()
        model.loadDashboard()
    }
    func dateStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; return f.string(from: d)
    }
}

// MARK: - Экран 2: IP-адрес

struct IPView: View {
    @State private var locals: [String] = []
    @State private var publicIP: String?
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { BackButton(); Text("Мой IP-адрес").font(.system(size: 22, weight: .bold)); Spacer() }.padding(.bottom, 4)

            Text("Локальный адрес (в вашей сети):").font(.headline).foregroundColor(.black)
            if locals.isEmpty {
                Text("не найден").foregroundColor(.black.opacity(0.5))
            } else {
                ForEach(locals, id: \.self) { Text($0).font(.system(.title3, design: .monospaced)).foregroundColor(.black) }
            }

            Divider()

            Text("Публичный адрес (виден в интернете):").font(.headline).foregroundColor(.black)
            if loading {
                ProgressView()
            } else if let publicIP {
                Text(publicIP).font(.system(.title3, design: .monospaced)).foregroundColor(.black)
            } else {
                Text("нажмите «Узнать»").foregroundColor(.black.opacity(0.5))
            }
            Button(action: fetchPublic) {
                Text("Узнать публичный IP").foregroundColor(.black)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.green).clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)

            Spacer()
        }
        .padding(30)
        .onAppear { locals = IPService.localIPv4Addresses() }
    }
    func fetchPublic() {
        loading = true
        IPService.fetchPublicIP { ip in
            publicIP = ip ?? "не удалось узнать (нет интернета?)"
            loading = false
        }
    }
}

// MARK: - Экран 3: подозрительные программы

struct SecurityView: View {
    @State private var items: [SecurityItem] = []
    @State private var scanned = false
    var suspicious: [SecurityItem] { items.filter { $0.suspicion != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { BackButton(); Text("Подозрительные программы").font(.system(size: 22, weight: .bold)); Spacer() }

            Text("Проверяю автозапуск — что стартует само при включении Mac. Это не антивирус: подсвечиваю необычное, решаете вы.")
                .font(.caption).foregroundColor(.black.opacity(0.6))

            if scanned {
                Text(suspicious.isEmpty
                     ? "Подозрительного не найдено ✅ (всего записей автозапуска: \(items.count))"
                     : "Подозрительных: \(suspicious.count) из \(items.count)")
                    .font(.headline)
                    .foregroundColor(suspicious.isEmpty ? .green : .red)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.suspicion == nil ? "checkmark.circle" : "exclamationmark.triangle.fill")
                                .foregroundColor(item.suspicion == nil ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline.weight(.semibold)).foregroundColor(.black)
                                Text(item.program).font(.caption).foregroundColor(.black.opacity(0.6)).lineLimit(1)
                                if let s = item.suspicion {
                                    Text("⚠︎ \(s)").font(.caption).foregroundColor(.red)
                                }
                            }
                            Spacer()
                            Text(item.source).font(.caption2).foregroundColor(.black.opacity(0.4))
                        }
                        .padding(10)
                        .background(item.suspicion == nil ? Color(white: 0.97) : Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(.vertical, 4)
            }
            Spacer()
        }
        .padding(30)
        .onAppear {
            items = SecurityInspector().inspect()
            scanned = true
        }
    }
}

// MARK: - Экран 4: скорость интернета

struct SpeedView: View {
    @State private var running = false
    @State private var result: Double?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 24) {
            HStack { BackButton(); Text("Скорость интернета").font(.system(size: 22, weight: .bold)); Spacer() }
            Spacer()

            if running {
                ProgressView("Измеряю…").scaleEffect(1.2)
            } else if let result {
                VStack(spacing: 6) {
                    Text(String(format: "%.1f", result)).font(.system(size: 64, weight: .bold)).foregroundColor(.black)
                    Text("Мбит/с (скачивание)").foregroundColor(.black.opacity(0.6))
                }
            } else if let error {
                Text(error).foregroundColor(.red)
            } else {
                Text("Нажмите кнопку, чтобы измерить\nскорость скачивания.")
                    .multilineTextAlignment(.center).foregroundColor(.black.opacity(0.6))
            }

            // Крупная зелёная кнопка.
            Button(action: measure) {
                Text(running ? "…" : "Измерить скорость")
                    .font(.title2.weight(.bold)).foregroundColor(.black)
                    .frame(width: 260, height: 90)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain).disabled(running)

            Spacer()
        }.padding(30)
    }
    func measure() {
        running = true; result = nil; error = nil
        SpeedTester.run { mbps, err in
            running = false
            if let mbps { result = mbps } else { error = err ?? "Не удалось измерить" }
        }
    }
}

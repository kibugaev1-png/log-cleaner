import SwiftUI

// Состояние всего приложения.
@MainActor
final class AppModel: ObservableObject {
    enum Phase { case consent, menu, logs, ip, security, speed }

    @Published var phase: Phase = .consent
    @Published var apps: [AppLogs] = []
    @Published var hiddenApps: Set<String> = []
    @Published var isScanning = false
    @Published var authError: String?
    @Published var showAll = false

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
            if ok { self.phase = .menu } else { self.authError = err }
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
            case .menu:     MenuView()
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

// MARK: - Меню

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            Text("Что хотите сделать?").font(.system(size: 28, weight: .bold)).padding(.top, 30)
            VStack(spacing: 14) {
                menuButton("1. Очистка следов и логов", "trash", .green) { model.openLogs() }
                menuButton("2. Мой IP-адрес", "network", Color(white: 0.9)) { model.phase = .ip }
                menuButton("3. Подозрительные программы", "magnifyingglass", Color(white: 0.9)) { model.phase = .security }
                menuButton("4. Скорость интернета", "speedometer", Color(white: 0.9)) { model.phase = .speed }
            }
            .frame(maxWidth: 440)
            Spacer()
        }.padding(30)
    }

    func menuButton(_ title: String, _ icon: String, _ bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundColor(.black).frame(width: 28)
                Text(title).font(.headline).foregroundColor(.black)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.black.opacity(0.4))
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
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
        lastReport = model.deleter.delete(app: current, period: p, pruneUnder: scanner.searchPaths)
        pending = nil
        let fresh = scanner.scan().first { $0.name == current.name }
        current = fresh ?? AppLogs(name: current.name, files: [])
        model.rescan()
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

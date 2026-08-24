import SwiftUI

// Состояние всего приложения.
@MainActor
final class AppModel: ObservableObject {
    enum Phase { case consent, list }

    @Published var phase: Phase = .consent
    @Published var apps: [AppLogs] = []
    @Published var hiddenApps: Set<String> = []      // те, где нажали «Нет»
    @Published var isScanning = false
    @Published var authError: String?

    private let auth = AuthService()
    private let scanner = LogScanner()
    private let lister = AppLister()
    let deleter = LogDeleter()

    @Published var showAll = false                   // B: показывать и приложения без логов

    var visibleApps: [AppLogs] {
        apps
            .filter { !hiddenApps.contains($0.name) }
            .filter { showAll || $0.count > 0 }
    }
    var hasAccess: Bool { PermissionChecker.hasLogAccess() }

    func confirmOwner() {
        authError = nil
        auth.authenticate { [weak self] ok, err in
            guard let self else { return }
            if ok {
                self.phase = .list
                self.rescan()
            } else {
                self.authError = err
            }
        }
    }

    func rescan() {
        isScanning = true
        let scanner = self.scanner
        let lister = self.lister
        DispatchQueue.global(qos: .userInitiated).async {
            let logApps = scanner.scan()
            let installed = lister.installedAppNames()

            // Объединяем: приложения с логами + установленные без логов.
            let logNames = Set(logApps.map { $0.name.lowercased() })
            let extra = installed
                .filter { !logNames.contains($0.lowercased()) }
                .map { AppLogs(name: $0, files: []) }

            // С логами — сверху (по размеру), без логов — по алфавиту.
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
                .frame(minWidth: 640, minHeight: 520)
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
            case .consent: ConsentView()
            case .list:    AppListView()
            }
        }
        .foregroundColor(.black)
    }
}

// MARK: - Экран 1: согласие

struct ConsentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.black)
            Text("Это ваш компьютер?")
                .font(.system(size: 30, weight: .bold))
            Text("Подтвердите, что вы хозяин этого Mac.\nПосле входа вы увидите логи приложений и сможете их удалить.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 420)
            Button(action: { model.confirmOwner() }) {
                Text("Да, это мой компьютер")
                    .font(.headline)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            if let err = model.authError {
                Text(err).foregroundColor(.red).font(.callout)
            }
            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Экран 2: список приложений

struct AppListView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: AppLogs?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Логи приложений")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Toggle("Показывать все приложения", isOn: $model.showAll)
                    .toggleStyle(.switch)
                Button(action: { model.rescan() }) {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
            }
            .padding()

            if !model.hasAccess {
                accessBanner
            }

            if model.isScanning {
                Spacer()
                ProgressView("Ищу логи…").frame(maxWidth: .infinity)
                Spacer()
            } else if model.visibleApps.isEmpty {
                Spacer()
                Text("Логи не найдены.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.visibleApps) { app in
                            AppRow(app: app,
                                   onYes: { selected = app },
                                   onNo: { model.hide(app) })
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $selected) { app in
            AppDetailView(app: app)
                .environmentObject(model)
        }
    }

    var accessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Нужен полный доступ к диску").font(.headline)
                Text("Чтобы видеть логи всех приложений, разрешите доступ в настройках.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Открыть настройки") { PermissionChecker.openFullDiskAccessSettings() }
        }
        .padding()
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

struct AppRow: View {
    let app: AppLogs
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundColor(.gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                Text(app.count > 0 ? "\(app.count) файлов · \(formatBytes(app.totalSize))" : "нет логов")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onYes) { pill("Да", app.count > 0 ? .green : .gray) }
                .buttonStyle(.plain)
                .disabled(app.count == 0)
            Button(action: onNo)  { pill("Нет", .red) }.buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .frame(width: 56, height: 32)
            .background(color)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Экран 3: детали приложения и удаление

struct AppDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let app: AppLogs

    @State private var current: AppLogs
    @State private var pending: TimePeriod?          // выбранный период, ждём подтверждения
    @State private var lastReport: DeleteReport?

    init(app: AppLogs) {
        self.app = app
        _current = State(initialValue: app)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(current.name).font(.system(size: 22, weight: .bold))
                Spacer()
                Button("Закрыть") { dismiss() }
            }

            Text("\(current.count) файлов · \(formatBytes(current.totalSize))")
                .foregroundColor(.secondary)

            // Список файлов.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(current.files) { f in
                        HStack {
                            Text(f.name).lineLimit(1)
                            Spacer()
                            Text(formatBytes(f.size)).foregroundColor(.secondary).font(.caption)
                            Text(dateStr(f.modified)).foregroundColor(.secondary).font(.caption)
                        }
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 200)

            Text("Что удалить:").font(.headline)
            VStack(spacing: 8) {
                ForEach(TimePeriod.allCases) { period in
                    let n = current.files(in: period).count
                    Button(action: { pending = period }) {
                        HStack {
                            Text(period.title)
                            Spacer()
                            Text("\(n) файлов").foregroundColor(.white.opacity(0.85)).font(.caption)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(n == 0 ? Color.gray : Color.red)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(n == 0)
                }
            }

            if let r = lastReport {
                Text("Удалено \(r.deletedCount) файлов, освобождено \(formatBytes(r.freedBytes))." +
                     (r.errors.isEmpty ? "" : " Ошибок: \(r.errors.count)."))
                    .foregroundColor(.green).font(.callout)
            }
        }
        .padding(24)
        .frame(width: 520)
        .foregroundColor(.black)
        .background(Color.white)
        .confirmationDialog(
            confirmText,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Да, стереть насовсем", role: .destructive) { performDelete() }
            Button("Отмена", role: .cancel) { pending = nil }
        } message: {
            Text("Файлы будут удалены безвозвратно, восстановить их нельзя.")
        }
    }

    var confirmText: String {
        guard let p = pending else { return "" }
        let n = current.files(in: p).count
        return "Точно стереть? (\(n) файлов)"
    }

    func performDelete() {
        guard let p = pending else { return }
        let report = model.deleter.delete(app: current, period: p)
        lastReport = report
        pending = nil
        // Обновляем локальный список и общий скан.
        let scanner = LogScanner()
        let fresh = scanner.scan().first { $0.name == current.name }
        current = fresh ?? AppLogs(name: current.name, files: [])
        model.rescan()
    }

    func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: d)
    }
}

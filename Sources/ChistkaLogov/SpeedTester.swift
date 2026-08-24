import Foundation

// Замер скорости интернета: качает тестовые данные и считает Мбит/с.
struct SpeedTester {
    // Чистая функция для теста: байты + секунды -> Мбит/с.
    static func megabitsPerSecond(bytes: Int64, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        let bits = Double(bytes) * 8.0
        return (bits / seconds) / 1_000_000.0
    }

    // Качает N байт с сервера Cloudflare и возвращает скорость в Мбит/с.
    static func run(bytes: Int = 25_000_000,
                    completion: @escaping (Double?, String?) -> Void) {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)") else {
            completion(nil, "Неверный адрес"); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        URLSession.shared.dataTask(with: req) { data, _, error in
            let elapsed = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                if let error {
                    completion(nil, error.localizedDescription); return
                }
                guard let data, !data.isEmpty else {
                    completion(nil, "Нет данных"); return
                }
                let mbps = megabitsPerSecond(bytes: Int64(data.count), seconds: elapsed)
                completion(mbps, nil)
            }
        }.resume()
    }
}

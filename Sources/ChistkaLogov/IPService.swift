import Foundation

// Узнаёт IP-адреса: локальные (в твоей сети) и публичный (виден в интернете).
struct IPService {
    // Локальные IPv4-адреса сетевых интерфейсов (Wi-Fi, Ethernet).
    static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let addr = cur.pointee.ifa_addr
            // только активные интерфейсы, не loopback, семейство IPv4
            if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
               (flags & IFF_LOOPBACK) == 0,
               let addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if !ip.isEmpty && !addresses.contains(ip) { addresses.append(ip) }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return addresses
    }

    // Публичный IP — запрос к внешнему сервису.
    static func fetchPublicIP(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.ipify.org") else { completion(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let ip = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion((ip?.isEmpty == false) ? ip : nil)
            }
        }.resume()
    }
}

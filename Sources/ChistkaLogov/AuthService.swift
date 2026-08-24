import Foundation
import LocalAuthentication

// Обёртка над LocalAuthentication: подтверждение, что за компьютером его хозяин.
struct AuthService {
    func authenticate(reason: String = "Подтвердите, что это ваш компьютер",
                      completion: @escaping (Bool, String?) -> Void) {
        let ctx = LAContext()
        var error: NSError?
        let policy = LAPolicy.deviceOwnerAuthentication // Touch ID, иначе — системный пароль

        guard ctx.canEvaluatePolicy(policy, error: &error) else {
            completion(false, error?.localizedDescription ?? "Проверка недоступна на этом компьютере")
            return
        }

        ctx.evaluatePolicy(policy, localizedReason: reason) { ok, err in
            DispatchQueue.main.async {
                completion(ok, ok ? nil : (err?.localizedDescription ?? "Отменено"))
            }
        }
    }
}

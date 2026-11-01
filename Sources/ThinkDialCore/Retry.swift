import Foundation

public enum Retry {
    public static func run<T: Sendable>(
        attempts: Int,
        delayNanoseconds: UInt64,
        sleep: @Sendable (UInt64) async -> Void,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let tries = max(1, attempts)
        var lastError: Error?
        for index in 0..<tries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if index + 1 < tries, delayNanoseconds > 0 {
                    await sleep(delayNanoseconds)
                }
            }
        }
        throw lastError ?? DDCError.cancelled
    }
}

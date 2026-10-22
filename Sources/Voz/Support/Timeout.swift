import os

private final class SingleResume<Value: Sendable>: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<Value, any Error>?>

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    func resume(with result: Result<Value, any Error>) {
        let pending = continuation.withLock { state -> CheckedContinuation<Value, any Error>? in
            defer { state = nil }
            return state
        }
        pending?.resume(with: result)
    }
}

func withTimeout<Value: Sendable>(
    _ timeout: Duration,
    onTimeout: any Error,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        let gate = SingleResume(continuation)
        let work = Task {
            do {
                gate.resume(with: .success(try await operation()))
            } catch {
                gate.resume(with: .failure(error))
            }
        }
        Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            gate.resume(with: .failure(onTimeout))
            work.cancel()
        }
    }
}

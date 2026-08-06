import Foundation

final class WorkCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

enum BoundedConcurrentWork {
    /// Executes at most `maxConcurrent` operations at a time and preserves input order in its output.
    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maxConcurrent: Int,
        shouldScheduleNext: @escaping @Sendable () -> Bool = { true },
        operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        guard inputs.isEmpty == false else { return [] }

        let limit = max(1, min(maxConcurrent, inputs.count))
        var nextIndex = 0
        var results = Array<Output?>(repeating: nil, count: inputs.count)

        await withTaskGroup(of: (Int, Output).self) { group in
            func addNextTask() {
                guard nextIndex < inputs.count, shouldScheduleNext() else { return }
                let index = nextIndex
                let input = inputs[index]
                nextIndex += 1
                group.addTask {
                    (index, await operation(input))
                }
            }

            for _ in 0..<limit {
                addNextTask()
            }

            while let (index, output) = await group.next() {
                results[index] = output
                guard shouldScheduleNext() else {
                    group.cancelAll()
                    break
                }
                addNextTask()
            }
        }

        return results.compactMap { $0 }
    }
}

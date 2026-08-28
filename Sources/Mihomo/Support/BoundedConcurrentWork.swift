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
    /// Executes at most `maxConcurrent` operations at a time, in input order.
    ///
    /// The result array is **not** index-aligned with `inputs`: when `shouldScheduleNext` turns
    /// false the remaining work is cancelled and those entries are simply absent, so the output can
    /// be shorter than the input. Relative order of the results that did complete is preserved.
    /// Callers that need to attribute a result back to its input must carry the input inside
    /// `Output` (as every caller here does) rather than zipping by index, and callers that report
    /// counts must derive "cancelled" from `inputs.count - results.count`.
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

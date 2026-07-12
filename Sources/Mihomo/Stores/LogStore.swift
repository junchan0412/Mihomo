import Combine
import Foundation

@MainActor
final class LogStore: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var isPaused = false
    @Published var bufferedCount = 0
}

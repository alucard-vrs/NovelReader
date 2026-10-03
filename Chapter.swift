import Foundation

struct Chapter: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let text: String
}

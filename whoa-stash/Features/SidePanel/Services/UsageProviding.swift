import Foundation

/// Interface commune aux trois fournisseurs de l'onglet AI : chacun rend ce que la carte montre,
/// ou une erreur que `currentReading()` transforme en état d'erreur propre à son agent — jamais
/// un « — » sans explication.
protocol UsageProviding: Sendable {
    var provider: NotchUsageProvider { get }
    func fetchReading() async throws -> NotchUsageReading
}

extension UsageProviding {
    func currentReading() async -> NotchUsageReading {
        do {
            return try await fetchReading()
        } catch {
            return NotchUsageReading.failure(of: provider, error: error)
        }
    }
}

extension ClaudeUsageService: UsageProviding {
    var provider: NotchUsageProvider { .claude }
    func fetchReading() async throws -> NotchUsageReading { .claude(.loaded(try await fetchSnapshot())) }
}

extension CodexUsageService: UsageProviding {
    var provider: NotchUsageProvider { .codex }
    func fetchReading() async throws -> NotchUsageReading { .codex(.loaded(try await fetchSnapshot())) }
}

extension CopilotUsageService: UsageProviding {
    var provider: NotchUsageProvider { .copilot }
    func fetchReading() async throws -> NotchUsageReading { .copilot(.loaded(try await fetchSnapshot())) }
}

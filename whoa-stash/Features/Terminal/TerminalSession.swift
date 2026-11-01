import AppKit
import os
import SwiftTerm

/// Le shell de l'onglet Terminal : un seul, pour toute l'app.
///
/// Le shell tourne dans un vrai pseudo-terminal (`LocalProcessTerminalView` ouvre le PTY et
/// l'émulateur). La vue appartient à la session et non à une fenêtre : le panneau de l'encoche
/// a une fenêtre par écran, reconstruites quand la configuration des écrans change, et la
/// session doit survivre aux deux, comme au repli du panneau. L'onglet Terminal d'une fenêtre
/// y rattache simplement la vue quand il s'affiche (voir `TerminalTabView.attach(_:)`).
///
/// Le shell ne démarre qu'à la première apparition de l'onglet : un lancement ordinaire, et
/// surtout un test, n'ouvre aucun processus.
@MainActor
final class TerminalSession {

    let view: LocalProcessTerminalView
    private(set) var isRunning = false
    private var startedAt: Date?
    private let delegateProxy = DelegateProxy()

    init() {
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
        view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.nativeBackgroundColor = NSColor(white: 0.06, alpha: 1)
        view.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        delegateProxy.session = self
        view.processDelegate = delegateProxy
    }

    /// Lance le shell de connexion de l'utilisateur s'il ne tourne pas déjà.
    func startIfNeeded() {
        guard !isRunning else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        // Un « - » devant le nom fait du processus un shell de connexion : c'est lui qui lit
        // `.zprofile` et rend le `PATH` de l'utilisateur, que l'app, lancée hors d'un terminal,
        // n'a pas.
        let loginName = "-" + (shell as NSString).lastPathComponent
        isRunning = true
        startedAt = Date()
        view.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: loginName,
            currentDirectory: NSHomeDirectory()
        )
        Log.terminal.info("shell démarré")
    }

    /// Le shell s'est arrêté (`exit`, Ctrl+D, processus tué).
    fileprivate func processTerminated(exitCode: Int32?) {
        isRunning = false
        let lived = Date().timeIntervalSince(startedAt ?? Date())
        Log.terminal.info("shell terminé après \(lived, format: .fixed(precision: 1)) s")
        view.feed(text: "\r\n[session terminée]\r\n")
        // Relance aussitôt, sauf si le shell est tombé tout de suite : un `.zshrc` cassé ne doit
        // pas faire tourner une boucle de démarrages.
        guard lived > 2 else { return }
        startIfNeeded()
    }

    /// Reçoit les rappels de la vue. Séparé de la session parce que le protocole de SwiftTerm
    /// n'est pas isolé au main actor, alors que ses rappels arrivent bien sur la file principale.
    private final class DelegateProxy: LocalProcessTerminalViewDelegate {
        weak var session: TerminalSession?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            MainActor.assumeIsolated { session?.processTerminated(exitCode: exitCode) }
        }
    }
}

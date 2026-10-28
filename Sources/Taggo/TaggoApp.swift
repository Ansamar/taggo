import AppKit
import SwiftUI

@main
struct TaggoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Taggo", id: "main") {
            ContentView()
                .environment(appDelegate.library)
                .frame(minWidth: 960, minHeight: 540)
        }
        .commands { TaggoCommands(library: appDelegate.library) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let library = Library()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        library.commitDrafts()
        let count = library.dirtyCount
        guard count > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Salvare le modifiche a \(count) file prima di uscire?"
        alert.addButton(withTitle: "Salva")
        alert.addButton(withTitle: "Annulla")
        alert.addButton(withTitle: "Non salvare")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            library.save { ok in NSApp.reply(toApplicationShouldTerminate: ok) }
            return .terminateLater
        case .alertThirdButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    /// Cartelle o file trascinati sull'icona dell'app nel Dock.
    func application(_ application: NSApplication, open urls: [URL]) {
        library.open(urls, append: !library.files.isEmpty)
    }
}

struct TaggoCommands: Commands {
    let library: Library

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Apri cartella…") { library.chooseFolder(append: false) }
                .keyboardShortcut("o")
            Button("Aggiungi cartella…") { library.chooseFolder(append: true) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Ricarica") { library.reload() }
                .keyboardShortcut("r")
            Button("Svuota elenco") { library.clearList() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Salva") { library.save() }
                .keyboardShortcut("s")
            Button("Annulla modifiche non salvate") { library.revert() }
        }
        CommandMenu("Converti") {
            Button("Tag → Nome file…") { library.present(.tagToFilename) }
                .keyboardShortcut("1", modifiers: .option)
            Button("Nome file → Tag…") { library.present(.filenameToTag) }
                .keyboardShortcut("2", modifiers: .option)
            Divider()
            Button("Numerazione automatica…") { library.present(.autonumber) }
                .keyboardShortcut("k", modifiers: [.command, .option])
            Button("Dividi in dischi…") { library.present(.discSplit) }
                .keyboardShortcut("d", modifiers: [.command, .option])
        }
        CommandMenu("Fonti") {
            Button("Cerca su MusicBrainz…") { library.present(.musicBrainz) }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button("Apri in MusicBrainz Picard") { library.openInPicard() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
            Menu("Cerca sul web") {
                ForEach(WebLookup.allCases) { site in
                    Button(site.rawValue) { library.openWeb(site) }
                }
            }
        }
        CommandGroup(replacing: .help) {
            Button("Come usare Taggo") {
                if let guide = Bundle.main.url(forResource: "HOW_TO_USE", withExtension: "md") {
                    NSWorkspace.shared.open(guide)
                }
            }
        }
        CommandMenu("Azioni") {
            Button("Maiuscole/minuscole…") { library.present(.caseConvert) }
                .keyboardShortcut("u", modifiers: [.command, .option])
            Button("Sostituisci…") { library.present(.replace) }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }
}

import SwiftUI

struct ContentView: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            HSplitView {
                TagEditorPanel()
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 440)
                FileTableView()
                    .frame(minWidth: 500)
            }
            Divider()
            StatusBar()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { library.chooseFolder(append: false) } label: {
                    Label("Apri", systemImage: "folder")
                }
                .help("Apri cartella (⌘O)")
                Button { library.save() } label: {
                    Label("Salva", systemImage: "square.and.arrow.down")
                }
                .help("Salva le modifiche (⌘S)")
                .disabled(library.dirtyCount == 0 && library.editedFields.isEmpty)
                Button { library.reload() } label: {
                    Label("Ricarica", systemImage: "arrow.clockwise")
                }
                .help("Ricarica (⌘R)")
            }
            ToolbarItemGroup {
                Button { library.present(.tagToFilename) } label: {
                    Label("Tag → Nome file", systemImage: "tag")
                }
                .help("Tag → Nome file (⌥1)")
                Button { library.present(.filenameToTag) } label: {
                    Label("Nome file → Tag", systemImage: "doc.text")
                }
                .help("Nome file → Tag (⌥2)")
                Button { library.present(.autonumber) } label: {
                    Label("Numerazione", systemImage: "list.number")
                }
                .help("Numerazione automatica")
                Button { library.present(.discSplit) } label: {
                    Label("Dischi", systemImage: "square.stack")
                }
                .help("Dividi in dischi (⌥⌘D)")
                Menu {
                    Button("Cerca su MusicBrainz…") { library.present(.musicBrainz) }
                    Button("Apri in MusicBrainz Picard") { library.openInPicard() }
                    Divider()
                    ForEach(WebLookup.allCases) { site in
                        Button("Cerca su \(site.rawValue)") { library.openWeb(site) }
                    }
                } label: {
                    Label("Fonti", systemImage: "globe")
                }
                .help("MusicBrainz, Picard e altri database")
                Menu {
                    Button("Maiuscole/minuscole…") { library.present(.caseConvert) }
                    Button("Sostituisci…") { library.present(.replace) }
                } label: {
                    Label("Azioni", systemImage: "wand.and.stars")
                }
                .help("Azioni")
            }
        }
        .searchable(text: $library.filter, prompt: "Filtra")
        .disabled(library.isBusy)
        .overlay {
            if library.isBusy {
                ProgressView(value: library.progress) { Text(library.statusMessage) }
                    .frame(width: 280)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.open(urls, append: !library.files.isEmpty)
            return true
        }
        .sheet(item: $library.activeSheet) { sheet in
            switch sheet {
            case .tagToFilename: TagToFilenameSheet()
            case .filenameToTag: FilenameToTagSheet()
            case .autonumber: AutonumberSheet()
            case .discSplit: DiscSplitSheet()
            case .caseConvert: CaseSheet()
            case .replace: ReplaceSheet()
            case .musicBrainz: MusicBrainzSheet()
            }
        }
        .alert("Attenzione", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK") { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }
}

private struct StatusBar: View {
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 16) {
            Text("\(library.files.count) file")
            if !library.selection.isEmpty { Text("\(library.selection.count) selezionati") }
            if library.dirtyCount > 0 {
                Label("\(library.dirtyCount) da salvare", systemImage: "circle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text(library.statusMessage).foregroundStyle(.secondary)
        }
        .font(.callout)
        .labelStyle(StatusLabelStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

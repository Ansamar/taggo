import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TagEditorPanel: View {
    @Environment(Library.self) private var library

    var body: some View {
        ScrollView {
            if library.selection.isEmpty {
                Text("Seleziona uno o più file per modificarne i tag.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .padding(.horizontal)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(library.selection.count == 1 ? "1 file selezionato" : "\(library.selection.count) file selezionati")
                        .font(.headline)
                    field(.title)
                    field(.artist)
                    field(.album)
                    field(.albumArtist)
                    HStack(alignment: .top) {
                        field(.year)
                        field(.track)
                        field(.disc)
                    }
                    field(.genre)
                    field(.composer)
                    field(.comment, multiline: true)
                    HStack {
                        Spacer()
                        Button("Applica") { library.commitDrafts() }
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(library.editedFields.isEmpty)
                            .help("Applica i campi ai file selezionati (⌘↩). Salva su disco con ⌘S.")
                    }
                    Divider()
                    CoverView()
                }
                .padding(14)
            }
        }
        .background(.background.secondary)
    }

    private func field(_ field: TagField, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(field.label)
                if library.editedFields.contains(field) {
                    Circle().fill(.orange).frame(width: 5, height: 5)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Group {
                if multiline {
                    TextField(library.placeholder(for: field), text: library.draftBinding(field), axis: .vertical)
                        .lineLimit(3...8)
                } else {
                    TextField(library.placeholder(for: field), text: library.draftBinding(field))
                        .onSubmit { library.commitDrafts() }
                }
            }
            .textFieldStyle(.roundedBorder)
            .contextMenu {
                Button("Svuota campo") { library.clearField(field) }
            }
        }
    }
}

struct CoverView: View {
    @Environment(Library.self) private var library
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Copertina").font(.caption).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                if let image = library.cover {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo").font(.largeTitle)
                        Text("Trascina qui un'immagine").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 260)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                library.setCover(from: url)
                return true
            } isTargeted: { isTargeted = $0 }

            if !library.coverDescription.isEmpty {
                Text(library.coverDescription + (library.selection.count > 1 ? " · primo file" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Aggiungi…", action: chooseImage)
                Button("Rimuovi") { library.removeCover() }
                    .disabled(library.cover == nil)
                Button("Esporta…") { library.exportCover() }
                    .disabled(library.coverData == nil)
            }
            .controlSize(.small)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Scegli la copertina per i file selezionati"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        library.setCover(from: url)
    }
}

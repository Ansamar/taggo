import AppKit
import SwiftUI

struct FileTableView: View {
    @Environment(Library.self) private var library
    @SceneStorage("columns") private var columns = TableColumnCustomization<AudioFile>()

    var body: some View {
        @Bindable var library = library
        Table(library.visibleFiles, selection: $library.selection, sortOrder: $library.sortOrder, columnCustomization: $columns) {
            tagColumns
            infoColumns
        }
        .contextMenu(forSelectionType: AudioFile.ID.self) { ids in
            if !ids.isEmpty {
                Button("Mostra nel Finder") { revealInFinder(ids) }
                Button("Apri con l'app predefinita") { openFiles(ids) }
                Button("Apri in MusicBrainz Picard") {
                    library.selection = ids
                    library.openInPicard()
                }
                Divider()
                Button("Rimuovi dall'elenco") { library.removeFromList(ids) }
            }
        } primaryAction: { ids in
            openFiles(ids)
        }
        .onDeleteCommand {
            library.removeFromList(library.selection)
        }
        .overlay {
            if library.files.isEmpty && !library.isBusy {
                ContentUnavailableView {
                    Label("Nessun file", systemImage: "music.note.list")
                } description: {
                    Text("Trascina qui una cartella di musica oppure usa Apri cartella (⌘O).")
                } actions: {
                    Button("Apri cartella…") { library.chooseFolder(append: false) }
                }
            }
        }
    }

    @TableColumnBuilder<AudioFile, KeyPathComparator<AudioFile>>
    private var tagColumns: some TableColumnContent<AudioFile, KeyPathComparator<AudioFile>> {
        TableColumn("Nome file", value: \.filename) { file in
            HStack(spacing: 5) {
                Circle()
                    .fill(file.isDirty ? Color.orange : Color.clear)
                    .frame(width: 6, height: 6)
                Text(file.filename)
            }
            .help(file.path)
        }
        .width(min: 160, ideal: 260)
        .customizationID("filename")
        TableColumn("Titolo", value: \.title).customizationID("title")
        TableColumn("Artista", value: \.artist).customizationID("artist")
        TableColumn("Album", value: \.album).customizationID("album")
        TableColumn("Artista album", value: \.albumArtist).customizationID("albumArtist")
        TableColumn("Anno", value: \.year).width(50).customizationID("year")
        TableColumn("Traccia", value: \.trackNumber) { Text($0[.track]) }
            .width(50).customizationID("track")
        TableColumn("Disco", value: \.discNumber) { Text($0[.disc]) }
            .width(45).customizationID("disc")
    }

    @TableColumnBuilder<AudioFile, KeyPathComparator<AudioFile>>
    private var infoColumns: some TableColumnContent<AudioFile, KeyPathComparator<AudioFile>> {
        TableColumn("Genere", value: \.genre).customizationID("genre")
        TableColumn("Compositore", value: \.composer)
            .customizationID("composer").defaultVisibility(.hidden)
        TableColumn("Commento", value: \.comment)
            .customizationID("comment").defaultVisibility(.hidden)
        TableColumn("Durata", value: \.duration) { Text($0.durationText).monospacedDigit() }
            .width(55).customizationID("duration")
        TableColumn("Bitrate", value: \.bitrate) { file in
            Text(file.bitrate > 0 ? "\(file.bitrate)" : "").monospacedDigit()
        }
        .width(55).customizationID("bitrate")
        TableColumn("Cop.", value: \.coverSortKey) { file in
            if file.showsCover {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .width(34).customizationID("cover")
        TableColumn("Formato", value: \.format).width(55).customizationID("format")
        TableColumn("Percorso", value: \.folder).customizationID("folder")
    }

    private func urls(_ ids: Set<AudioFile.ID>) -> [URL] {
        library.files.filter { ids.contains($0.id) }.map(\.url)
    }

    private func revealInFinder(_ ids: Set<AudioFile.ID>) {
        NSWorkspace.shared.activateFileViewerSelecting(urls(ids))
    }

    private func openFiles(_ ids: Set<AudioFile.ID>) {
        for url in urls(ids).prefix(20) { NSWorkspace.shared.open(url) }
    }
}

import AppKit
import SwiftUI

struct MusicBrainzSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library

    enum Matching: String, CaseIterable, Identifiable {
        case order = "Ordine della tabella"
        case number = "Numero di disco e traccia"
        var id: String { rawValue }
    }

    struct Pair: Identifiable {
        let file: AudioFile
        let track: MusicBrainz.FlatTrack?
        var id: AudioFile.ID { file.id }
        var lengthMismatch: Bool {
            guard let track, track.seconds > 0, file.duration > 0 else { return false }
            return abs(track.seconds - file.duration) > 5
        }
    }

    @State private var artist = ""
    @State private var album = ""
    @State private var results: [MusicBrainz.ReleaseSummary] = []
    @State private var selectedID: String?
    @State private var release: MusicBrainz.Release?
    @State private var tracks: [MusicBrainz.FlatTrack] = []
    @State private var coverData: Data?
    @State private var busy = ""
    @State private var error = ""
    @State private var matching = Matching.order
    @State private var fields: Set<TagField> = [.title, .artist, .album, .albumArtist, .year, .track, .disc]
    @State private var writeCover = true
    @AppStorage("mb.originalYear") private var originalYear = false

    var body: some View {
        let files = library.targetFiles
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cerca su MusicBrainz").font(.title2.bold())
                Spacer()
                Text(library.selection.isEmpty ? "\(files.count) file visibili" : "\(files.count) file selezionati")
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Artista", text: $artist)
                TextField("Album", text: $album)
                Button("Cerca", action: search)
                    .keyboardShortcut(.defaultAction)
                    .disabled(artist.isEmpty && album.isEmpty)
            }
            .textFieldStyle(.roundedBorder)

            Table(results, selection: $selectedID) {
                TableColumn("Album") { r in
                    Text(r.title).fontWeight(r.trackCount == files.count ? .semibold : .regular)
                }
                TableColumn("Artista") { Text($0.artist) }
                TableColumn("Data") { Text($0.date ?? "") }.width(80)
                TableColumn("Paese") { Text($0.country ?? "") }.width(45)
                TableColumn("Formato") { Text($0.format) }.width(90)
                TableColumn("Etichetta") { Text($0.label) }.width(110)
                TableColumn("Brani") { r in
                    Text(r.trackCount.map(String.init) ?? "")
                        .foregroundStyle(r.trackCount == files.count ? Color.green : Color.primary)
                }
                .width(45)
            }
            .frame(height: 170)
            .onChange(of: selectedID) { loadRelease() }

            if !busy.isEmpty {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(busy) }
            } else if !error.isEmpty {
                Text(error).foregroundStyle(.red)
            }

            if release != nil {
                options
                pairsTable(pairs(files))
            } else {
                ContentUnavailableView(
                    "Scegli un'edizione",
                    systemImage: "opticaldisc",
                    description: Text("In verde le edizioni con lo stesso numero di brani dei file.")
                )
                .frame(maxHeight: .infinity)
            }

            HStack {
                if let id = selectedID {
                    Link("Apri su musicbrainz.org", destination: URL(string: "https://musicbrainz.org/release/\(id)")!)
                        .font(.callout)
                }
                Spacer()
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Applica ai file") {
                    apply(pairs(files))
                    dismiss()
                }
                .disabled(release == nil || !busy.isEmpty || pairs(files).allSatisfy { $0.track == nil })
            }
        }
        .padding(20)
        .frame(width: 900, height: 680)
        .onAppear {
            let hint = library.lookupHint
            artist = hint.artist
            album = hint.album
            if !artist.isEmpty || !album.isEmpty { search() }
        }
    }

    private var options: some View {
        HStack(alignment: .top, spacing: 18) {
            if let image = coverData.flatMap(NSImage.init(data:)) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker("Abbina per", selection: $matching) {
                    ForEach(Matching.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 360)
                HStack(spacing: 12) {
                    ForEach([TagField.title, .artist, .album, .albumArtist, .year, .track, .disc, .genre]) { field in
                        Toggle(field.label, isOn: Binding(
                            get: { fields.contains(field) },
                            set: { if $0 { fields.insert(field) } else { fields.remove(field) } }
                        ))
                    }
                }
                HStack(spacing: 12) {
                    Toggle("Copertina", isOn: $writeCover).disabled(coverData == nil)
                    Toggle("Anno della prima uscita", isOn: $originalYear)
                }
            }
            .font(.callout)
        }
    }

    private func pairsTable(_ pairs: [Pair]) -> some View {
        Table(pairs) {
            TableColumn("File") { Text($0.file.filename) }
            TableColumn("Durata") { Text($0.file.durationText).monospacedDigit() }.width(50)
            TableColumn("Disco/Traccia") { p in
                Text(p.track.map { "\($0.disc)/\($0.track)" } ?? "")
            }
            .width(85)
            TableColumn("Titolo MusicBrainz") { p in
                Text(p.track?.title ?? "— nessuna traccia —")
                    .foregroundStyle(p.track == nil ? Color.secondary : Color.primary)
            }
            TableColumn("Durata MB") { p in
                Text(p.track.map { Self.time($0.seconds) } ?? "")
                    .monospacedDigit()
                    .foregroundStyle(p.lengthMismatch ? Color.orange : Color.primary)
                    .help(p.lengthMismatch ? "Durata molto diversa: controlla l'abbinamento" : "")
            }
            .width(70)
        }
    }

    // MARK: Logica

    private func pairs(_ files: [AudioFile]) -> [Pair] {
        switch matching {
        case .order:
            return files.enumerated().map { i, file in Pair(file: file, track: i < tracks.count ? tracks[i] : nil) }
        case .number:
            let byKey = Dictionary(tracks.map { ("\($0.disc)-\($0.track)", $0) }, uniquingKeysWith: { a, _ in a })
            return files.map { file in
                let disc = max(file.discNumber, 1)
                return Pair(file: file, track: byKey["\(disc)-\(file.trackNumber)"])
            }
        }
    }

    private func search() {
        error = ""
        busy = "Ricerca…"
        release = nil
        selectedID = nil
        Task {
            do {
                results = try await MusicBrainz.shared.search(artist: artist, album: album)
                if results.isEmpty { error = "Nessun risultato. Prova a semplificare artista o album." }
            } catch {
                self.error = error.localizedDescription
            }
            busy = ""
        }
    }

    private func loadRelease() {
        guard let id = selectedID else { return }
        error = ""
        busy = "Caricamento dell'album…"
        release = nil
        coverData = nil
        Task {
            do {
                let loaded = try await MusicBrainz.shared.release(id: id)
                guard selectedID == id else { return }
                release = loaded
                tracks = MusicBrainz.flatten(loaded)
                let files = library.targetFiles
                let keys = files.map { "\(max($0.discNumber, 1))-\($0.trackNumber)" }
                matching = files.allSatisfy({ $0.trackNumber > 0 }) && Set(keys).count == keys.count ? .number : .order
                if loaded.hasFrontCover {
                    busy = "Scaricamento della copertina…"
                    coverData = try? await MusicBrainz.shared.frontCover(releaseID: id)
                }
            } catch {
                self.error = error.localizedDescription
            }
            if selectedID == id { busy = "" }
        }
    }

    private func apply(_ pairs: [Pair]) {
        guard let release else { return }
        let date = originalYear ? (release.releaseGroup?.firstReleaseDate ?? release.date) : (release.date ?? release.releaseGroup?.firstReleaseDate)
        var updates: [AudioFile.ID: [TagField: String]] = [:]
        for pair in pairs {
            guard let track = pair.track else { continue }
            var values: [TagField: String] = [
                .title: track.title,
                .artist: track.artist,
                .album: release.title,
                .albumArtist: release.artist,
                .track: "\(track.track)/\(track.trackTotal)",
                .disc: "\(track.disc)/\(track.discTotal)",
            ]
            if let year = date?.prefix(4), !year.isEmpty { values[.year] = String(year) }
            if let genre = release.topGenre { values[.genre] = genre.capitalized }
            updates[pair.file.id] = values.filter { fields.contains($0.key) }
        }
        library.applyTags(updates, cover: writeCover ? coverData : nil)
    }

    private static func time(_ seconds: Int) -> String {
        seconds > 0 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : ""
    }
}

import AppKit
import Observation
import SwiftUI

enum ActiveSheet: String, Identifiable {
    case tagToFilename, filenameToTag, autonumber, discSplit, caseConvert, replace, musicBrainz
    var id: String { rawValue }
}

struct FieldChange: Identifiable {
    let id = UUID()
    let filename: String
    let field: TagField
    let old: String
    let new: String
}

struct RenamePreview: Identifiable {
    let id: UUID
    let old: String
    let new: String
}

@MainActor
@Observable
final class Library {
    var files: [AudioFile] = []
    var selection: Set<AudioFile.ID> = [] {
        didSet { if selection != oldValue { selectionDidChange(from: oldValue) } }
    }
    var sortOrder: [KeyPathComparator<AudioFile>] = [KeyPathComparator(\AudioFile.path)] {
        didSet { files.sort(using: sortOrder) }
    }
    var filter = ""
    var isBusy = false
    var progress = 0.0
    var statusMessage = ""
    var errorMessage: String?
    var activeSheet: ActiveSheet?
    private var roots: [URL] = []

    // Stato del pannello di modifica.
    var drafts: [TagField: String] = [:]
    private(set) var mixedFields: Set<TagField> = []
    private(set) var editedFields: Set<TagField> = []
    private(set) var clearedFields: Set<TagField> = []
    private(set) var cover: NSImage?
    private(set) var coverData: Data?
    private(set) var coverDescription = ""
    private var coverRequest = UUID()

    // MARK: - Viste derivate

    var visibleFiles: [AudioFile] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return files }
        return files.filter { file in
            file.filename.localizedCaseInsensitiveContains(query)
                || file.tags.values.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var selectedFiles: [AudioFile] { files.filter { selection.contains($0.id) } }

    /// I file su cui agiscono convertitori e azioni: la selezione, o tutti quelli visibili.
    var targetFiles: [AudioFile] { selection.isEmpty ? visibleFiles : selectedFiles }

    var dirtyCount: Int { files.count { $0.isDirty } }

    // MARK: - Apertura

    func chooseFolder(append: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = append ? "Aggiungi" : "Apri"
        panel.message = "Scegli una cartella o dei file audio"
        guard panel.runModal() == .OK else { return }
        open(panel.urls, append: append)
    }

    func open(_ urls: [URL], append: Bool) {
        guard !isBusy, !urls.isEmpty else { return }
        if !append {
            guard confirmDiscardChanges() else { return }
            resetPanel()
            selection = []
            roots = []
        }
        roots += urls
        load(urls, append: append)
    }

    func reload() {
        guard !isBusy, !roots.isEmpty, confirmDiscardChanges() else { return }
        resetPanel()
        selection = []
        load(roots, append: false)
    }

    private func load(_ urls: [URL], append: Bool) {
        isBusy = true
        progress = 0
        statusMessage = "Lettura dei file…"
        let known = append ? Set(files.map { $0.url.standardizedFileURL }) : []
        Task {
            let found = await Task.detached { TagLibIO.audioFiles(in: urls) }.value
                .filter { !known.contains($0.standardizedFileURL) }
            var loaded: [AudioFile] = []
            var failed = 0
            let chunkSize = 100
            for start in stride(from: 0, to: found.count, by: chunkSize) {
                let chunk = Array(found[start..<min(start + chunkSize, found.count)])
                let result = await Task.detached { chunk.map(TagLibIO.read) }.value
                loaded += result.compactMap { $0 }
                failed += result.count { $0 == nil }
                progress = Double(start + chunk.count) / Double(found.count)
            }
            var all = append ? files + loaded : loaded
            all.sort(using: sortOrder)
            files = all
            isBusy = false
            statusMessage = "\(loaded.count) file caricati"
                + (failed > 0 ? ", \(failed) non leggibili" : "")
        }
    }

    func removeFromList(_ ids: Set<AudioFile.ID>) {
        commitDrafts()
        let dirty = files.count { ids.contains($0.id) && $0.isDirty }
        if dirty > 0, !confirm("\(dirty) file hanno modifiche non salvate.", detail: "Rimuovendoli dall'elenco le modifiche andranno perse.", ok: "Rimuovi") {
            return
        }
        selection.subtract(ids)
        files.removeAll { ids.contains($0.id) }
    }

    // MARK: - Salvataggio

    func save(completion: ((Bool) -> Void)? = nil) {
        commitDrafts()
        let dirty = files.filter(\.isDirty)
        guard !dirty.isEmpty else {
            statusMessage = "Nessuna modifica da salvare"
            completion?(true)
            return
        }
        isBusy = true
        progress = 0
        statusMessage = "Salvataggio…"
        Task {
            let results: [(UUID, String?)] = await Task.detached {
                dirty.map { file in
                    do {
                        try TagLibIO.write(file)
                        return (file.id, nil)
                    } catch {
                        return (file.id, "\(file.filename): \(error.localizedDescription)")
                    }
                }
            }.value
            let saved = Set(results.filter { $0.1 == nil }.map(\.0))
            let errors = results.compactMap(\.1)
            mutate(saved) { $0.markSaved() }
            isBusy = false
            statusMessage = "\(saved.count) file salvati"
            if !errors.isEmpty {
                errorMessage = "\(errors.count) file non salvati:\n" + errors.prefix(20).joined(separator: "\n")
            }
            loadPanel()
            completion?(errors.isEmpty)
        }
    }

    func revert() {
        resetPanel()
        mutate(Set(files.filter(\.isDirty).map(\.id))) { file in
            file.tags = file.original
            file.coverEdit = nil
        }
        loadPanel()
        statusMessage = "Modifiche annullate"
    }

    private func confirmDiscardChanges() -> Bool {
        commitDrafts()
        let count = dirtyCount
        return count == 0 || confirm(
            "\(count) file hanno modifiche non salvate.",
            detail: "Se continui, le modifiche andranno perse.",
            ok: "Scarta modifiche"
        )
    }

    private func confirm(_ message: String, detail: String, ok: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Annulla")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Pannello di modifica

    private func selectionDidChange(from old: Set<AudioFile.ID>) {
        if !editedFields.isEmpty { applyDrafts(to: old) }
        loadPanel()
    }

    func draftBinding(_ field: TagField) -> Binding<String> {
        Binding(
            get: { self.drafts[field] ?? "" },
            set: { value in
                guard self.drafts[field] != value else { return }
                self.drafts[field] = value
                self.editedFields.insert(field)
                if !value.isEmpty { self.clearedFields.remove(field) }
            }
        )
    }

    /// Svuota esplicitamente un campo (serve quando i file selezionati hanno valori diversi).
    func clearField(_ field: TagField) {
        drafts[field] = ""
        editedFields.insert(field)
        clearedFields.insert(field)
    }

    func placeholder(for field: TagField) -> String {
        if clearedFields.contains(field) { return "< vuoto >" }
        if mixedFields.contains(field) && (drafts[field] ?? "").isEmpty { return "< mantieni >" }
        return ""
    }

    func commitDrafts() {
        guard !editedFields.isEmpty else { return }
        applyDrafts(to: selection)
        loadPanel()
    }

    private func applyDrafts(to ids: Set<AudioFile.ID>) {
        let fields = editedFields.filter { field in
            // Un campo con valori diversi lasciato vuoto non va toccato, a meno di svuotarlo apposta.
            !(mixedFields.contains(field) && (drafts[field] ?? "").isEmpty && !clearedFields.contains(field))
        }
        let values = drafts
        mutate(ids) { file in
            for field in fields { file[field] = values[field] ?? "" }
        }
        editedFields = []
        clearedFields = []
    }

    private func resetPanel() {
        editedFields = []
        clearedFields = []
    }

    func loadPanel() {
        let selected = selectedFiles
        var newDrafts: [TagField: String] = [:]
        var mixed: Set<TagField> = []
        for field in TagField.allCases {
            let values = Set(selected.map { $0[field] })
            if values.count > 1 {
                mixed.insert(field)
                newDrafts[field] = ""
            } else {
                newDrafts[field] = values.first ?? ""
            }
        }
        drafts = newDrafts
        mixedFields = mixed
        editedFields = []
        clearedFields = []
        loadCover(for: selected)
    }

    // MARK: - Copertine

    private func loadCover(for selected: [AudioFile]) {
        let token = UUID()
        coverRequest = token
        guard let first = selected.first else {
            showCover(nil)
            return
        }
        switch first.coverEdit {
        case .set(let data, _):
            showCover(data)
        case .remove:
            showCover(nil)
        case nil:
            guard first.hasCover else {
                showCover(nil)
                return
            }
            let url = first.url
            Task {
                let data = await Task.detached { TagLibIO.readCover(url) }.value
                guard self.coverRequest == token else { return }
                self.showCover(data)
            }
        }
    }

    private func showCover(_ data: Data?) {
        coverData = data
        guard let data, let image = NSImage(data: data) else {
            cover = nil
            coverDescription = data == nil ? "" : "Immagine non leggibile"
            return
        }
        cover = image
        let rep = image.representations.first
        let size = rep.map { "\($0.pixelsWide)×\($0.pixelsHigh)" } ?? ""
        let kind = Self.isPNG(data) ? "PNG" : "JPEG"
        coverDescription = "\(size) · \(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }

    func setCover(from url: URL) {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            errorMessage = "\(url.lastPathComponent) non è un'immagine valida."
            return
        }
        setCover(data: data, image: image)
    }

    func setCover(data: Data, image: NSImage) {
        guard !selection.isEmpty else { return }
        var bytes = data
        var mime = "image/jpeg"
        if Self.isPNG(data) {
            mime = "image/png"
        } else if !Self.isJPEG(data) {
            // HEIC, WebP, TIFF… vengono convertiti in JPEG, l'unico formato sicuro ovunque.
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            else {
                errorMessage = "Impossibile convertire l'immagine."
                return
            }
            bytes = jpeg
        }
        mutate(selection) { $0.coverEdit = .set(bytes, mime: mime) }
        loadCover(for: selectedFiles)
    }

    func removeCover() {
        mutate(selection) { file in
            file.coverEdit = file.hasCover ? .remove : nil
        }
        loadCover(for: selectedFiles)
    }

    func exportCover() {
        guard let data = coverData else { return }
        let panel = NSSavePanel()
        let base = selectedFiles.first?.album.isEmpty == false ? selectedFiles[0].album : "cover"
        panel.nameFieldStringValue = base.replacingOccurrences(of: "/", with: "-") + (Self.isPNG(data) ? ".png" : ".jpg")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func isPNG(_ data: Data) -> Bool { data.starts(with: [0x89, 0x50, 0x4E, 0x47]) }
    private static func isJPEG(_ data: Data) -> Bool { data.starts(with: [0xFF, 0xD8, 0xFF]) }

    // MARK: - Convertitori e azioni

    func present(_ sheet: ActiveSheet) {
        commitDrafts()
        activeSheet = sheet
    }

    func previewTagToFilename(_ pattern: String) -> [RenamePreview] {
        targetFiles.map { RenamePreview(id: $0.id, old: $0.filename, new: Patterns.filename(pattern, for: $0)) }
    }

    func applyTagToFilename(_ pattern: String) {
        let fm = FileManager.default
        var copy = files
        var renamed = 0
        var errors: [String] = []
        let targets = Set(targetFiles.map(\.id))
        for i in copy.indices where targets.contains(copy[i].id) {
            let file = copy[i]
            let relative = Patterns.filename(pattern, for: file)
            guard !relative.isEmpty else { continue }
            let destination = file.url.deletingLastPathComponent().appendingPathComponent(relative)
            guard destination.path != file.url.path else { continue }
            do {
                // Su APFS non sensibile alle maiuscole "a.mp3" → "A.mp3" è lo stesso file.
                if fm.fileExists(atPath: destination.path),
                   destination.path.lowercased() != file.url.path.lowercased() {
                    throw TagError("esiste già \(relative)")
                }
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: file.url, to: destination)
                copy[i].url = destination
                renamed += 1
            } catch {
                errors.append("\(file.filename): \(error.localizedDescription)")
            }
        }
        files = copy
        statusMessage = "\(renamed) file rinominati"
        if !errors.isEmpty {
            errorMessage = "\(errors.count) file non rinominati:\n" + errors.prefix(20).joined(separator: "\n")
        }
    }

    /// Calcola le modifiche di un'azione sui file di destinazione senza applicarle.
    func preview(_ transform: ([AudioFile]) -> [AudioFile]) -> [FieldChange] {
        let before = targetFiles
        let after = transform(before)
        var changes: [FieldChange] = []
        for (old, new) in zip(before, after) {
            for field in TagField.allCases where old[field] != new[field] {
                changes.append(FieldChange(filename: old.filename, field: field, old: old[field], new: new[field]))
            }
        }
        return changes
    }

    func apply(_ transform: ([AudioFile]) -> [AudioFile]) {
        let after = transform(targetFiles)
        let byID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        var changed = 0
        mutate(Set(byID.keys)) { file in
            guard let new = byID[file.id], new.tags != file.tags else { return }
            file.tags = new.tags
            changed += 1
        }
        loadPanel()
        statusMessage = "\(changed) file modificati (non ancora salvati)"
    }

    // MARK: - Fonti online

    /// Artista e album da cercare: dai tag, oppure (file senza tag) dai nomi delle cartelle
    /// secondo lo schema comune …/Artista/Album/brano.
    var lookupHint: (artist: String, album: String) {
        guard let first = targetFiles.first else { return ("", "") }
        let artist = first.albumArtist.isEmpty ? first.artist : first.albumArtist
        let folder = first.url.deletingLastPathComponent()
        return (
            artist.isEmpty ? folder.deletingLastPathComponent().lastPathComponent : artist,
            first.album.isEmpty ? folder.lastPathComponent : first.album
        )
    }

    func openWeb(_ site: WebLookup) {
        let hint = lookupHint
        let query = [hint.artist, hint.album].filter { !$0.isEmpty }.joined(separator: " ")
        if let url = site.url(for: query) { NSWorkspace.shared.open(url) }
    }

    static var picardURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.musicbrainz.Picard")
    }

    func openInPicard() {
        commitDrafts()
        guard let picard = Self.picardURL else {
            NSWorkspace.shared.open(URL(string: "https://picard.musicbrainz.org/")!)
            return
        }
        let targets = targetFiles
        guard !targets.isEmpty else { return }
        let dirty = targets.count { $0.isDirty }
        if dirty > 0, !confirm(
            "\(dirty) file hanno modifiche non salvate in Taggo.",
            detail: "Picard leggerà i file come sono ora sul disco. Salva prima con ⌘S se vuoi che le veda.",
            ok: "Apri comunque"
        ) { return }
        NSWorkspace.shared.open(targets.map(\.url), withApplicationAt: picard, configuration: NSWorkspace.OpenConfiguration())
        statusMessage = "\(targets.count) file aperti in Picard · dopo il salvataggio in Picard usa Ricarica (⌘R)"
    }

    /// Applica i valori arrivati da una fonte online (in sospeso fino a ⌘S).
    func applyTags(_ updates: [AudioFile.ID: [TagField: String]], cover: Data?) {
        let mime = cover.map { Self.isPNG($0) ? "image/png" : "image/jpeg" } ?? ""
        mutate(Set(updates.keys)) { file in
            for (field, value) in updates[file.id] ?? [:] { file[field] = value }
            if let cover { file.coverEdit = .set(cover, mime: mime) }
        }
        loadPanel()
        statusMessage = "\(updates.count) file aggiornati da MusicBrainz (non ancora salvati)"
    }

    private func mutate(_ ids: Set<AudioFile.ID>, _ body: (inout AudioFile) -> Void) {
        guard !ids.isEmpty else { return }
        var copy = files
        for i in copy.indices where ids.contains(copy[i].id) {
            body(&copy[i])
        }
        files = copy
    }
}

// MARK: - Trasformazioni

enum Transforms {
    static func filenameToTag(_ pattern: String) -> ([AudioFile]) -> [AudioFile] {
        { files in
            files.map { file in
                var file = file
                for (field, value) in Patterns.parse(pattern, file: file) ?? [:] { file[field] = value }
                return file
            }
        }
    }

    static func autonumber(start: Int, perFolder: Bool, withTotal: Bool) -> ([AudioFile]) -> [AudioFile] {
        { files in
            let groups = perFolder ? Dictionary(grouping: files.indices, by: { files[$0].folder }) : ["": Array(files.indices)]
            var result = files
            for indices in groups.values {
                for (n, i) in indices.enumerated() {
                    let number = start + n
                    result[i][.track] = withTotal ? "\(number)/\(start + indices.count - 1)" : "\(number)"
                }
            }
            return result
        }
    }

    static func changeCase(_ mode: CaseMode, fields: Set<TagField>) -> ([AudioFile]) -> [AudioFile] {
        { files in
            files.map { file in
                var file = file
                for field in fields { file[field] = mode.apply(file[field]) }
                return file
            }
        }
    }

    static func replace(_ replacement: Replacement, fields: Set<TagField>) -> ([AudioFile]) -> [AudioFile] {
        { files in
            files.map { file in
                var file = file
                for field in fields {
                    if let value = replacement.apply(file[field]) { file[field] = value }
                }
                return file
            }
        }
    }
}

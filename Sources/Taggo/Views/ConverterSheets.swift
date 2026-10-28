import SwiftUI

private let patternHelp = "Segnaposto: %title% %artist% %album% %albumartist% %year% %track% %discnumber% %genre% %composer% %comment%"

/// Struttura comune dei convertitori: controlli in alto, anteprima, pulsanti.
private struct SheetScaffold<Controls: View, Preview: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    let title: String
    let applyTitle: String
    let canApply: Bool
    let onApply: () -> Void
    @ViewBuilder let controls: Controls
    @ViewBuilder let preview: Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            Text(library.selection.isEmpty
                ? "Si applica a tutti i \(library.targetFiles.count) file visibili."
                : "Si applica ai \(library.targetFiles.count) file selezionati.")
                .foregroundStyle(.secondary)
            controls
            Text("Anteprima").font(.headline)
            preview
                .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(applyTitle) {
                    onApply()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
    }
}

private struct ChangesList: View {
    let changes: [FieldChange]

    var body: some View {
        if changes.isEmpty {
            ContentUnavailableView("Nessuna modifica", systemImage: "equal.circle")
        } else {
            Table(Array(changes.prefix(500))) {
                TableColumn("File", value: \.filename)
                TableColumn("Campo") { Text($0.field.label) }.width(90)
                TableColumn("Prima", value: \.old)
                TableColumn("Dopo") { Text($0.new).foregroundStyle(Color.accentColor) }
            }
        }
    }
}

struct TagToFilenameSheet: View {
    @Environment(Library.self) private var library
    @AppStorage("pattern.tagToFilename") private var pattern = "$num(%track%,2) - %title%"

    var body: some View {
        let previews = library.previewTagToFilename(pattern)
        let changed = previews.filter { $0.old != $0.new && !$0.new.isEmpty }
        SheetScaffold(title: "Tag → Nome file", applyTitle: "Rinomina \(changed.count) file", canApply: !changed.isEmpty) {
            library.applyTagToFilename(pattern)
        } controls: {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Formato", text: $pattern).textFieldStyle(.roundedBorder)
                Text(patternHelp + " %filename% %folder% · $num(%track%,2) per 01, 02… · / crea sottocartelle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } preview: {
            Table(Array(previews.prefix(500))) {
                TableColumn("Nome attuale", value: \.old)
                TableColumn("Nuovo nome") { item in
                    Text(item.new.isEmpty ? "(tag mancanti, ignorato)" : item.new)
                        .foregroundStyle(item.old == item.new ? Color.secondary : Color.accentColor)
                }
            }
        }
    }
}

struct FilenameToTagSheet: View {
    @Environment(Library.self) private var library
    @AppStorage("pattern.filenameToTag") private var pattern = "%track% - %artist% - %title%"

    var body: some View {
        let transform = Transforms.filenameToTag(pattern)
        let changes = library.preview(transform)
        let unmatched = library.targetFiles.count { Patterns.parse(pattern, file: $0) == nil }
        SheetScaffold(title: "Nome file → Tag", applyTitle: "Applica", canApply: !changes.isEmpty) {
            library.apply(transform)
        } controls: {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Formato", text: $pattern).textFieldStyle(.roundedBorder)
                Text(patternHelp + " · %dummy% ignora una parte · / per usare i nomi delle cartelle")
                    .font(.caption).foregroundStyle(.secondary)
                if unmatched > 0 {
                    Text("\(unmatched) nomi non corrispondono al formato e verranno saltati.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        } preview: {
            ChangesList(changes: changes)
        }
    }
}

struct AutonumberSheet: View {
    @Environment(Library.self) private var library
    @AppStorage("autonumber.start") private var start = 1
    @AppStorage("autonumber.perFolder") private var perFolder = true
    @AppStorage("autonumber.total") private var withTotal = false

    var body: some View {
        let transform = Transforms.autonumber(start: start, perFolder: perFolder, withTotal: withTotal)
        let changes = library.preview(transform)
        SheetScaffold(title: "Numerazione automatica", applyTitle: "Numera", canApply: !changes.isEmpty) {
            library.apply(transform)
        } controls: {
            VStack(alignment: .leading, spacing: 6) {
                Stepper("Inizia da \(start)", value: $start, in: 0...999)
                Toggle("Ricomincia per ogni cartella", isOn: $perFolder)
                Toggle("Aggiungi il totale (es. 3/12)", isOn: $withTotal)
                Text("I file vengono numerati nell'ordine in cui appaiono nella tabella.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } preview: {
            ChangesList(changes: changes)
        }
    }
}

private struct FieldPicker: View {
    @Binding var fields: Set<TagField>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 5)) {
            ForEach(TagField.allCases) { field in
                Toggle(field.label, isOn: Binding(
                    get: { fields.contains(field) },
                    set: { if $0 { fields.insert(field) } else { fields.remove(field) } }
                ))
            }
        }
    }
}

struct CaseSheet: View {
    @Environment(Library.self) private var library
    @State private var mode = CaseMode.title
    @State private var fields: Set<TagField> = [.title, .artist, .album, .albumArtist]

    var body: some View {
        let transform = Transforms.changeCase(mode, fields: fields)
        let changes = library.preview(transform)
        SheetScaffold(title: "Maiuscole/minuscole", applyTitle: "Applica", canApply: !changes.isEmpty) {
            library.apply(transform)
        } controls: {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Stile", selection: $mode) {
                    ForEach(CaseMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 320)
                FieldPicker(fields: $fields)
            }
        } preview: {
            ChangesList(changes: changes)
        }
    }
}

struct ReplaceSheet: View {
    @Environment(Library.self) private var library
    @State private var replacement = Replacement(find: "", replaceWith: "", useRegex: false, caseSensitive: false)
    @State private var fields: Set<TagField> = [.title]

    var body: some View {
        let invalid = replacement.useRegex && replacement.apply("") == nil
        let transform = Transforms.replace(replacement, fields: fields)
        let changes = invalid ? [] : library.preview(transform)
        SheetScaffold(title: "Sostituisci", applyTitle: "Sostituisci", canApply: !changes.isEmpty) {
            library.apply(transform)
        } controls: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Cerca", text: $replacement.find)
                    TextField("Sostituisci con", text: $replacement.replaceWith)
                }
                .textFieldStyle(.roundedBorder)
                HStack(spacing: 16) {
                    Toggle("Espressione regolare", isOn: $replacement.useRegex)
                    Toggle("Distingui maiuscole", isOn: $replacement.caseSensitive)
                    if invalid {
                        Text("Espressione non valida").foregroundStyle(.red)
                    } else if replacement.useRegex {
                        Text("Usa $1, $2… per i gruppi").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                FieldPicker(fields: $fields)
            }
        } preview: {
            ChangesList(changes: changes)
        }
    }
}

struct DiscSplitSheet: View {
    @Environment(Library.self) private var library
    @AppStorage("discSplit.mode") private var mode = DiscSplit.Mode.restart
    @AppStorage("discSplit.perDisc") private var perDisc = 10
    @AppStorage("discSplit.renumber") private var renumber = true
    @AppStorage("discSplit.totals") private var withTotals = true
    @AppStorage("discSplit.byAlbum") private var groupByAlbum = true
    @State private var pointsText = ""

    private var split: DiscSplit {
        DiscSplit(
            mode: mode,
            perDisc: perDisc,
            points: DiscSplit.parsePoints(pointsText),
            renumber: renumber,
            withTotals: withTotals,
            groupByAlbum: groupByAlbum
        )
    }

    var body: some View {
        let split = split
        let changes = library.preview(split.apply)
        let summary = split.summary(for: library.targetFiles)
        SheetScaffold(title: "Dividi in dischi", applyTitle: "Applica", canApply: !changes.isEmpty) {
            library.apply(split.apply)
        } controls: {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Nuovo disco", selection: $mode) {
                    ForEach(DiscSplit.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 420)
                Text(mode.help).font(.caption).foregroundStyle(.secondary)
                switch mode {
                case .count:
                    Stepper("\(perDisc) brani per disco", value: $perDisc, in: 1...999)
                case .points:
                    TextField("Primo brano di ogni disco successivo, es. 13, 25", text: $pointsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 420)
                default:
                    EmptyView()
                }
                HStack(spacing: 16) {
                    Toggle("Rinumera le tracce da 1 per disco", isOn: $renumber)
                    Toggle("Aggiungi i totali (1/2, 3/12)", isOn: $withTotals)
                    Toggle("Separa per album", isOn: $groupByAlbum)
                }
                Text(summary.map { "\($0.album): \($0.tracksPerDisc.count) dischi (\($0.tracksPerDisc.map(String.init).joined(separator: " + ")) brani)" }
                    .prefix(4).joined(separator: "\n"))
                    .font(.callout)
                Text("Dopo puoi spostare i file in cartelle per disco con Tag → Nome file, es. %album%/CD%discnumber%/$num(%track%,2) - %title%")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } preview: {
            ChangesList(changes: changes)
        }
    }
}

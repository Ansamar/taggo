import CTagLib
import Foundation

struct TagError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Lettura e scrittura dei tag tramite l'API C di TagLib.
enum TagLibIO {
    static let extensions: Set<String> = [
        "mp3", "mp2", "m4a", "m4b", "m4p", "mp4", "aac", "alac",
        "flac", "ogg", "oga", "opus", "spx",
        "wav", "aif", "aiff", "aifc",
        "ape", "wv", "mpc", "tta", "wma", "asf", "dsf", "dff",
    ]

    /// Trova ricorsivamente i file audio nelle cartelle (o tra i file) indicati.
    static func audioFiles(in urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                if extensions.contains(url.pathExtension.lowercased()) { result.append(url) }
                continue
            }
            let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let item = enumerator?.nextObject() as? URL {
                if extensions.contains(item.pathExtension.lowercased()) { result.append(item) }
            }
        }
        return result
    }

    static func read(_ url: URL) -> AudioFile? {
        guard let file = open(url) else { return nil }
        defer { taglib_file_free(file) }

        var tags: [TagField: String] = [:]
        for field in TagField.allCases {
            let value = values(file, field.key).joined(separator: "; ")
            if !value.isEmpty { tags[field] = value }
        }

        var audio = AudioFile(url: url, tags: tags)
        audio.hasCover = taggo_has_pictures(file) != 0
        if let props = taglib_file_audioproperties(file) {
            audio.duration = Int(taglib_audioproperties_length(props))
            audio.bitrate = Int(taglib_audioproperties_bitrate(props))
            audio.sampleRate = Int(taglib_audioproperties_samplerate(props))
            audio.channels = Int(taglib_audioproperties_channels(props))
        }
        return audio
    }

    static func readCover(_ url: URL) -> Data? {
        guard let file = open(url) else { return nil }
        defer { taglib_file_free(file) }
        var size: UInt32 = 0
        guard let bytes = taggo_copy_first_picture(file, &size), size > 0 else { return nil }
        return Data(bytesNoCopy: bytes, count: Int(size), deallocator: .free)
    }

    /// Scrive solo i campi modificati, così i valori multipli e i frame
    /// non gestiti dall'app restano intatti.
    static func write(_ audio: AudioFile) throws {
        guard let file = open(audio.url) else {
            throw TagError("impossibile aprire il file")
        }
        defer { taglib_file_free(file) }

        for field in audio.changedFields {
            let value = audio[field].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                taglib_property_set(file, field.key, nil)
            } else {
                taglib_property_set(file, field.key, value)
            }
        }

        switch audio.coverEdit {
        case .set(let data, let mime):
            let ok = data.withUnsafeBytes { buffer in
                taggo_set_front_cover(
                    file,
                    buffer.baseAddress?.assumingMemoryBound(to: CChar.self),
                    UInt32(buffer.count),
                    mime
                )
            }
            if ok == 0 { throw TagError("questo formato non supporta le copertine") }
        case .remove:
            _ = taggo_remove_pictures(file)
        case nil:
            break
        }

        guard taglib_file_save(file) != 0 else {
            throw TagError("salvataggio non riuscito (file in sola lettura?)")
        }
    }

    private static func open(_ url: URL) -> UnsafeMutablePointer<TagLib_File>? {
        guard let file = url.withUnsafeFileSystemRepresentation({ path in
            path.flatMap { taglib_file_new($0) }
        }) else { return nil }
        guard taglib_file_is_valid(file) != 0 else {
            taglib_file_free(file)
            return nil
        }
        return file
    }

    private static func values(_ file: UnsafeMutablePointer<TagLib_File>, _ key: String) -> [String] {
        guard let list = taglib_property_get(file, key) else { return [] }
        defer { taglib_property_free(list) }
        var result: [String] = []
        var i = 0
        while let item = list[i] {
            result.append(String(cString: item))
            i += 1
        }
        return result
    }
}

import Foundation
import Testing
@testable import Taggo

@Suite struct TagLibIOTests {
    /// Copia un file di prova in una cartella temporanea, per non toccare gli originali.
    func fixture(_ name: String) throws -> URL {
        let source = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    @Test(arguments: ["silence.mp3", "silence.flac", "silence.m4a", "silence.ogg"])
    func roundTrip(_ name: String) throws {
        let url = try fixture(name)
        var file = try #require(TagLibIO.read(url))
        #expect(file.tags.isEmpty)
        #expect(file.sampleRate == 44100)

        file[.title] = "Città d'estate"
        file[.artist] = "Ënnio Morricone"
        file[.track] = "3/12"
        file[.year] = "1966"
        let cover = try Data(contentsOf: try #require(Bundle.module.url(forResource: "cover", withExtension: "jpg", subdirectory: "Fixtures")))
        file.coverEdit = .set(cover, mime: "image/jpeg")
        try TagLibIO.write(file)

        let reread = try #require(TagLibIO.read(url))
        #expect(reread[.title] == "Città d'estate")
        #expect(reread[.artist] == "Ënnio Morricone")
        #expect(reread.trackNumber == 3)
        #expect(reread[.year] == "1966")
        #expect(reread.hasCover)
        #expect(TagLibIO.readCover(url) == cover)

        // Svuotare un campo e rimuovere la copertina.
        var edited = reread
        edited[.artist] = ""
        edited.coverEdit = .remove
        try TagLibIO.write(edited)
        let final = try #require(TagLibIO.read(url))
        #expect(final[.artist] == "")
        #expect(final[.title] == "Città d'estate")
        #expect(!final.hasCover)
    }
}

@Suite struct PatternTests {
    let file: AudioFile = {
        var f = AudioFile(url: URL(fileURLWithPath: "/Musica/Ennio Morricone/Il buono/07 - Ennio Morricone - L'estasi dell'oro.mp3"))
        f[.title] = "L'estasi dell'oro"
        f[.artist] = "Ennio Morricone"
        f[.album] = "Il buono, il brutto, il cattivo"
        f[.track] = "7/12"
        return f
    }()

    @Test func tagToFilename() {
        #expect(Patterns.filename("$num(%track%,2) - %title%", for: file) == "07 - L'estasi dell'oro.mp3")
        #expect(Patterns.filename("%artist%/%album%/%track% %title%", for: file)
            == "Ennio Morricone/Il buono, il brutto, il cattivo/7 L'estasi dell'oro.mp3")
        var slash = file
        slash[.title] = "A/B: C"
        #expect(Patterns.filename("%title%", for: slash) == "A-B- C.mp3")
        #expect(Patterns.filename("%genre%", for: file) == "")
    }

    @Test func filenameToTag() throws {
        let tags = try #require(Patterns.parse("%track% - %artist% - %title%", file: file))
        #expect(tags[.track] == "07")
        #expect(tags[.artist] == "Ennio Morricone")
        #expect(tags[.title] == "L'estasi dell'oro")

        let withFolders = try #require(Patterns.parse("%artist%/%album%/%track% - %dummy% - %title%", file: file))
        #expect(withFolders[.album] == "Il buono")
        #expect(withFolders[.artist] == "Ennio Morricone")
        #expect(Patterns.parse("%title% [%year%]", file: file) == nil)
    }

    @Test func autonumberPerFolder() {
        let files = ["/a/1.mp3", "/a/2.mp3", "/b/1.mp3"].map { AudioFile(url: URL(fileURLWithPath: $0)) }
        let result = Transforms.autonumber(start: 1, perFolder: true, withTotal: true)(files)
        #expect(result.map { $0[.track] } == ["1/2", "2/2", "1/1"])
    }

    @Test func caseAndReplace() {
        #expect(CaseMode.title.apply("the GOOD the bad") == "The Good The Bad")
        #expect(CaseMode.sentence.apply("the GOOD the bad") == "The good the bad")
        let r = Replacement(find: #"(\d+)-(\d+)"#, replaceWith: "$2-$1", useRegex: true, caseSensitive: false)
        #expect(r.apply("12-34") == "34-12")
        #expect(Replacement(find: "(", replaceWith: "", useRegex: true, caseSensitive: false).apply("x") == nil)
    }
}

@Suite struct DiscSplitTests {
    func files(_ specs: [(String, String, String)]) -> [AudioFile] {
        specs.map { path, album, track in
            var f = AudioFile(url: URL(fileURLWithPath: path))
            f[.album] = album
            f[.track] = track
            return f
        }
    }

    @Test func restartDetection() {
        let input = files([("/a/1.mp3", "X", "1"), ("/a/2.mp3", "X", "2"), ("/a/3.mp3", "X", "3"),
                           ("/a/4.mp3", "X", "1"), ("/a/5.mp3", "X", "2")])
        let out = DiscSplit(mode: .restart).apply(input)
        #expect(out.map { $0[.disc] } == ["1/2", "1/2", "1/2", "2/2", "2/2"])
        #expect(out.map { $0[.track] } == ["1/3", "2/3", "3/3", "1/2", "2/2"])
    }

    @Test func sequentialAlbumByCountAndPoints() {
        let input = files((1...5).map { ("/a/\($0).mp3", "X", "\($0)") })
        let byCount = DiscSplit(mode: .count, perDisc: 2, withTotals: false).apply(input)
        #expect(byCount.map { $0[.disc] } == ["1", "1", "2", "2", "3"])
        #expect(byCount.map { $0[.track] } == ["1", "2", "1", "2", "1"])
        let byPoints = DiscSplit(mode: .points, points: [4], renumber: false, withTotals: false).apply(input)
        #expect(byPoints.map { $0[.disc] } == ["1", "1", "1", "2", "2"])
        #expect(byPoints.map { $0[.track] } == ["1", "2", "3", "4", "5"])
    }

    @Test func foldersAndAlbums() {
        let input = files([("/X/CD2/1.mp3", "X", "1"), ("/X/CD1/1.mp3", "X", "1"), ("/X/CD1/2.mp3", "X", "2"),
                           ("/Y/1.mp3", "Y", "1")])
        let split = DiscSplit(mode: .folders, withTotals: false)
        #expect(split.discs(for: input) == [2, 1, 1, 1])
        #expect(split.summary(for: input).map(\.tracksPerDisc) == [[2, 1], [1]])
    }
}

@Suite struct MusicBrainzTests {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    @Test func decodesRealRelease() throws {
        let release = try JSONDecoder().decode(MusicBrainz.Release.self, from: try fixture("mb-release"))
        #expect(release.title == "Il buono, il brutto, il cattivo")
        #expect(release.artist == "Ennio Morricone")
        #expect(release.hasFrontCover)
        let tracks = MusicBrainz.flatten(release)
        #expect(tracks.count == 21)
        #expect(tracks[0].track == 1 && tracks[0].trackTotal == 21 && tracks[0].disc == 1 && tracks[0].discTotal == 1)
        #expect(tracks[0].seconds == 162)
    }

    @Test func decodesRealSearch() throws {
        struct Response: Decodable { let releases: [MusicBrainz.ReleaseSummary] }
        let results = try JSONDecoder().decode(Response.self, from: try fixture("mb-search")).releases
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { !$0.title.isEmpty && !$0.artist.isEmpty })
    }

    @Test func flattensMultiDisc() throws {
        let json = """
        {"id":"x","title":"Doppio","artist-credit":[{"name":"A","joinphrase":" & "},{"name":"B"}],
         "media":[{"position":1,"tracks":[{"position":1,"title":"Uno"},{"position":2,"title":"Due"}]},
                  {"position":2,"tracks":[{"position":1,"title":"Tre","artist-credit":[{"name":"C"}]}]}]}
        """
        let release = try JSONDecoder().decode(MusicBrainz.Release.self, from: Data(json.utf8))
        let tracks = MusicBrainz.flatten(release)
        #expect(release.artist == "A & B")
        #expect(tracks.map { "\($0.disc)/\($0.discTotal) \($0.track)/\($0.trackTotal) \($0.artist)" }
            == ["1/2 1/2 A & B", "1/2 2/2 A & B", "2/2 1/1 C"])
    }

    @Test func quotesSearchTerms() {
        #expect(MusicBrainz.quote(#"Say "Hi""#) == #""Say \"Hi\"""#)
    }
}

@Suite struct UntaggedFileTests {
    @Test func untaggedFileIsListedAndRenameIsSkipped() throws {
        let source = try #require(Bundle.module.url(forResource: "silence", withExtension: "mp3", subdirectory: "Fixtures"))
        let file = try #require(TagLibIO.read(source))
        #expect(file.tags.isEmpty)
        #expect(file.duration == 1)
        #expect(Patterns.filename("%artist% - %title%", for: file) == "")
        #expect(Patterns.filename("%title%", for: file) == "")
    }
}

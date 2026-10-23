import Foundation

/// File and folder names as the Music app creates them in its media folder: `NN Title.m4a` for single-disc
/// albums, `D-NN Title.m4a` for multi-disc albums, and `_` in place of `:` and `/`. Other rules of the Music
/// app, such as length limits, are unknown.
public enum Naming {
    /// Replaces the characters that the Music app replaces in path components.
    public static func component(_ text: String) -> String {
        text.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
    }

    public static func fileName(title: String, disc: Int, track: Int, discCount: Int, fileExtension: String = "m4a")
        -> String
    {
        let number = String(format: "%02d", track)
        let prefix = discCount > 1 ? "\(disc)-\(number)" : number
        return "\(prefix) \(component(title)).\(fileExtension)"
    }

    /// The path of a track relative to the media folder's music directory: album artist, album, and file.
    public static func relativePath(for track: ResolvedTrack, fileExtension: String = "m4a") -> [String]? {
        guard let artist = track.albumArtist, !artist.isEmpty else { return nil }
        return [
            component(artist), component(track.album),
            fileName(
                title: track.title, disc: track.reference.disc, track: track.reference.track,
                discCount: track.discCount, fileExtension: fileExtension),
        ]
    }
}

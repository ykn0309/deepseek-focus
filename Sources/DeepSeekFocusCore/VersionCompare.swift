import Foundation

/// Compares the dotted version strings used by GitHub release tags and
/// CFBundleShortVersionString. A leading "v" and any pre-release suffix are
/// ignored; the public "latest" release endpoint does not return prereleases.
public enum VersionCompare {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ raw: String) -> [Int] {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        // Stop at a pre-release/build suffix such as "-beta.1" or "+build".
        let numericPrefix = value.prefix { character in
            character.isNumber || character == "."
        }
        guard !numericPrefix.isEmpty else { return [] }
        return numericPrefix
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
    }
}

import Foundation
import Security

/// Resolves a "Publisher" for an executable or bundle from its code signature.
enum CodeSigning {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    nonisolated(unsafe) private static var pending: Set<String> = []
    private static let queue = DispatchQueue(label: "TaskManager.codesigning", qos: .utility)

    /// Returns the cached publisher, or nil if it hasn't been looked up yet.
    static func cachedPublisher(_ path: String?) -> String? {
        guard let path else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return cache[path]
    }

    /// Looks up any paths not seen before in the background and calls `completion` when done.
    static func prefetch(_ paths: some Sequence<String>, completion: @escaping @Sendable () -> Void) {
        lock.lock()
        let missing = paths.filter { cache[$0] == nil && !pending.contains($0) }
        pending.formUnion(missing)
        lock.unlock()
        guard !missing.isEmpty else { return }
        queue.async {
            var found: [String: String] = [:]
            for path in missing {
                found[path] = lookup(path)
            }
            lock.lock()
            cache.merge(found) { $1 }
            pending.subtract(missing)
            lock.unlock()
            completion()
        }
    }

    /// Synchronous lookup (cached). Call off the main thread.
    static func publisher(for path: String) -> String {
        if let cached = cachedPublisher(path) { return cached }
        let value = lookup(path)
        lock.lock()
        cache[path] = value
        lock.unlock()
        return value
    }

    private static func lookup(_ path: String) -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return "" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "" }
        if dict[kSecCodeInfoPlatformIdentifier as String] != nil { return "Apple Inc." }
        guard let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String? else { return "" }
        return clean(summary)
    }

    /// "Developer ID Application: Google LLC (EQHXZ8M8AV)" → "Google LLC"
    private static func clean(_ summary: String) -> String {
        switch summary {
        case "Software Signing", "Apple Code Signing Certification Authority": return "Apple Inc."
        case "Apple Mac OS Application Signing": return "Mac App Store"
        default: break
        }
        var name = summary
        if let colon = name.range(of: ": ") { name = String(name[colon.upperBound...]) }
        if name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) { name = String(name[..<open.lowerBound]) }
        return name
    }
}

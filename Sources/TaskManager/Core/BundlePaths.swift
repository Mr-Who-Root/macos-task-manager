import Foundation

enum BundlePaths {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: [String: String] = [:]

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper" → "/Applications/Google Chrome.app"
    static func outermostApp(_ path: String?) -> String? {
        guard let path else { return nil }
        if let range = path.range(of: ".app/") { return String(path[..<range.lowerBound]) + ".app" }
        return path.hasSuffix(".app") ? path : nil
    }

    /// The nearest enclosing .app, e.g. a helper app nested inside the main bundle.
    static func innermostApp(_ path: String?) -> String? {
        guard let path else { return nil }
        if let range = path.range(of: ".app/", options: .backwards) { return String(path[..<range.lowerBound]) + ".app" }
        return path.hasSuffix(".app") ? path : nil
    }

    static func displayName(_ bundlePath: String) -> String {
        lock.lock()
        if let cached = names[bundlePath] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let bundle = Bundle(path: bundlePath)
        let info = bundle?.localizedInfoDictionary ?? [:]
        let base = bundle?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (base["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? (base["CFBundleName"] as? String)
            ?? ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
        lock.lock()
        names[bundlePath] = name
        lock.unlock()
        return name
    }

    /// Paths that belong to the operating system rather than to third-party software.
    static func isSystem(_ path: String?) -> Bool {
        guard let path else { return true }
        if path.hasPrefix("/usr/local/") { return false }
        let prefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/", "/private/var/", "/Library/Developer/CommandLineTools/"]
        return prefixes.contains { path.hasPrefix($0) }
    }
}

import Foundation

class MediaCacheManager {
    static let shared = MediaCacheManager()
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let maxAgeInDays: Double = 7
    
    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("com.bbc-sounds.media-cache")
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cleanup()
    }
    
    func getCachedData(for url: URL) -> Data? {
        let fileURL = localURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        // Update modification date to implement LRU (optional, but keep it simple with 7-day expiry)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        
        return try? Data(contentsOf: fileURL)
    }
    
    func cacheData(_ data: Data, for url: URL) {
        let fileURL = localURL(for: url)
        let parentDir = fileURL.deletingLastPathComponent()
        
        try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
    
    func localURL(for url: URL) -> URL {
        // Create a stable local path based on the URL
        // We use the last two components of the path to keep it readable but distinct
        // e.g. .../iplayer/segments/12345.ts -> segments/12345.ts
        let pathComponents = url.pathComponents
        let fileName = pathComponents.last ?? "unnamed"
        let subDir = pathComponents.dropLast().last ?? "default"
        
        // Use a hash of the full URL for the parent directory to avoid collisions
        let hash = String(format: "%08x", url.absoluteString.hashValue)
        return cacheDirectory.appendingPathComponent(hash).appendingPathComponent(subDir).appendingPathComponent(fileName)
    }
    
    func cleanup() {
        let now = Date()
        let maxAge: TimeInterval = maxAgeInDays * 24 * 60 * 60
        
        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return }
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            if let modificationDate = resourceValues?.contentModificationDate {
                if now.timeIntervalSince(modificationDate) > maxAge {
                    try? fileManager.removeItem(at: fileURL)
                    print("🧹 Removed expired cache file: \(fileURL.lastPathComponent)")
                }
            }
        }
        
        // Also remove empty directories
        removeEmptyDirectories(at: cacheDirectory)
    }
    
    private func removeEmptyDirectories(at url: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for content in contents {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: content.path, isDirectory: &isDir), isDir.boolValue {
                removeEmptyDirectories(at: content)
                let remaining = try? fileManager.contentsOfDirectory(atPath: content.path)
                if remaining?.isEmpty ?? false {
                    try? fileManager.removeItem(at: content)
                }
            }
        }
    }
}

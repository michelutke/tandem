import Foundation
import GRDB

/// Opens the app's GRDB databases (SMS store E50-09, contacts cache E51-04) with the at-rest
/// posture of D-12: no app-level encryption (FileVault assumed), file mode 0600 on the database
/// and its `-wal`/`-shm` sidecars, excluded from backup, and
/// `completeUntilFirstUserAuthentication` file protection where the platform supports it.
public enum TandemDatabaseFactory {
    private static let directoryName = "Tandem"
    private static let sidecarSuffixes = ["", "-wal", "-shm"]
    private static let ownerReadWrite = 0o600
    private static let ownerOnlyDirectory = 0o700

    /// `Application Support/Tandem/<fileName>`; inside the sandbox container for the app.
    public static func defaultDatabaseURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Creates the parent directory and the file (mode 0600) when missing, opens a pool, runs
    /// `migrator`, then hardens the database and the sidecars that exist.
    public static func openPool(
        at url: URL,
        migrator: DatabaseMigrator,
        fileManager: FileManager = .default
    ) throws -> DatabasePool {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: ownerOnlyDirectory]
        )
        if !fileManager.fileExists(atPath: url.path) {
            let attributes: [FileAttributeKey: Any] = [.posixPermissions: ownerReadWrite]
            guard fileManager.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let pool = try DatabasePool(path: url.path)
        try migrator.migrate(pool)
        try harden(url, fileManager: fileManager)
        return pool
    }

    private static func harden(_ url: URL, fileManager: FileManager) throws {
        for suffix in sidecarSuffixes {
            let path = url.path + suffix
            guard fileManager.fileExists(atPath: path) else { continue }
            try fileManager.setAttributes([.posixPermissions: ownerReadWrite], ofItemAtPath: path)
            var fileURL = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try fileURL.setResourceValues(values)
            try? (fileURL as NSURL).setResourceValue(
                URLFileProtection.completeUntilFirstUserAuthentication,
                forKey: .fileProtectionKey
            )
        }
    }
}

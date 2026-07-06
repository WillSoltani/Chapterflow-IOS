import Foundation
import Observation
import CoreKit
import Persistence

// MARK: - Downloaded file summary

/// Metadata for a single downloaded book blob on disk.
public struct DownloadedFile: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let byteCount: Int64
    public let url: URL

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

// MARK: - SettingsModel

/// Drives the Settings tab.
///
/// Responsibilities:
/// - Load and write-through reading preferences (server + `AppPreferences`).
/// - Surface the user's email from the stored id_token JWT.
/// - Enumerate downloaded books from the local `FileStore`.
/// - Trigger data export and present a share sheet.
/// - Handle account deactivation / deletion (calls server, then signs out).
/// - Toggle the App Lock (Face ID) UserDefaults flag.
@Observable
@MainActor
public final class SettingsModel {

    // MARK: - Dependencies

    private let repository: any SettingsRepository
    let preferences: AppPreferences
    private let onSignOut: () async -> Void

    // MARK: - Async state

    public private(set) var isLoading = false
    public private(set) var error: AppError?

    // MARK: - Export

    public private(set) var exportData: Data?
    public var showShareSheet = false

    // MARK: - Danger zone

    public var showDeactivateConfirm = false
    public var showDeleteConfirm = false
    public private(set) var isDangerousOperationInProgress = false

    // MARK: - Downloads (new SwiftData-backed)

    /// Optional download-info provider (DownloadManager from LibraryFeature).
    /// When nil, falls back to the legacy file-scan approach.
    public let downloadInfoProvider: (any DownloadInfoProviding)?
    public let userId: String

    public private(set) var downloadedFiles: [DownloadedFile] = []
    public private(set) var totalDownloadBytes: Int64 = 0

    // MARK: - App Lock

    public var appLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "appLockEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "appLockEnabled") }
    }

    // MARK: - Debounce

    @ObservationIgnored private var patchTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        repository: any SettingsRepository,
        preferences: AppPreferences,
        onSignOut: @escaping () async -> Void,
        downloadInfoProvider: (any DownloadInfoProviding)? = nil,
        userId: String = ""
    ) {
        self.repository = repository
        self.preferences = preferences
        self.onSignOut = onSignOut
        self.downloadInfoProvider = downloadInfoProvider
        self.userId = userId
    }

    // MARK: - Lifecycle

    /// Loads server reading settings and syncs them into `AppPreferences`.
    /// Also refreshes the downloads inventory.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        await loadReadingSettings()
        await loadDownloads()
    }

    private func loadReadingSettings() async {
        do {
            guard let remote = try await repository.getReadingSettings() else { return }
            // Sync remote values into local preferences (server is authoritative on first load).
            if let raw = remote.defaultDepth, let v = DepthVariant(rawValue: raw) {
                preferences.depthVariant = v
            }
            if let raw = remote.readingTone, let t = ReadingTone(rawValue: raw) {
                preferences.readingTone = t
            }
            if let scale = remote.fontScale {
                preferences.readerFontScale = max(0.8, min(1.8, scale))
            }
            if let speed = remote.audioSpeed {
                preferences.audioSpeed = max(0.5, min(3.0, speed))
            }
        } catch {
            // Non-fatal: local prefs remain valid if the server call fails.
        }
    }

    // MARK: - Reading preference write-through

    /// Called whenever a reading preference changes. Immediately updates
    /// `AppPreferences` (write-through) then debounces a server PATCH.
    public func readingPreferencesDidChange() {
        patchTask?.cancel()
        patchTask = Task { [weak self] in
            guard let self else { return }
            // 800 ms debounce — accumulates rapid picker changes.
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled else { return }
            let patch = UserReadingSettings(
                defaultDepth: preferences.depthVariant.rawValue,
                readingTone: preferences.readingTone.rawValue,
                fontScale: preferences.readerFontScale,
                audioSpeed: preferences.audioSpeed
            )
            try? await repository.patchReadingSettings(patch)
        }
    }

    // MARK: - Downloads

    private func loadDownloads() async {
        if let provider = downloadInfoProvider, !userId.isEmpty {
            // SwiftData-backed inventory
            let books = await provider.downloadedBooks(userId: userId)
            let total = await provider.totalUsedBytes(userId: userId)
            downloadedFiles = books.map {
                DownloadedFile(
                    id: $0.bookId,
                    displayName: $0.title,
                    byteCount: $0.totalBytes,
                    url: URL(filePath: $0.bookId)   // URL not used for deletion; provider handles it
                )
            }.sorted { $0.displayName < $1.displayName }
            totalDownloadBytes = total
            return
        }
        // Legacy file-scan fallback (pre-P3.2 data)
        guard let store = try? FileStore.applicationSupport(subdirectory: "Downloads") else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: store.root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }

        var files: [DownloadedFile] = []
        var total: Int64 = 0
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            let name = url.deletingPathExtension().lastPathComponent
            files.append(DownloadedFile(
                id: url.lastPathComponent,
                displayName: name,
                byteCount: size,
                url: url
            ))
            total += size
        }
        downloadedFiles = files.sorted { $0.displayName < $1.displayName }
        totalDownloadBytes = total
    }

    /// Deletes a single downloaded book (SwiftData path) or file (legacy path).
    public func deleteDownload(_ file: DownloadedFile) {
        if let provider = downloadInfoProvider, !userId.isEmpty {
            let bid = file.id
            let uid = userId
            Task {
                try? await provider.deleteBookDownload(bookId: bid, userId: uid)
                downloadedFiles.removeAll { $0.id == bid }
                totalDownloadBytes = await provider.totalUsedBytes(userId: uid)
            }
            return
        }
        try? FileManager.default.removeItem(at: file.url)
        downloadedFiles.removeAll { $0.id == file.id }
        totalDownloadBytes -= file.byteCount
    }

    /// Deletes all downloaded books.
    public func deleteAllDownloads() {
        if let provider = downloadInfoProvider, !userId.isEmpty {
            let uid = userId
            Task {
                try? await provider.deleteAllBookDownloads(userId: uid)
                downloadedFiles = []
                totalDownloadBytes = 0
            }
            return
        }
        for file in downloadedFiles {
            try? FileManager.default.removeItem(at: file.url)
        }
        downloadedFiles = []
        totalDownloadBytes = 0
    }

    // MARK: - Export

    /// Fetches the data export and triggers the share sheet.
    public func requestExport() async {
        guard !isDangerousOperationInProgress else { return }
        isDangerousOperationInProgress = true
        defer { isDangerousOperationInProgress = false }
        error = nil
        do {
            exportData = try await repository.exportData()
            showShareSheet = true
        } catch let appErr as AppError {
            error = appErr
        } catch {
            self.error = .offline
        }
    }

    // MARK: - Deactivate

    public func confirmDeactivate() async {
        guard !isDangerousOperationInProgress else { return }
        isDangerousOperationInProgress = true
        defer { isDangerousOperationInProgress = false }
        error = nil
        do {
            try await repository.deactivateAccount()
            await onSignOut()
        } catch let appErr as AppError {
            error = appErr
        } catch {
            self.error = .offline
        }
    }

    // MARK: - Delete

    public func confirmDelete() async {
        guard !isDangerousOperationInProgress else { return }
        isDangerousOperationInProgress = true
        defer { isDangerousOperationInProgress = false }
        error = nil
        do {
            try await repository.deleteAccount()
            await onSignOut()
        } catch let appErr as AppError {
            error = appErr
        } catch {
            self.error = .offline
        }
    }

    // MARK: - Sign out

    public func signOut() async {
        await onSignOut()
    }
}

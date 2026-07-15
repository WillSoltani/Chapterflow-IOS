import Foundation
import Observation
import AuthKit
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
    private let workPermit: SessionWorkPermit

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
    /// When nil, download inventory remains unavailable. Accountless legacy
    /// storage is intentionally neither scanned nor mutated in this lifecycle.
    public let downloadInfoProvider: (any DownloadInfoProviding)?
    public let accountContext: AccountContext

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
        accountContext: AccountContext,
        workPermit: SessionWorkPermit = SessionWorkPermit()
    ) {
        self.repository = repository
        self.preferences = preferences
        self.onSignOut = onSignOut
        self.downloadInfoProvider = downloadInfoProvider
        self.accountContext = accountContext
        self.workPermit = workPermit
    }

    // MARK: - Lifecycle

    /// Loads server reading settings and syncs them into `AppPreferences`.
    /// Also refreshes the downloads inventory.
    public func load() async {
        guard let ticket = try? workPermit.begin() else { return }
        try? workPermit.commit(ticket) {
            isLoading = true
            error = nil
        }
        defer {
            try? workPermit.commit(ticket) {
                isLoading = false
            }
        }
        await loadReadingSettings(ticket: ticket)
        await loadDownloads(ticket: ticket)
    }

    private func loadReadingSettings(ticket: UInt64) async {
        do {
            guard let remote = try await repository.getReadingSettings() else { return }
            try workPermit.commit(ticket) {
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
            }
        } catch is CancellationError {
            return
        } catch {
            // Non-fatal: local prefs remain valid if the server call fails.
        }
    }

    // MARK: - Reading preference write-through

    /// Called whenever a reading preference changes. Immediately updates
    /// `AppPreferences` (write-through) then debounces a server PATCH.
    public func readingPreferencesDidChange() {
        patchTask?.cancel()
        guard let ticket = try? workPermit.begin() else { return }
        patchTask = Task { [weak self] in
            guard let self else { return }
            // 800 ms debounce — accumulates rapid picker changes.
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled else { return }
            guard (try? self.workPermit.validate(ticket)) != nil else { return }
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

    private func loadDownloads(ticket: UInt64) async {
        guard let provider = downloadInfoProvider else {
            try? workPermit.commit(ticket) {
                downloadedFiles = []
                totalDownloadBytes = 0
            }
            return
        }

        let accountID = accountContext.accountID
        let books = await provider.downloadedBooks(userId: accountID)
        let total = await provider.totalUsedBytes(userId: accountID)
        try? workPermit.commit(ticket) {
            downloadedFiles = books.map {
                DownloadedFile(
                    id: $0.bookId,
                    displayName: $0.title,
                    byteCount: $0.totalBytes,
                    url: URL(filePath: $0.bookId)   // URL not used for deletion; provider handles it
                )
            }.sorted { $0.displayName < $1.displayName }
            totalDownloadBytes = total
        }
    }

    /// Deletes a single downloaded book through the account-scoped provider.
    public func deleteDownload(_ file: DownloadedFile) {
        guard let provider = downloadInfoProvider else { return }
        guard let ticket = try? workPermit.begin() else { return }
        let bookID = file.id
        let accountID = accountContext.accountID
        Task {
            try? await provider.deleteBookDownload(bookId: bookID, userId: accountID)
            let total = await provider.totalUsedBytes(userId: accountID)
            try? workPermit.commit(ticket) {
                downloadedFiles.removeAll { $0.id == bookID }
                totalDownloadBytes = total
            }
        }
    }

    /// Deletes all downloaded books.
    public func deleteAllDownloads() {
        guard let provider = downloadInfoProvider else { return }
        guard let ticket = try? workPermit.begin() else { return }
        let accountID = accountContext.accountID
        Task {
            try? await provider.deleteAllBookDownloads(userId: accountID)
            try? workPermit.commit(ticket) {
                downloadedFiles = []
                totalDownloadBytes = 0
            }
        }
    }

    // MARK: - Export

    /// Fetches the data export and triggers the share sheet.
    public func requestExport() async {
        guard !isDangerousOperationInProgress else { return }
        guard let ticket = try? workPermit.begin() else { return }
        try? workPermit.commit(ticket) {
            isDangerousOperationInProgress = true
            error = nil
        }
        defer {
            try? workPermit.commit(ticket) {
                isDangerousOperationInProgress = false
            }
        }
        do {
            let data = try await repository.exportData()
            try workPermit.commit(ticket) {
                exportData = data
                showShareSheet = true
            }
        } catch is CancellationError {
            return
        } catch let appErr as AppError {
            try? workPermit.commit(ticket) {
                error = appErr
            }
        } catch {
            try? workPermit.commit(ticket) {
                self.error = .offline
            }
        }
    }

    // MARK: - Deactivate

    public func confirmDeactivate() async {
        guard !isDangerousOperationInProgress else { return }
        guard let ticket = try? workPermit.begin() else { return }
        try? workPermit.commit(ticket) {
            isDangerousOperationInProgress = true
            error = nil
        }
        defer {
            try? workPermit.commit(ticket) {
                isDangerousOperationInProgress = false
            }
        }
        do {
            try await repository.deactivateAccount()
            try workPermit.validate(ticket)
            await onSignOut()
        } catch is CancellationError {
            return
        } catch let appErr as AppError {
            try? workPermit.commit(ticket) {
                error = appErr
            }
        } catch {
            try? workPermit.commit(ticket) {
                self.error = .offline
            }
        }
    }

    // MARK: - Delete

    public func confirmDelete() async {
        guard !isDangerousOperationInProgress else { return }
        guard let ticket = try? workPermit.begin() else { return }
        try? workPermit.commit(ticket) {
            isDangerousOperationInProgress = true
            error = nil
        }
        defer {
            try? workPermit.commit(ticket) {
                isDangerousOperationInProgress = false
            }
        }
        do {
            try await repository.deleteAccount()
            try workPermit.validate(ticket)
            await onSignOut()
        } catch is CancellationError {
            return
        } catch let appErr as AppError {
            try? workPermit.commit(ticket) {
                error = appErr
            }
        } catch {
            try? workPermit.commit(ticket) {
                self.error = .offline
            }
        }
    }

    // MARK: - Sign out

    public func signOut() async {
        await onSignOut()
    }
}

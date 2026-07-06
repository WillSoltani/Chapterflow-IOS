import SwiftUI
import DesignSystem
import CoreKit
import Persistence

/// The full "Downloads" settings screen.
///
/// Shows downloaded books with per-book sizes, allows deletion, displays total
/// usage vs. the configured cap, and provides the Wi-Fi-only toggle.
public struct DownloadsSettingsView: View {

    @State private var model: DownloadsSettingsModel

    public init(
        downloadInfo: (any DownloadInfoProviding)?,
        preferences: AppPreferences,
        userId: String
    ) {
        _model = State(initialValue: DownloadsSettingsModel(
            downloadInfo: downloadInfo,
            preferences: preferences,
            userId: userId
        ))
    }

    public var body: some View {
        Form {
            preferencesSection
            storageSection
            booksSection
        }
        .navigationTitle("Downloads")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await model.load() }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section {
            Toggle(isOn: $model.downloadOverWifiOnly) {
                Label("Download over Wi-Fi only", systemImage: "wifi")
                    .foregroundStyle(Color.cfLabel)
            }
            .tint(Color.cfAccent)
            .accessibilityLabel("Download over Wi-Fi only")

            Picker("Storage limit", selection: $model.storageLimitGB) {
                Text("1 GB").tag(1.0)
                Text("3 GB").tag(3.0)
                Text("5 GB").tag(5.0)
                Text("10 GB").tag(10.0)
                Text("Unlimited").tag(0.0)
            }
        } header: {
            Text("Preferences")
        }
    }

    // MARK: - Storage usage

    private var storageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: .cfSpacing8) {
                HStack {
                    Text("Used")
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfLabel)
                    Spacer()
                    Text(model.formattedUsedBytes)
                        .font(.cfSubheadline)
                        .foregroundStyle(Color.cfSecondaryLabel)
                    if model.storageLimitGB > 0 {
                        Text("/ \(model.formattedLimitBytes)")
                            .font(.cfCaption)
                            .foregroundStyle(Color.cfTertiaryLabel)
                    }
                }
                if model.storageLimitGB > 0 && model.usageFraction > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: .cfRadius4)
                                .fill(Color.cfSecondaryFill)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: .cfRadius4)
                                .fill(model.usageFraction > 0.9 ? Color.orange : Color.cfAccent)
                                .frame(width: geo.size.width * CGFloat(min(model.usageFraction, 1)), height: 6)
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                }
            }
            .padding(.vertical, .cfSpacing4)
        } header: {
            Text("Storage")
        }
    }

    // MARK: - Downloaded books

    @ViewBuilder
    private var booksSection: some View {
        Section {
            if model.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if model.books.isEmpty {
                Text("No downloaded books")
                    .foregroundStyle(Color.cfSecondaryLabel)
                    .font(.cfSubheadline)
                    .accessibilityLabel("No downloaded books stored on device")
            } else {
                ForEach(model.books) { book in
                    HStack {
                        VStack(alignment: .leading, spacing: .cfSpacing4) {
                            Text(book.title)
                                .font(.cfSubheadline)
                                .foregroundStyle(Color.cfLabel)
                            Text(book.formattedSize)
                                .font(.cfCaption)
                                .foregroundStyle(Color.cfSecondaryLabel)
                        }
                        Spacer()
                        Button {
                            Task { await model.deleteBook(book) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(book.title)")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(book.title), \(book.formattedSize)")
                }

                if model.books.count > 1 {
                    Button(role: .destructive) {
                        Task { await model.deleteAll() }
                    } label: {
                        Label("Delete All Downloads", systemImage: "trash")
                    }
                    .accessibilityLabel("Delete all downloaded books")
                }
            }
        } header: {
            Text("Downloaded Books")
        } footer: {
            if !model.books.isEmpty {
                Text("Total: \(model.formattedUsedBytes)")
            }
        }
    }
}

// MARK: - Model

@Observable
@MainActor
final class DownloadsSettingsModel {

    private let downloadInfo: (any DownloadInfoProviding)?
    private let preferences: AppPreferences
    private let userId: String

    private(set) var books: [DownloadedBookInfo] = []
    private(set) var totalBytes: Int64 = 0
    private(set) var isLoading = false

    var downloadOverWifiOnly: Bool {
        get { preferences.downloadOverWifiOnly }
        set { preferences.downloadOverWifiOnly = newValue }
    }

    var storageLimitGB: Double {
        get { preferences.downloadStorageLimitGB }
        set { preferences.downloadStorageLimitGB = newValue }
    }

    var formattedUsedBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var formattedLimitBytes: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(storageLimitGB * 1_073_741_824),
            countStyle: .file
        )
    }

    var usageFraction: Double {
        guard storageLimitGB > 0 else { return 0 }
        let limit = storageLimitGB * 1_073_741_824
        return Double(totalBytes) / limit
    }

    init(
        downloadInfo: (any DownloadInfoProviding)?,
        preferences: AppPreferences,
        userId: String
    ) {
        self.downloadInfo = downloadInfo
        self.preferences = preferences
        self.userId = userId
    }

    func load() async {
        guard let info = downloadInfo else { return }
        isLoading = true
        defer { isLoading = false }
        async let booksFetch = info.downloadedBooks(userId: userId)
        async let bytesFetch = info.totalUsedBytes(userId: userId)
        let (fetchedBooks, fetchedBytes) = await (booksFetch, bytesFetch)
        books = fetchedBooks.sorted { $0.title < $1.title }
        totalBytes = fetchedBytes
    }

    func deleteBook(_ book: DownloadedBookInfo) async {
        guard let info = downloadInfo else { return }
        try? await info.deleteBookDownload(bookId: book.bookId, userId: userId)
        books.removeAll { $0.bookId == book.bookId }
        totalBytes = await info.totalUsedBytes(userId: userId)
    }

    func deleteAll() async {
        guard let info = downloadInfo else { return }
        try? await info.deleteAllBookDownloads(userId: userId)
        books = []
        totalBytes = 0
    }
}

// MARK: - Previews

#Preview("Downloads Settings") {
    NavigationStack {
        DownloadsSettingsView(
            downloadInfo: nil,
            preferences: AppPreferences(defaults: UserDefaults(suiteName: "preview.downloads")!),
            userId: "preview-user"
        )
    }
}

#Preview("Downloads Settings — Dark") {
    NavigationStack {
        DownloadsSettingsView(
            downloadInfo: nil,
            preferences: AppPreferences(defaults: UserDefaults(suiteName: "preview.downloads.dark")!),
            userId: "preview-user"
        )
    }
    .preferredColorScheme(.dark)
}

import SwiftUI
import Models
import DesignSystem
import Observation

/// Renders public remote artwork over the book's generated fallback when available.
///
/// The design is an emoji centred on a vertical gradient derived from the
/// `cover.color` hex string. Falls back to a neutral DesignSystem fill when
/// the cover data is absent or the hex cannot be parsed.
public struct BookCoverView: View {

    let cover: Cover?
    let coverImageURL: String?
    let size: CGFloat
    private let artworkLoader: any BookArtworkLoading

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkState: BookArtworkViewState

    public init(cover: Cover?, coverImageURL: String? = nil, size: CGFloat = 56) {
        self.cover = cover
        self.coverImageURL = coverImageURL
        self.size = size
        artworkLoader = BookArtworkLoader.shared
        _artworkState = State(initialValue: BookArtworkViewState())
    }

    init(
        cover: Cover?,
        coverImageURL: String?,
        size: CGFloat,
        artworkLoader: any BookArtworkLoading,
        artworkState: BookArtworkViewState = BookArtworkViewState()
    ) {
        self.cover = cover
        self.coverImageURL = coverImageURL
        self.size = size
        self.artworkLoader = artworkLoader
        _artworkState = State(initialValue: artworkState)
    }

    public var body: some View {
        ZStack {
            fallback

            if let image = artworkState.image(for: request) {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .frame(width: size, height: size * coverAspect)
                    .clipped()
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size * coverAspect)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: artworkState.image(for: request) != nil
        )
        .task(id: request) {
            await artworkState.load(request: request, using: artworkLoader)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Derived

    private var cornerRadius: CGFloat {
        switch size {
        case ..<40: return .cfRadius8
        case 40..<80: return .cfRadius12
        default: return .cfRadius16
        }
    }

    private var coverAspect: CGFloat { 1.4 }

    private var request: BookArtworkRequest? {
        guard let coverImageURL else { return nil }
        return BookArtworkRequest(
            rawURL: coverImageURL,
            pixelWidth: Int(ceil(size * displayScale)),
            pixelHeight: Int(ceil(size * coverAspect * displayScale))
        )
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(gradient)
            Text(cover?.emoji ?? "📖")
                .font(.system(size: size * 0.45))
                .minimumScaleFactor(0.5)
        }
    }

    private var gradient: LinearGradient {
        let base = parseHex(cover?.color) ?? Color.cfSecondaryFill
        return LinearGradient(
            colors: [base.opacity(0.95), base.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func parseHex(_ hex: String?) -> Color? {
        guard let hex else { return nil }
        let clean = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return nil }
        return Color(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

struct BookArtworkRequest: Hashable, Sendable {
    let rawURL: String
    let pixelWidth: Int
    let pixelHeight: Int

    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }
}

@MainActor
@Observable
final class BookArtworkViewState {
    private(set) var image: CGImage?
    private(set) var publishedRequest: BookArtworkRequest?
    private var generation = 0

    func image(for request: BookArtworkRequest?) -> CGImage? {
        guard publishedRequest == request else { return nil }
        return image
    }

    func load(request: BookArtworkRequest?, using loader: any BookArtworkLoading) async {
        generation += 1
        let loadGeneration = generation
        image = nil
        publishedRequest = nil

        guard let request else { return }
        let loadedImage = await loader.image(for: request.rawURL, pixelSize: request.pixelSize)
        guard !Task.isCancelled, generation == loadGeneration else { return }

        image = loadedImage
        publishedRequest = loadedImage == nil ? nil : request
    }

    func seed(image: CGImage, for request: BookArtworkRequest) {
        generation += 1
        self.image = image
        publishedRequest = request
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Cover sizes", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        BookCoverView(cover: PreviewData.atomicHabits.cover, size: 40)
        BookCoverView(cover: PreviewData.deepWork.cover, size: 56)
        BookCoverView(cover: PreviewData.thinkingFastAndSlow.cover, size: 72)
        BookCoverView(cover: nil, size: 56)
    }
    .padding()
}

#Preview("Dark mode", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        BookCoverView(cover: PreviewData.atomicHabits.cover, size: 56)
        BookCoverView(cover: PreviewData.deepWork.cover, size: 56)
    }
    .padding()
    .preferredColorScheme(.dark)
}
#endif

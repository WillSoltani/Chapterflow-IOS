import SwiftUI
import DesignSystem

/// Placeholder skeleton shown while the dashboard is loading.
struct DashboardSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: .cfSpacing24) {
                statCardsSkeleton
                chartSkeleton(title: "Daily Reading Activity", height: 140)
                chartSkeleton(title: "Chapters Progress", height: 200)
                chartSkeleton(title: "Reading Goal", height: 120)
                chartSkeleton(title: "Books Overview", height: 140)
            }
            .padding(.cfSpacing16)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Loading dashboard…")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var statCardsSkeleton: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: .cfSpacing12
        ) {
            ForEach(0..<4, id: \.self) { _ in
                CFCard {
                    VStack(alignment: .leading, spacing: .cfSpacing8) {
                        CFSkeleton(Circle()).frame(width: 20, height: 20)
                        CFSkeleton().frame(height: 28).frame(maxWidth: 60)
                        CFSkeleton().frame(height: 12).frame(maxWidth: 80)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func chartSkeleton(title: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: .cfSpacing12) {
            CFSkeleton().frame(height: 16).frame(maxWidth: 160)
            CFCard {
                CFSkeleton().frame(height: height)
            }
        }
    }
}

#Preview("DashboardSkeleton") {
    DashboardSkeletonView()
        .background(Color.cfGroupedBackground)
}

import SwiftUI

struct ReleaseNotesSheetView: View {
    let entry: ReleaseNotesEntry
    let dismissAction: () -> Void
    @ScaledMetric(relativeTo: .headline) private var iconColumnSize: CGFloat = 24

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(entry.highlights) { highlight in
                            highlightRow(highlight)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) {
                continueButton
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(.background)
            }
            .background(.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        Text("release_notes_sheet_title")
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightRow(_ highlight: ReleaseNotesHighlight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: highlight.iconName)
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: iconColumnSize, height: iconColumnSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(highlight.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var continueButton: some View {
        Button(action: dismissAction) {
            Text("release_notes_continue_button")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.orange, in: Capsule())
    }
}

import SwiftUI
import NaturalLanguage
#if canImport(Translation)
@preconcurrency import Translation
#endif

// MARK: - About / Description Section

struct PlaceDescriptionSection: View {
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("business_description_section", comment: "Section header for business description"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface {
                TranslatableBusinessDescriptionView(description: description)
            }
        }
    }
}

private struct TranslatableBusinessDescriptionView: View {
    let description: String

    @State private var detectedLanguageCode: String?
    @State private var translatedDescription: String?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSuccessfulTranslation: Bool {
        guard let translatedDescription else { return false }
        return !translatedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var preferredLanguageCode: String? {
        guard let preferredIdentifier = Locale.preferredLanguages.first else { return nil }
        return normalizedLanguageCode(preferredIdentifier)
    }

    private var sourceLanguage: Locale.Language? {
        guard let detectedLanguageCode else { return nil }
        return Locale.Language(identifier: detectedLanguageCode)
    }

    private var targetLanguage: Locale.Language? {
        guard let preferredLanguageCode else { return nil }
        return Locale.Language(identifier: preferredLanguageCode)
    }

    private var shouldOfferTranslation: Bool {
        guard let detectedLanguageCode, let preferredLanguageCode else { return false }
        return normalizedLanguageCode(detectedLanguageCode) != preferredLanguageCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(3)

            if let translatedDescription, !translatedDescription.isEmpty {
                Text(translatedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
            }

            if shouldOfferTranslation && !hasSuccessfulTranslation {
                Button(action: startTranslation) {
                    Label("Translate", systemImage: "translate")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.tactilePress(scale: 0.96))
                .padding(.vertical, -8)
            }

            if hasSuccessfulTranslation {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Translated on device with Apple Translate")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .transition(.opacity)
            }

            if let translationError, !translationError.isEmpty {
                Text(translationError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: description) {
            if description.count >= 20 {
                detectedLanguageCode = NLLanguageRecognizer.dominantLanguage(for: description)?.rawValue
            } else {
                detectedLanguageCode = nil
            }
        }
        .translationTask(translationConfiguration) { session in
            do {
                let response = try await session.translate(description)
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion)
                    ) {
                        translatedDescription = response.targetText
                        translationError = nil
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)
                    ) {
                        translationError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func startTranslation() {
        guard let sourceLanguage, let targetLanguage else { return }
        BitLocalHaptics.selection()
        translationError = nil
        translationConfiguration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
        )
    }

    private func normalizedLanguageCode(_ identifier: String) -> String {
        let normalized = identifier.replacing("_", with: "-").lowercased()
        return normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
    }
}

// MARK: - Community Reviews Row & List View

struct PlaceReviewsRow: View {
    let element: Element
    let count: Int

    var body: some View {
        NavigationLink(value: BitLocalNavigationRoute.placeComments(element)) {
            PlaceGroupedSurface(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Community Reviews")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("^[\(count) review](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 36)
            }
        }
        .buttonStyle(.tactileRow(cornerRadius: 16))
    }
}

struct BTCMapPlaceCommentsListView: View {
    let element: Element

    @State private var comments: [V4PlaceCommentRecord] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var hasLoaded = false

    private let repository: BTCMapRepositoryProtocol = BTCMapRepository.shared

    var body: some View {
        List {
            if isLoading && comments.isEmpty {
                HStack {
                    ProgressView()
                    Text("Loading comments…")
                        .foregroundStyle(.secondary)
                }
            } else if let errorText, !errorText.isEmpty, comments.isEmpty {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                Button("Retry") {
                    BitLocalHaptics.lightTap()
                    loadComments(force: true)
                }
            } else if comments.isEmpty {
                Text("No reviews yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Community Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: element.id) {
            loadComments()
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: V4PlaceCommentRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let author = comment.authorDisplayName {
                    Text(author)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else {
                    Text("Anonymous")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let createdAt = comment.createdAt, !createdAt.isEmpty {
                    Text(createdAt.formattedBTCMapDate())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !comment.bodyText.isEmpty {
                TranslatableReviewBodyTextView(text: comment.bodyText)
            }

            if let sats = comment.amountSats, sats > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text(String(format: NSLocalizedString("~%lld sats", comment: "Approximate sats amount label"), sats))
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func loadComments(force: Bool = false) {
        guard !isLoading else { return }
        if hasLoaded && !force { return }

        isLoading = true
        errorText = nil

        repository.fetchPlaceComments(placeID: element.id) { result in
            Task { @MainActor in
                isLoading = false
                hasLoaded = true
                switch result {
                case .success(let comments):
                    self.comments = comments
                        .filter { !$0.bodyText.isEmpty }
                        .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
    }
}

private struct TranslatableReviewBodyTextView: View {
    let text: String

    @State private var detectedLanguageCode: String?
    @State private var translatedText: String?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSuccessfulTranslation: Bool {
        guard let translatedText else { return false }
        return !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var preferredLanguageCode: String? {
        guard let preferredIdentifier = Locale.preferredLanguages.first else { return nil }
        return normalizedLanguageCode(preferredIdentifier)
    }

    private var sourceLanguage: Locale.Language? {
        guard let detectedLanguageCode else { return nil }
        return Locale.Language(identifier: detectedLanguageCode)
    }

    private var targetLanguage: Locale.Language? {
        guard let preferredLanguageCode else { return nil }
        return Locale.Language(identifier: preferredLanguageCode)
    }

    private var shouldOfferTranslation: Bool {
        guard let detectedLanguageCode, let preferredLanguageCode else { return false }
        return normalizedLanguageCode(detectedLanguageCode) != preferredLanguageCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)

            if let translatedText, !translatedText.isEmpty {
                Text(translatedText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
            }

            if shouldOfferTranslation && !hasSuccessfulTranslation {
                Button(action: startTranslation) {
                    Label("Translate", systemImage: "translate")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.tactilePress(scale: 0.96))
                .padding(.vertical, -8)
            }

            if hasSuccessfulTranslation {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Translated on device with Apple Translate")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .transition(.opacity)
            }

            if let translationError, !translationError.isEmpty {
                Text(translationError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: text) {
            if text.count >= 20 {
                detectedLanguageCode = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
            } else {
                detectedLanguageCode = nil
            }
        }
        .translationTask(translationConfiguration) { session in
            do {
                let response = try await session.translate(text)
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion)
                    ) {
                        translatedText = response.targetText
                        translationError = nil
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)
                    ) {
                        translationError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func startTranslation() {
        guard let sourceLanguage, let targetLanguage else { return }
        BitLocalHaptics.selection()
        translationError = nil
        translationConfiguration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
        )
    }

    private func normalizedLanguageCode(_ identifier: String) -> String {
        let normalized = identifier.replacing("_", with: "-").lowercased()
        return normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
    }
}

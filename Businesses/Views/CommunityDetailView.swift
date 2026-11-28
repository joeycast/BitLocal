import SwiftUI
import Foundation
import UIKit
import MapKit

struct CommunityDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.openURL) var openURL
    @Environment(ContentViewModel.self) var viewModel
    private let metadataStore = CommunityRowMetadataObservableStore.shared
    let area: V2AreaRecord
    @Binding var currentDetent: PresentationDetent?
    @AppStorage("community.lastLightningWalletID") var lastLightningWalletID: String = ""
    @State private var isHeroScrolledPast = false
    @State private var showLightningAlert = false
    @State private var showWalletAlert = false
    @State private var showTipsDisclaimerAlert = false
    @State private var shareItem: ShareTextItem?
    @State var linkOpenErrorItem: CommunityLinkOpenError?
    @State var lightningErrorMessage: String?
    @State var memberElements: [Element] = []
    @State private var showOnMapTask: Task<Void, Never>?

    init(area: V2AreaRecord, currentDetent: Binding<PresentationDetent?> = .constant(nil)) {
        self.area = area
        self._currentDetent = currentDetent
    }

    var body: some View {
        detailWithTipAlerts
            .sheet(item: $shareItem) { item in
                ActivityView(items: item.items)
            }
            .alert("Unable to Open Wallet", isPresented: Binding(
                get: { lightningErrorMessage != nil },
                set: { newValue in
                    if !newValue { lightningErrorMessage = nil }
                })
            ) {
            } message: {
                Text(lightningErrorMessage ?? "")
            }
            .alert("Unable to Open", isPresented: Binding(
                get: { linkOpenErrorItem != nil },
                set: { newValue in
                    if !newValue { linkOpenErrorItem = nil }
                })
            ) {
                if let copyValue = linkOpenErrorItem?.copyValue {
                    Button(String(localized: "Copy \("npub")", comment: "Button title to copy a value label")) {
                        UIPasteboard.general.string = copyValue
                        BitLocalHaptics.success()
                    }
                }
                Button("OK") {}
            } message: {
                Text(linkOpenErrorItem?.message ?? "")
            }
    }

    private var detailWithTipAlerts: some View {
        detailWithChromeAndLifecycle
            .alert("Tip This Community", isPresented: $showLightningAlert) {
                if let lastWallet = knownWallets.first(where: { $0.id == lastLightningWalletID }),
                   let payload = payableLightningPayload {
                    Button(String(localized: "Copy and Open \(lastWallet.name)", comment: "Button title to copy a value and open the selected wallet")) {
                        openWallet(lastWallet, payload: payload)
                    }
                }
                Button("Choose Wallet") {
                    showWalletAlert = true
                }
                if let payload = payableLightningPayload {
                    Button("Copy Lightning Address") {
                        UIPasteboard.general.string = payload
                        BitLocalHaptics.success()
                    }
                    Button("Share") {
                        shareItem = ShareTextItem(text: payload)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose a wallet or copy the Lightning address to tip this community.")
            }
            .alert("Choose Wallet", isPresented: $showWalletAlert) {
                if let payload = payableLightningPayload {
                    ForEach(walletsForPicker) { wallet in
                        Button(wallet.name) {
                            openWallet(wallet, payload: payload)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose your Lightning wallet. BitLocal will copy the Lightning address, then open the wallet.")
            }
            .alert("Tipping Disclaimer", isPresented: $showTipsDisclaimerAlert) {
            } message: {
                Text("BitLocal does not process, custody, or guarantee tip transactions. We only open your selected wallet or link and help copy/share the Lightning address.")
            }
    }

    private var detailWithChromeAndLifecycle: some View {
        scrollContent
            // Only observes live height while collapsed-like; expanded detail is free of drag churn.
            .sheetCollapsedReveal(
                geometry: viewModel.sheetGeometry,
                isCollapsedLike: isCollapsedLikeDetent
            )
            .navigationTitle((isHeroScrolledPast || isCollapsedLikeDetent) ? area.displayName : "")
            .navigationBarTitleDisplayMode(.inline)
            .bitLocalDetailNavigationChrome()
            .toolbar {
                if BottomSheetDetents.isFullScreen(currentDetent) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            BitLocalHaptics.lightTap()
                            withAnimation(BitLocalMotion.animation(BitLocalMotion.disclosureSpring, reduceMotion: reduceMotion)) {
                                currentDetent = BottomSheetDetents.standard
                            }
                            showOnMapTask?.cancel()
                            showOnMapTask = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(80))
                                guard !Task.isCancelled else { return }
                                viewModel.showCommunityOnMap(area)
                            }
                        } label: {
                            Label("Show on Map", systemImage: "map")
                        }
                    }
                }
                if isHeroScrolledPast, let shareableURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            BitLocalHaptics.lightTap()
                            shareItem = ShareTextItem(items: [area.displayName, shareableURL])
                        } label: {
                            Label("Share community", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onDisappear {
                showOnMapTask?.cancel()
                showOnMapTask = nil
            }
            .task(id: area.id) {
                if viewModel.selectedCommunityArea?.id != area.id || viewModel.communityMemberElements.isEmpty {
                    viewModel.selectCommunity(area, presentDetail: false)
                }
                updateMemberElements()
            }
            .onChange(of: area.id) { _, _ in
                updateMemberElements()
            }
            .onChange(of: viewModel.selectedCommunityArea?.id) { _, _ in
                updateMemberElements()
            }
            .onChange(of: viewModel.communityMemberElements) { _, _ in
                updateMemberElements()
            }
            .onAppear {
                updateMemberElements()
            }
    }

    private var scrollContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    heroHeader(scrollProxy: scrollProxy)

                    quickActionBar

                    detailsSurface

                    if let descriptionText {
                        descriptionSection(descriptionText)
                    }

                    if let payload = payableLightningPayload {
                        tippingSection(payload: payload)
                    } else if let tipFallbackURL {
                        tipFallbackSection(url: tipFallbackURL)
                    }

                    merchantsSection

                    verificationSection
                        .id("community-verification-section")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 56
            } action: { _, scrolledPast in
                guard isHeroScrolledPast != scrolledPast else { return }
                withAnimation(BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)) {
                    isHeroScrolledPast = scrolledPast
                }
            }
        }
    }

    // MARK: - Hero Header & Quick Actions

    @ViewBuilder
    private func heroHeader(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                communityHeroIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(area.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let metadataLine = heroMetadataLine {
                        Text(metadataLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Quiet inline verification status (tappable to jump to verification section)
            Button {
                BitLocalHaptics.selection()
                withAnimation(BitLocalMotion.animation(BitLocalMotion.disclosureSpring, reduceMotion: reduceMotion)) {
                    scrollProxy.scrollTo("community-verification-section", anchor: .center)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: heroVerificationIcon)
                        .font(.caption.weight(.semibold))
                    Text(heroVerificationTitle)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(heroVerificationTint)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactilePress(scale: 0.96))
            .padding(.vertical, -8)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var communityHeroIcon: some View {
        if let communityIconURL {
            CommunityIconImage(url: communityIconURL, placeholderSystemName: "person.3.fill", scaleToFill: true)
                .frame(width: 48, height: 48)
                .background(
                    BitLocalSheetSurface.fillColor(
                        for: .card,
                        colorScheme: colorScheme,
                        contrast: colorSchemeContrast
                    ),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            BitLocalSheetSurface.borderColor(
                                for: .card,
                                colorScheme: colorScheme,
                                contrast: colorSchemeContrast
                            ),
                            lineWidth: 0.5
                        )
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: "person.3.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color("MarkerColor"), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                }
                .accessibilityHidden(true)
        }
    }

    private var resolvedMerchantCount: Int? {
        if sameSelectedCommunity && !viewModel.communityMembersIsLoading {
            return memberElements.count
        }
        if !memberElements.isEmpty {
            return memberElements.count
        }
        return metadataStore.metadataByAreaID[area.id]?.merchantCount
    }

    private var heroMetadataLine: String? {
        guard let count = resolvedMerchantCount else { return nil }
        return String(AttributedString(localized: "^[\(count) merchant](inflect: true)").characters)
    }

    private var heroVerificationIcon: String {
        verificationStatus?.icon ?? "questionmark.circle"
    }

    private var heroVerificationTitle: String {
        verificationStatus?.title ?? String(localized: "Unverified", comment: "Fallback status label when a community has no verification date")
    }

    private var heroVerificationTint: Color {
        verificationStatus?.tint ?? .secondary
    }

    @ViewBuilder
    private var quickActionBar: some View {
        let hasTip = hasTipAction
        let websiteURL = primaryWebsiteURL
        let shareURL = shareableURL
        if hasTip || websiteURL != nil || shareURL != nil {
            HStack(spacing: 8) {
                if hasTip {
                    quickActionButton(
                        title: LocalizedStringKey("Tip"),
                        systemImage: "bolt.fill",
                        isPrimary: true
                    ) {
                        BitLocalHaptics.lightTap()
                        if payableLightningPayload != nil {
                            showLightningAlert = true
                        } else if let tipFallbackURL {
                            openURL(tipFallbackURL)
                        }
                    }

                    if let websiteURL {
                        quickActionButton(
                            title: LocalizedStringKey("Website"),
                            systemImage: "safari.fill",
                            isPrimary: false
                        ) {
                            BitLocalHaptics.lightTap()
                            openURL(websiteURL)
                        }
                    }
                } else if let websiteURL {
                    quickActionButton(
                        title: LocalizedStringKey("Website"),
                        systemImage: "safari.fill",
                        isPrimary: true
                    ) {
                        BitLocalHaptics.lightTap()
                        openURL(websiteURL)
                    }
                }

                if let shareURL {
                    quickActionButton(
                        title: LocalizedStringKey("Share"),
                        systemImage: "square.and.arrow.up",
                        isPrimary: false
                    ) {
                        BitLocalHaptics.lightTap()
                        shareItem = ShareTextItem(items: [area.displayName, shareURL])
                    }
                }
            }
        }
    }

    private func quickActionButton(
        title: LocalizedStringKey,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isPrimary ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            BitLocalSheetSurface.fillColor(
                                for: .control,
                                colorScheme: colorScheme,
                                contrast: colorSchemeContrast
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isPrimary
                            ? Color.clear
                            : BitLocalSheetSurface.borderColor(
                                for: .control,
                                colorScheme: colorScheme,
                                contrast: colorSchemeContrast
                            ),
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.tactilePress(scale: 0.96))
    }

    // MARK: - Consolidated Details & Socials Surface

    @ViewBuilder
    private var detailsSurface: some View {
        let contacts = contactInformationLinks
        let socials = socialLinks
        if !contacts.isEmpty || !socials.isEmpty {
            PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 10)) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(contacts.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            detailsRowDivider
                        }
                        communityContactRow(item)
                    }

                    if !socials.isEmpty {
                        if !contacts.isEmpty {
                            detailsRowDivider
                        }
                        communitySocialsRow(socials)
                    }
                }
            }
        }
    }

    private var detailsRowDivider: some View {
        Divider()
            .padding(.leading, 32)
            .padding(.trailing, 4)
    }

    @ViewBuilder
    private func communityContactRow(_ item: CommunitySocialLink) -> some View {
        let copyTitle = String(
            localized: "Copy \(item.label)",
            comment: "Context menu title to copy a labeled value"
        )
        HStack(alignment: .center, spacing: 4) {
            if item.isInteractive {
                Button {
                    BitLocalHaptics.lightTap()
                    openCommunityLink(item)
                } label: {
                    contactRowLabel(item)
                }
                .buttonStyle(.tactileRow(cornerRadius: 10))
                .copyValueContextMenu(item.value, title: copyTitle)
            } else {
                contactRowLabel(item)
                    .copyValueContextMenu(item.value, title: copyTitle)
            }

            if !item.value.isEmpty {
                TactileCopyButton(value: item.value, accessibilityLabel: copyTitle)
            }
        }
    }

    private func contactRowLabel(_ item: CommunitySocialLink) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func communitySocialsRow(_ socials: [CommunitySocialLink]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "at")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                Text("Socials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                BitLocalFlowLayout(horizontalSpacing: 14, verticalSpacing: 0) {
                    ForEach(socials) { social in
                        communitySocialLink(social)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func communitySocialLink(_ social: CommunitySocialLink) -> some View {
        let copyTitle = String(
            localized: "Copy \(social.label)",
            comment: "Context menu title to copy a labeled value"
        )
        let content = HStack(spacing: 5) {
            if let icon = social.icon {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
            }
            Text(social.displayLabel)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(social.isInteractive ? Color.accentColor : Color.primary)
        .frame(minWidth: social.icon == nil ? 28 : nil, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(social.label)

        if social.isInteractive {
            Button {
                BitLocalHaptics.lightTap()
                openCommunityLink(social)
            } label: {
                content
            }
            .buttonStyle(.tactilePress(scale: 0.96))
            .copyValueContextMenu(social.value, title: copyTitle)
        } else {
            content
                .copyValueContextMenu(social.value, title: copyTitle)
        }
    }

    // MARK: - Description Section

    private var descriptionText: String? {
        guard let raw = area.tags?["description"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Tipping Section

    private func tippingSection(payload: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tips")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 6)) {
                HStack(alignment: .center, spacing: 0) {
                    Button {
                        BitLocalHaptics.lightTap()
                        showLightningAlert = true
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bolt.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tip This Community")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(payload)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactileRow(cornerRadius: 10))
                    .copyValueContextMenu(
                        payload,
                        title: String(localized: "Copy Lightning Address", comment: "Context menu title to copy a community Lightning address")
                    )

                    Button {
                        BitLocalHaptics.selection()
                        showTipsDisclaimerAlert = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactilePress(scale: 0.92))
                    .accessibilityLabel("Tipping disclaimer")

                    TactileCopyButton(
                        value: payload,
                        accessibilityLabel: String(localized: "Copy Lightning Address", comment: "VoiceOver label for copying a community Lightning address")
                    )
                }
            }
        }
    }

    private func tipFallbackSection(url: URL) -> some View {
        let displayHost = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        return VStack(alignment: .leading, spacing: 6) {
            Text("Tips")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 10)) {
                HStack(alignment: .center, spacing: 4) {
                    Button {
                        BitLocalHaptics.lightTap()
                        openURL(url)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "heart")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Support This Community")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(displayHost)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactileRow(cornerRadius: 10))
                    .copyValueContextMenu(
                        url.absoluteString,
                        title: String(localized: "Copy Support Link", comment: "Context menu title to copy a community support URL")
                    )

                    TactileCopyButton(
                        value: url.absoluteString,
                        accessibilityLabel: String(localized: "Copy Support Link", comment: "VoiceOver label for copying a community support URL")
                    )
                }
            }
        }
    }

    // MARK: - Merchants Section

    private var merchantsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Merchants")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.communityMembersIsLoading || !memberElements.isEmpty {
                    Text("\(memberElements.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 4)

            if viewModel.communityMembersIsLoading && sameSelectedCommunity {
                PlaceGroupedSurface {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading merchants…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = viewModel.communityMembersError, !error.isEmpty, sameSelectedCommunity {
                PlaceGroupedSurface {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if memberElements.isEmpty {
                PlaceGroupedSurface {
                    Text("No merchants found for this community")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(memberElements.enumerated()), id: \.element.id) { index, element in
                            VStack(alignment: .leading, spacing: 0) {
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                                NavigationLink(value: BitLocalNavigationRoute.place(element)) {
                                    HStack(alignment: .center, spacing: 8) {
                                        ElementCell(viewModel: cellViewModel(for: element))
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.tactileRow(cornerRadius: 10))
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        viewModel.setMerchantDetailSequence(memberElements)
                                        viewModel.setSelectionSource(.list)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Verification Section

    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verification")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                if let verificationStatus {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: verificationStatus.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(verificationStatus.tint)
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(verificationStatus.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(verificationStatus.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(verificationStatus.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Not Yet Verified")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("No verification date is available for this community.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

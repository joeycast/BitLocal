import SwiftUI

// MARK: - Verification & Boost Footer Section

struct PlaceTrustAndBoostSection: View {
    let element: Element
    let verificationState: PlaceVerificationState
    @Environment(\.openURL) private var openURL

    private var btcMapMerchantURL: URL? {
        BTCMapMerchantURLBuilder.makeURL(for: element)
    }

    private var openStreetMapURL: URL? {
        guard let raw = element.v4Metadata?.osmURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    private var hasActionRows: Bool {
        btcMapMerchantURL != nil || openStreetMapURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verification")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface(padding: EdgeInsets(top: 12, leading: 14, bottom: 6, trailing: 14)) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        if verificationState == .loading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: verificationState.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(verificationState.tint)
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 1)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(verificationState.detailTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            if let dateText = verificationState.formattedDate {
                                Text(
                                    String(
                                        localized: "Last verified: \(dateText)",
                                        comment: "Verification status date label"
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            } else if verificationState == .unverified {
                                Text("No one has confirmed this location yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(verificationState.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.bottom, hasActionRows ? 10 : 6)

                    if let btcMapMerchantURL {
                        insetDivider
                        externalActionRow(
                            icon: "checkmark.seal",
                            iconTint: .accentColor,
                            title: "Verify or Update on BTC Map",
                            subtitle: "Confirm bitcoin acceptance or report changes",
                            url: btcMapMerchantURL
                        )
                    }

                    if let openStreetMapURL {
                        insetDivider
                        externalActionRow(
                            icon: "map",
                            iconTint: .secondary,
                            title: "Edit on OpenStreetMap",
                            subtitle: "Update hours, address, or tags",
                            url: openStreetMapURL
                        )
                    }

                    if let btcMapMerchantURL {
                        insetDivider
                        externalActionRow(
                            icon: "star.fill",
                            iconTint: .orange,
                            title: "Boost on BTC Map",
                            subtitle: "Feature This Merchant",
                            url: btcMapMerchantURL
                        )
                    }
                }
            }

            if btcMapMerchantURL != nil {
                Text("Opening the link above will direct you to btcmap.org where you can boost this merchant. Boosted merchants are featured on BitLocal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var insetDivider: some View {
        Divider()
            .padding(.leading, 32)
    }

    private func externalActionRow(
        icon: String,
        iconTint: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        url: URL
    ) -> some View {
        Button {
            BitLocalHaptics.lightTap()
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(iconTint)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.tactileRow(cornerRadius: 10))
    }
}

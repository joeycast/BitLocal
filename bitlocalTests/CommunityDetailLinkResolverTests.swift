import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.formatting))
struct CommunityDetailLinkResolverTests {

    @Test("Payable Lightning payload normalization accepts BOLT11, BOLT12, LNURL, and LUD-16")
    func payableLightningPayloads() {
        #expect(
            CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: "tips@bitlocal.app")
                == "tips@bitlocal.app"
        )
        #expect(
            CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: "lightning:tips@bitlocal.app")
                == "tips@bitlocal.app"
        )
        #expect(
            CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: "LIGHTNING:lnurl1dp68gurn8ghj7mrw")
                == "lnurl1dp68gurn8ghj7mrw"
        )
        #expect(
            CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: "lno1pg257enxv4ezqcneype82um50ynhxgrwdajx283qfwdpl28qqmc78ha")
                == "lno1pg257enxv4ezqcneype82um50ynhxgrwdajx283qfwdpl28qqmc78ha"
        )
        #expect(
            CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: "lnbc10u1p3xnhl2pp5...")
                == "lnbc10u1p3xnhl2pp5..."
        )

        // Plain web URLs and malformed addresses are not wallet-payable Lightning payloads.
        #expect(CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: "https://geyser.fund/project/bitlocal") == nil)
        #expect(CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: "user@localhost") == nil)
        #expect(CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: "   ") == nil)
    }

    @Test("Non-payable tip URL fallback handles HTTPS links, bare domains, and Lightning address fallback")
    func nonPayableTipFallbackURLs() {
        #expect(
            CommunityDetailLinkResolver.nonPayableTipURL(from: "https://geyser.fund/project/test")?.absoluteString
                == "https://geyser.fund/project/test"
        )
        #expect(
            CommunityDetailLinkResolver.nonPayableTipURL(from: "geyser.fund/project/test")?.absoluteString
                == "https://geyser.fund/project/test"
        )
        #expect(
            CommunityDetailLinkResolver.nonPayableTipURL(from: "tips@community.org")?.absoluteString
                == "https://community.org/tips"
        )
        #expect(CommunityDetailLinkResolver.nonPayableTipURL(from: "  ") == nil)
    }

    @Test("Nostr link targets distinguish web URLs from nostr app deep links")
    func nostrLinkTargetResolution() {
        #expect(
            CommunityDetailLinkResolver.nostrLinkTarget(for: "npub1example123")
                == .appPreferred(appURL: URL(string: "nostr:npub1example123")!)
        )
        #expect(
            CommunityDetailLinkResolver.nostrLinkTarget(for: "nostr:npub1example123")
                == .appPreferred(appURL: URL(string: "nostr:npub1example123")!)
        )
        #expect(
            CommunityDetailLinkResolver.nostrLinkTarget(for: "https://njump.me/npub1example123")
                == .web(URL(string: "https://njump.me/npub1example123")!)
        )
        #expect(CommunityDetailLinkResolver.nostrLinkTarget(for: "nostr:   ") == nil)
        #expect(CommunityDetailLinkResolver.nostrLinkTarget(for: "") == nil)
    }

    @Test("Contact URLs and BTC Map community links normalize schemes and handles")
    func contactAndBTCMapURLResolution() {
        #expect(
            CommunityDetailLinkResolver.resolvedContactURL(forKey: "contact:email", value: "hi@bitlocal.app")?.absoluteString
                == "mailto:hi@bitlocal.app"
        )
        #expect(
            CommunityDetailLinkResolver.resolvedContactURL(forKey: "contact:phone", value: "+15551234567")?.absoluteString
                == "tel:+15551234567"
        )
        #expect(
            CommunityDetailLinkResolver.resolvedContactURL(forKey: "contact:github", value: "@joeycast")?.absoluteString
                == "https://github.com/joeycast"
        )
        #expect(
            CommunityDetailLinkResolver.resolvedContactURL(forKey: "contact:discord", value: "abc123")?.absoluteString
                == "https://discord.gg/abc123"
        )
        #expect(
            CommunityDetailLinkResolver.resolvedContactURL(forKey: "contact:matrix", value: "#bitcoin:matrix.org")?.absoluteString
                == "https://matrix.to/#/#bitcoin:matrix.org"
        )
        #expect(
            CommunityDetailLinkResolver.resolvedContactURL(forKey: "contact:website", value: "bitlocal.app")?.absoluteString
                == "https://bitlocal.app"
        )

        #expect(
            CommunityDetailLinkResolver.btcMapCommunityURL(areaID: "123", urlAlias: "bitcoin-austin")?.absoluteString
                == "https://btcmap.org/community/bitcoin-austin"
        )
        #expect(
            CommunityDetailLinkResolver.btcMapCommunityURL(areaID: "bitcoin-lake", urlAlias: nil)?.absoluteString
                == "https://btcmap.org/community/bitcoin-lake"
        )
    }
}

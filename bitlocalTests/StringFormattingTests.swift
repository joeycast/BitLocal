import XCTest
@testable import bitlocal

final class WebsiteCleaningTests: XCTestCase {
    func testKeepsURLsThatAlreadyHaveAScheme() {
        XCTAssertEqual("https://example.com/menu".cleanedWebsiteURL()?.absoluteString, "https://example.com/menu")
        XCTAssertEqual("http://example.com".cleanedWebsiteURL()?.absoluteString, "http://example.com")
    }

    func testAddsHTTPSWhenSchemeIsMissing() {
        XCTAssertEqual("example.com".cleanedWebsiteURL()?.absoluteString, "https://example.com")
        XCTAssertEqual("  www.example.com/path  ".cleanedWebsiteURL()?.absoluteString, "https://www.example.com/path")
    }

    func testCollapsesDuplicatedSchemes() {
        XCTAssertEqual("https://http://example.com".cleanedWebsiteURL()?.absoluteString, "https://example.com")
        XCTAssertEqual("http://https://example.com".cleanedWebsiteURL()?.absoluteString, "https://example.com")
    }

    func testRejectsOSMTagContaminationAndJunk() {
        let junk = [
            "",
            "   ",
            "currency:XBT=yes",
            "payment:lightning",
            "addr:street=Main",
            "bitcoin=yes",
            "example.com\nother.com",
            "example.com\tother",
            "https://example.com/" + String(repeating: "a", count: 200)
        ]

        for value in junk {
            XCTAssertNil(value.cleanedWebsiteURL(), "Expected nil for '\(value)'")
        }
    }

    func testCleanedForDisplayStripsSchemeWWWAndTrailingSlashes() {
        XCTAssertEqual("https://www.example.com/".cleanedForDisplay(), "example.com")
        XCTAssertEqual("HTTP://WWW.Example.com/menu//".cleanedForDisplay(), "Example.com/menu")
        XCTAssertEqual("  example.com  ".cleanedForDisplay(), "example.com")
        XCTAssertEqual("shop.example.com/www.page".cleanedForDisplay(), "shop.example.com/www.page")
    }
}

final class PhoneNumberCleaningTests: XCTestCase {
    func testStripsCommonSeparators() {
        let result = " +1 (555) 123-4567 ".cleanedPhoneNumber()

        XCTAssertEqual(result.cleaned, "+15551234567")
        XCTAssertTrue(result.isValid)
    }

    func testDotSeparatedNumbersAreValid() {
        let result = "020.7123.4567".cleanedPhoneNumber()

        XCTAssertEqual(result.cleaned, "02071234567")
        XCTAssertTrue(result.isValid)
    }

    func testRejectsTooShortOrTooLongNumbers() {
        XCTAssertFalse("123".cleanedPhoneNumber().isValid)
        XCTAssertTrue("1234".cleanedPhoneNumber().isValid)
        XCTAssertTrue(String(repeating: "1", count: 20).cleanedPhoneNumber().isValid)
        XCTAssertFalse(String(repeating: "1", count: 21).cleanedPhoneNumber().isValid)
    }

    func testRejectsJunkThatIsNotAPhoneNumber() {
        let junk = [
            "",
            "call us",
            "currency:XBT=yes",
            "https://example.com/1234",
            "www.12345678.com",
            "info@1234.com",
            "ext1234abcd"
        ]

        for value in junk {
            XCTAssertFalse(value.cleanedPhoneNumber().isValid, "Expected invalid for '\(value)'")
        }
    }

    func testDisplayablePhoneNumberTrimsAndTightensCountryCode() {
        XCTAssertEqual("  +44 20 7123 4567  ".displayablePhoneNumber(), "+44 20 7123 4567")
        XCTAssertEqual("+ 1 555 123 4567".displayablePhoneNumber(), "+1 555 123 4567")
        XCTAssertEqual("   ".displayablePhoneNumber(), "   ")
    }
}

final class AddressFormattingTests: XCTestCase {
    func testSingleLineUSAddressReadsNaturally() throws {
        let address = Address(
            streetNumber: "21",
            streetName: "Main Street",
            cityOrTownName: "Austin",
            postalCode: "78701",
            regionOrStateName: "TX",
            countryName: "United States",
            isoCountryCode: "US"
        )

        let line = try XCTUnwrap(address.formatted(.singleLine))

        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("21 Main Street"), line)
        XCTAssertTrue(line.contains("Austin, TX 78701"), line)
        XCTAssertFalse(line.contains("United States"), line)
    }

    func testFullStyleIncludesCountryAndCompactDoesNot() throws {
        let address = Address(
            streetNumber: "21",
            streetName: "Main Street",
            cityOrTownName: "Austin",
            postalCode: "78701",
            regionOrStateName: "TX",
            countryName: "United States",
            isoCountryCode: "US"
        )

        XCTAssertTrue(try XCTUnwrap(address.formatted(.full)).contains("United States"))
        XCTAssertFalse(try XCTUnwrap(address.formatted(.compact)).contains("United States"))
    }

    func testDoesNotRepeatStreetNumberAlreadyInStreetName() throws {
        let address = Address(
            streetNumber: "11",
            streetName: "11 Willemstad",
            cityOrTownName: nil,
            postalCode: nil,
            regionOrStateName: nil,
            countryName: nil,
            isoCountryCode: "CW"
        )

        let line = try XCTUnwrap(address.formatted(.singleLine))

        XCTAssertTrue(line.contains("11 Willemstad"), line)
        XCTAssertFalse(line.contains("11 11"), line)
    }

    func testTrimsWhitespaceInComponents() throws {
        let address = Address(
            streetNumber: " 5 ",
            streetName: "  Ocean Drive ",
            cityOrTownName: " Miami ",
            postalCode: " 33139 ",
            regionOrStateName: " FL ",
            countryName: nil,
            isoCountryCode: " US "
        )

        let line = try XCTUnwrap(address.formatted(.singleLine))

        XCTAssertTrue(line.contains("5 Ocean Drive"), line)
        XCTAssertTrue(line.contains("Miami, FL 33139"), line)
    }

    func testEmptyAddressFormatsAsNil() {
        let address = Address(
            streetNumber: " ",
            streetName: nil,
            cityOrTownName: "",
            postalCode: nil,
            regionOrStateName: nil,
            countryName: nil,
            isoCountryCode: "US"
        )

        XCTAssertNil(address.formatted(.full))
        XCTAssertNil(address.formatted(.singleLine))
    }

    func testNormalizedPostalCodeStripsZipPlusFourOnlyForUS() {
        XCTAssertEqual(Address.normalizedPostalCode("78701-1234", countryName: "United States"), "78701")
        XCTAssertEqual(Address.normalizedPostalCode("78701-1234", countryName: " USA "), "78701")
        XCTAssertEqual(Address.normalizedPostalCode("78701-1234", countryName: nil), "78701")
        XCTAssertEqual(Address.normalizedPostalCode("12345-6789", countryName: "Germany"), "12345-6789")
        XCTAssertEqual(Address.normalizedPostalCode(" SW1A 1AA ", countryName: "United Kingdom"), "SW1A 1AA")
        XCTAssertEqual(Address.normalizedPostalCode("78701", countryName: "United States"), "78701")
        XCTAssertNil(Address.normalizedPostalCode("   ", countryName: "United States"))
        XCTAssertNil(Address.normalizedPostalCode(nil, countryName: nil))
    }
}

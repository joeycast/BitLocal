import Contacts

extension Address {
    enum FormatStyle {
        case full
        case compact
        case singleLine
    }

    func formatted(_ style: FormatStyle = .full) -> String? {
        let postal = CNMutablePostalAddress()

        var street = ""
        let num = streetNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !num.isEmpty && !name.isEmpty {
            // Avoid duplicating the number when streetName already starts with it
            // (e.g. geocoder returns subThoroughfare:"11", thoroughfare:"11 Willemstad")
            if name.hasPrefix(num) {
                street = name
            } else {
                street = "\(num) \(name)"
            }
        } else if !name.isEmpty {
            street = name
        } else if !num.isEmpty {
            street = num
        }
        postal.street = street

        postal.city = cityOrTownName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        postal.state = regionOrStateName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        postal.postalCode = postalCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if style == .full {
            postal.country = countryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        if let code = isoCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            postal.isoCountryCode = code
        } else if let deviceRegion = Locale.current.region?.identifier {
            // Fall back to device locale so the formatter knows basic conventions
            // (e.g. "City, State ZIP" for US). The regional country code cache
            // will override this with the merchant's actual country once available.
            postal.isoCountryCode = deviceRegion
        }

        let formatter = CNPostalAddressFormatter()
        let raw = formatter.string(from: postal)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // CNPostalAddressFormatter omits the comma between city and state
        // (follows USPS postal conventions). Insert it when both are present
        // so addresses read naturally (e.g. "Miami, FL 33131").
        let result = Self.insertCityStateComma(raw, city: postal.city, state: postal.state)

        guard !result.isEmpty else { return nil }

        switch style {
        case .full, .compact:
            return result
        case .singleLine:
            return result
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    /// Insert a comma between city and state when the formatter omits it.
    private static func insertCityStateComma(_ text: String, city: String, state: String) -> String {
        guard !city.isEmpty, !state.isEmpty else { return text }
        let needle = "\(city) \(state)"
        let replacement = "\(city), \(state)"
        return text.replacingOccurrences(of: needle, with: replacement)
    }
}

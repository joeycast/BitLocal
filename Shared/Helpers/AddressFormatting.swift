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
        }

        let formatter = CNPostalAddressFormatter()
        let result = formatter.string(from: postal)
            .trimmingCharacters(in: .whitespacesAndNewlines)

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
}

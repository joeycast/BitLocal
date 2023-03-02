//import SwiftUI
//import SQLite
//
//// Create database
//let path = NSSearchPathForDirectoriesInDomains(
//    .documentDirectory, .userDomainMask, true
//).first!
//
//// Define the SQLite database connection
//let db = try! Connection("\(path)/db.sqlite3")
//
//// Enable logging
//// db.trace { print($0) }
//
//// Define an "elements" table
//let elementsTable = Table("elements")
//
//// Define table fields
//let id = Expression<Int64>("id")
//let btcMapElementId = Expression<String>("btcMapElementId")
//let btcMapElementCreatedAt = Expression<Date>("btcMapElementCreatedAt")
//let btcMapElementUpdatedAt = Expression<Date>("btcMapElementUpdatedAt")
//let btcMapElementDeletedAt = Expression<Date?>("btcMapElementDeletedAt")
//let osmJsonChangeset = Expression<Int64?>("osmJsonChangeset")
//let osmJsonId = Expression<Int64>("osmJsonId")
//let osmJsonLat = Expression<Double?>("osmJsonLat")
//let osmJsonLon = Expression<Double?>("osmJsonLon")
//let osmJsonTimestamp = Expression<Date?>("osmJsonTimestamp")
//let osmJsonType = Expression<String?>("osmJsonType")
//let osmJsonUid = Expression<Int64?>("osmJsonUid")
//let osmJsonUser = Expression<String?>("osmJsonUser")
//let osmJsonVersion = Expression<Int64?>("osmJsonVersion")
//let osmJsonTagAddrCity = Expression<String?>("osmJsonTagAddrCity")
//let osmJsonTagAddrHousenumber = Expression<String?>("osmJsonTagAddrHousenumber")
//let osmJsonTagAddrPostcode = Expression<String?>("osmJsonTagAddrPostcode")
//let osmJsonTagAddrStreet = Expression<String?>("osmJsonTagAddrStreet")
//let osmJsonTagCurrencyGBP = Expression<String?>("osmJsonTagCurrencyGBP")
//let osmJsonTagCurrencyXBT = Expression<String?>("osmJsonTagCurrencyXBT")
//let osmJsonTagCurrencyOthers = Expression<String?>("osmJsonTagCurrencyOthers")
//let osmJsonTagDescription = Expression<String?>("osmJsonTagDescription")
//let osmJsonTagName = Expression<String?>("osmJsonTagName")
//let osmJsonTagOpeningHours = Expression<String?>("osmJsonTagOpeningHours")
//let osmJsonTagPaymentLightning = Expression<String?>("osmJsonTagPaymentLightning")
//let osmJsonTagPaymentLightningContactless = Expression<String?>("osmJsonTagPaymentLightningContactless")
//let osmJsonTagPaymentOnchain = Expression<String?>("osmJsonTagPaymentOnchain")
//let osmJsonTagPhone = Expression<String?>("osmJsonTagPhone")
//let osmJsonTagShop = Expression<String?>("osmJsonTagShop")
//let osmJsonTagSurveyDate = Expression<String?>("osmJsonTagSurveyDate")
//let btcMapTagBoostExpires = Expression<String?>("btcMapTagBoostExpires")
//let btcMapTagCategory = Expression<String?>("btcMapTagCategory")
//let btcMapTagIconAndroid = Expression<String?>("btcMapTagIconAndroid")
//let btcMapTagPaymentProvider = Expression<String?>("btcMapTagPaymentProvider")
//
//// Define the Element struct
//struct Element: Codable {
//    let id: Int64
//    let osmJson: OsmJson?
//    let tags: Tags?
//    let createdAt: Date
//    let updatedAt: Date
//    let deletedAt: String?
//}
//
//struct OsmJson: Codable {
//    let changeset: Int?
//    let id: Int?
//    let lat: Double? 
//    let lon: Double?
//    let tags: OsmJsonTags?
//    let timestamp: Date?
//    let type: String?
//    let uid: Int?
//    let user: String?
//    let version: Int?
//}
//
//struct OsmJsonTags: Codable {
//    let addr: Addr?
//    let currency: Currency?
//    let description: String?
//    let name: String?
//    let opening_hours: String?
//    let payment: Payment?
//    let phone: String?
//    let shop: String?
//    let survey: Survey?
//    let wesbite: String?
//}
//
//struct Addr: Codable {
//    let city: String?
//    let housenumber: String?
//    let postcode: String?
//    let street: String?
//}
//
//struct Currency: Codable {
//    let XBT: String?
//    let GBT: String?
//    let others: String?
//}
//
//struct Payment: Codable {
//    let lightning: String?
//    let lightningcontactless: String?
//    let paymentonchain: String?
//}
//
//struct Survey: Codable {
//    let date: String?
//}
//
//struct Tags: Codable {
//    let boostExpires: String?
//    let category: String?
//    let icon: Icon?
//    let paymentProvider: String?
//}
//
//struct Icon: Codable {
//    let android: String?
//}
//
//// Define the ElementsViewModel class as before
//class ElementsViewModel: ObservableObject {
//    @Published var elements = [Element]()
//    
//    init() {
//        // Create the "elements" table if it doesn't exist
//        try! db.run(elementsTable.create(ifNotExists: true) { table in
//            table.column(id, primaryKey: .autoincrement)            //     "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
//            //table.column(id, primaryKey: true)                      //     "id" INTEGER PRIMARY KEY NOT NULL,
//            table.column(btcMapElementId, unique: true)             //     "btcMapElementId" TEXT UNIQUE NOT NULL
//            table.column(btcMapElementCreatedAt)                    //     "btcMapElementCreatedAt" TEXT NOT NULL
//            table.column(btcMapElementUpdatedAt)                    //     "btcMapElementUpdatedAt" TEXT NOT NULL
//            table.column(btcMapElementDeletedAt)                    //     "btcMapElementDeletedAt" TEXT
//            table.column(osmJsonChangeset)                          //     etc...
//            table.column(osmJsonId)
//            table.column(osmJsonLat)
//            table.column(osmJsonLon)
//            table.column(osmJsonTimestamp)
//            table.column(osmJsonType)
//            table.column(osmJsonUid)
//            table.column(osmJsonUser)
//            table.column(osmJsonVersion)
//            table.column(osmJsonTagAddrCity)
//            table.column(osmJsonTagAddrHousenumber)
//            table.column(osmJsonTagAddrPostcode)
//            table.column(osmJsonTagAddrStreet)
//            table.column(osmJsonTagCurrencyGBP)
//            table.column(osmJsonTagCurrencyXBT)
//            table.column(osmJsonTagCurrencyOthers)
//            table.column(osmJsonTagDescription)
//            table.column(osmJsonTagName)
//            table.column(osmJsonTagOpeningHours)
//            table.column(osmJsonTagPaymentLightning)
//            table.column(osmJsonTagPaymentLightningContactless)
//            table.column(osmJsonTagPaymentOnchain)
//            table.column(osmJsonTagPhone)
//            table.column(osmJsonTagShop)
//            table.column(osmJsonTagSurveyDate)
//            table.column(btcMapTagBoostExpires)
//            table.column(btcMapTagCategory)
//            table.column(btcMapTagIconAndroid)
//            table.column(btcMapTagPaymentProvider)
//        })
//        
//        // Fetch the data from the API and store it in the database
//        guard let url = URL(string: "https://api.btcmap.org/v2/elements/node:9985802993") else { 
//            return }
//        URLSession.shared.dataTask(with: url) { (data, response, error) in
//            if let data = data {
//                if let decodedResponse = try? JSONDecoder().decode([Element].self, from: data) {
//                    DispatchQueue.main.async {
//                        self.elements = decodedResponse
//                        
//                        // Store the fetched data in the database
//                        for element in decodedResponse {
//                            let insert = elementsTable.insert(or: .replace, id <- element.id)
//                            try! db.run(insert)
//                            print("\(element.id)")
//                        }
//                    }
//                    return
//                }
//            }
//            print("Fetch failed: \(error?.localizedDescription ?? "Unknown error")")
//        }.resume()
//    }
//}
//
//
//// Define the ContentView
//struct BtcMapView: SwiftUI.View {
//    @ObservedObject var elementsVM = ElementsViewModel()
//    
//    var body: some SwiftUI.View {
//        List(elementsVM.elements, id: \.id) { element in
//            VStack(alignment: .leading) {
//                Text("\(element.id)")
//            }
//        }
//    }
//}
//
//struct BtcMapView_Previews: PreviewProvider {
//    static var previews: some SwiftUI.View {
//        BtcMapView()
//    }
//}

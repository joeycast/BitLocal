//import SwiftUI
//import SQLite
//
//func createDatabase() {
//    // Wrap everything in a do catch for error handling 
//    do {
//        // Create database
//        let path = NSSearchPathForDirectoriesInDomains(
//            .documentDirectory, .userDomainMask, true
//        ).first!
//        
//        let db = try Connection("\(path)/db.sqlite3")
//        
//        // Enable logging
//        db.trace { print($0) }
//        
//        // Define an "elements" table
//        let elements = Table("elements")
//        
//        // Define table fields
//        let id = Expression<Int64>("id")
//        let btcMapElementId = Expression<String>("btcMapElementId")
//        let btcMapElementCreatedAt = Expression<Date>("btcMapElementCreatedAt")
//        let btcMapElementUpdatedAt = Expression<Date>("btcMapElementUpdatedAt")
//        let btcMapElementDeletedAt = Expression<Date?>("btcMapElementDeletedAt")
//        let osmJsonChangeset = Expression<Int64?>("osmJsonChangeset")
//        let osmJsonId = Expression<Int64>("osmJsonId")
//        let osmJsonLat = Expression<Double?>("osmJsonLat")
//        let osmJsonLon = Expression<Double?>("osmJsonLon")
//        let osmJsonTimestamp = Expression<Date?>("osmJsonTimestamp")
//        let osmJsonType = Expression<String?>("osmJsonType")
//        let osmJsonUid = Expression<Int64?>("osmJsonUid")
//        let osmJsonUser = Expression<String?>("osmJsonUser")
//        let osmJsonVersion = Expression<Int64?>("osmJsonVersion")
//        let osmJsonTagAddrCity = Expression<String?>("osmJsonTagAddrCity")
//        let osmJsonTagAddrHousenumber = Expression<String?>("osmJsonTagAddrHousenumber")
//        let osmJsonTagAddrPostcode = Expression<String?>("osmJsonTagAddrPostcode")
//        let osmJsonTagAddrStreet = Expression<String?>("osmJsonTagAddrStreet")
//        let osmJsonTagCurrencyGBP = Expression<String?>("osmJsonTagCurrencyGBP")
//        let osmJsonTagCurrencyXBT = Expression<String?>("osmJsonTagCurrencyXBT")
//        let osmJsonTagCurrencyOthers = Expression<String?>("osmJsonTagCurrencyOthers")
//        let osmJsonTagDescription = Expression<String?>("osmJsonTagDescription")
//        let osmJsonTagName = Expression<String?>("osmJsonTagName")
//        let osmJsonTagOpeningHours = Expression<String?>("osmJsonTagOpeningHours")
//        let osmJsonTagPaymentLightning = Expression<String?>("osmJsonTagPaymentLightning")
//        let osmJsonTagPaymentLightningContactless = Expression<String?>("osmJsonTagPaymentLightningContactless")
//        let osmJsonTagPaymentOnchain = Expression<String?>("osmJsonTagPaymentOnchain")
//        let osmJsonTagPhone = Expression<String?>("osmJsonTagPhone")
//        let osmJsonTagShop = Expression<String?>("osmJsonTagShop")
//        let osmJsonTagSurveyDate = Expression<String?>("osmJsonTagSurveyDate")
//        let btcMapTagBoostExpires = Expression<String?>("btcMapTagBoostExpires")
//        let btcMapTagCategory = Expression<String?>("btcMapTagCategory")
//        let btcMapTagIconAndroid = Expression<String?>("btcMapTagIconAndroid")
//        let btcMapTagPaymentProvider = Expression<String?>("btcMapTagPaymentProvider")
//
//        // Create table
//        try db.run(elements.create(ifNotExists: true) { t in    // CREATE TABLE "elements" (
//            t.column(id, primaryKey: .autoincrement)            //     "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
//            t.column(id, primaryKey: true)                      //     "id" INTEGER PRIMARY KEY NOT NULL,
//            t.column(btcMapElementId, unique: true)             //     "btcMapElementId" TEXT UNIQUE NOT NULL
//            t.column(btcMapElementCreatedAt)                    //     "btcMapElementCreatedAt" TEXT NOT NULL
//            t.column(btcMapElementUpdatedAt)                    //     "btcMapElementUpdatedAt" TEXT NOT NULL
//            t.column(btcMapElementDeletedAt)                    //     "btcMapElementDeletedAt" TEXT
//            t.column(osmJsonChangeset)                          //     etc...
//            t.column(osmJsonId)
//            t.column(osmJsonLat)
//            t.column(osmJsonLon)
//            t.column(osmJsonTimestamp)
//            t.column(osmJsonType)
//            t.column(osmJsonUid)
//            t.column(osmJsonUser)
//            t.column(osmJsonVersion)
//            t.column(osmJsonTagAddrCity)
//            t.column(osmJsonTagAddrHousenumber)
//            t.column(osmJsonTagAddrPostcode)
//            t.column(osmJsonTagAddrStreet)
//            t.column(osmJsonTagCurrencyGBP)
//            t.column(osmJsonTagCurrencyXBT)
//            t.column(osmJsonTagCurrencyOthers)
//            t.column(osmJsonTagDescription)
//            t.column(osmJsonTagName)
//            t.column(osmJsonTagOpeningHours)
//            t.column(osmJsonTagPaymentLightning)
//            t.column(osmJsonTagPaymentLightningContactless)
//            t.column(osmJsonTagPaymentOnchain)
//            t.column(osmJsonTagPhone)
//            t.column(osmJsonTagShop)
//            t.column(osmJsonTagSurveyDate)
//            t.column(btcMapTagBoostExpires)
//            t.column(btcMapTagCategory)
//            t.column(btcMapTagIconAndroid)
//            t.column(btcMapTagPaymentProvider)
//        })
//    } catch {
//        print("An error occurred.")
//    }
//    
//}

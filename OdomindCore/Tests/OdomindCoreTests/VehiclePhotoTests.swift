import XCTest
@testable import OdomindCore

/// The rules that decide whether Odomind may show a photograph, and what it is
/// allowed to say about it.
final class VehiclePhotoTests: XCTestCase {

    private func photo(
        licence: String,
        attribution: String,
        level: PhotoMatchLevel = .exactModelYear
    ) -> VehiclePhoto {
        VehiclePhoto(
            sourceIdentifier: "commons:File:Example.jpg",
            providerName: "Wikimedia Commons",
            imageURL: URL(string: "https://upload.wikimedia.org/example.jpg")!,
            licenceName: licence,
            attribution: attribution,
            matchLevel: level,
            matchedQuery: "2010 Jeep Wrangler",
            retrievedOn: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    // MARK: - Licence

    func testAnImageWithNoLicenceIsNeverShown() {
        XCTAssertFalse(photo(licence: "", attribution: "Somebody").isDisplayable)
    }

    func testAShareAlikeImageNeedsItsAuthorNamed() {
        XCTAssertFalse(
            photo(licence: "CC BY-SA 4.0", attribution: "").isDisplayable,
            "a licence requiring attribution cannot be satisfied without an author"
        )
        XCTAssertTrue(photo(licence: "CC BY-SA 4.0", attribution: "Dinkun Chen").isDisplayable)
    }

    func testAPublicDomainImageDoesNotRequireAnAuthor() {
        XCTAssertFalse(photo(licence: "Public domain", attribution: "").requiresAttribution)
        XCTAssertTrue(photo(licence: "Public domain", attribution: "").isDisplayable)
    }

    func testTheCreditLineNamesBothAuthorAndLicence() {
        let credit = photo(licence: "CC BY-SA 4.0", attribution: "Dinkun Chen").creditLine
        XCTAssertTrue(credit.contains("Dinkun Chen"))
        XCTAssertTrue(credit.contains("CC BY-SA 4.0"))
    }

    // MARK: - What the picture is allowed to claim

    func testEveryMatchLevelSaysWhatItIs() {
        for level in PhotoMatchLevel.allCases {
            XCTAssertFalse(level.disclosure.isEmpty, "\(level) must say what it is")
        }
    }

    func testOnlyTheOwnersPhotoIsDescribedAsTheirs() {
        XCTAssertEqual(PhotoMatchLevel.ownerPhoto.disclosure, "Your photo.")
        for level in PhotoMatchLevel.allCases where level != .ownerPhoto {
            XCTAssertFalse(
                level.disclosure.lowercased().contains("your vehicle."),
                "\(level) must not be described as a photo of the owner's own car"
            )
        }
    }

    func testARepresentativePhotoDoesNotClaimTheModel() {
        XCTAssertFalse(PhotoMatchLevel.representative.namesTheModel)
        XCTAssertTrue(PhotoMatchLevel.exactModelYear.namesTheModel)
        XCTAssertTrue(PhotoMatchLevel.generation.namesTheModel)
    }

    func testTheOwnersPhotoOutranksEverythingElse() {
        for level in PhotoMatchLevel.allCases where level != .ownerPhoto {
            XCTAssertGreaterThan(PhotoMatchLevel.ownerPhoto, level)
        }
        XCTAssertGreaterThan(PhotoMatchLevel.exactModelYear, PhotoMatchLevel.generation)
        XCTAssertGreaterThan(PhotoMatchLevel.generation, PhotoMatchLevel.representative)
    }

    func testARecordSurvivesARoundTrip() throws {
        let original = photo(licence: "CC BY-SA 4.0", attribution: "Dinkun Chen")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = DateCoding.encodingStrategy
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = DateCoding.decodingStrategy

        let restored = try decoder.decode(VehiclePhoto.self, from: encoder.encode(original))
        XCTAssertEqual(restored, original, "a cached record must read back exactly, licence included")
    }
}

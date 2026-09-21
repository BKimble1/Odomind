import XCTest
@testable import OdomindCore

/// The searching behaviour Build 3 exists to fix, checked against the real
/// generated index rather than a hand-made fixture — a matcher that only works
/// on invented data is not evidence of anything.
final class VehicleSearchMatchingTests: XCTestCase {

    private static let index: VehicleIndex = {
        (try? VehicleIndexLoader.loadBundled()) ?? .empty
    }()

    private var index: VehicleIndex { Self.index }

    private func plan(_ text: String) -> VehicleQuery {
        VehicleQueryPlanner.plan(text, index: index, now: Date(timeIntervalSince1970: 1_780_000_000))
    }

    // MARK: - The index itself

    func testTheBundledIndexIsRealAndGenerated() throws {
        XCTAssertGreaterThan(index.makes.count, 1000, "the index should be vPIC's make list, not a hand-typed one")
        XCTAssertGreaterThan(index.models.values.reduce(0) { $0 + $1.count }, 1000)
        XCTAssertTrue(index.source.localizedCaseInsensitiveContains("vPIC"), "the index must say where it came from")
        XCTAssertFalse(index.generatedOn.isEmpty)
    }

    // MARK: - Normalising

    func testPunctuationAndSpacingDoNotChangeTheAnswer() {
        for spelling in ["F-150", "f150", "F 150", "f-150"] {
            let tokens = VehicleTextMatch.tokens(spelling)
            let ranked = VehicleTextMatch.rank(models: index.models(for: "FORD"), queryTokens: tokens, limit: 3)
            XCTAssertTrue(
                ranked.contains { $0.model.uppercased() == "F-150" },
                "\(spelling) should find the F-150, got \(ranked.map(\.model))"
            )
        }
    }

    // MARK: - Extra words must narrow, never delete

    func testTrimWordsDoNotEliminateTheModel() {
        // The Build 2 defect: everything after the make was matched as one
        // substring, so "Unlimited Sport" matched no model and the Wrangler
        // was lost.
        let query = plan("2010 Jeep Wrangler Unlimited Sport")
        guard case .makeAndModel(let make, let tokens) = query.intent else {
            return XCTFail("expected a make and model, got \(query.intent)")
        }
        XCTAssertEqual(make, "JEEP")
        XCTAssertEqual(query.modelYear, 2010)

        let ranked = VehicleTextMatch.rank(models: index.models(for: make), queryTokens: tokens, limit: 5)
        XCTAssertTrue(
            ranked.contains { $0.model == "Wrangler" },
            "Wrangler must survive the extra trim words, got \(ranked.map(\.model))"
        )
    }

    func testTheUnexplainedWordsComeBackAsATrimHint() {
        let match = VehicleTextMatch.match(model: "Wrangler", queryTokens: ["wrangler", "unlimited", "sport"])
        XCTAssertEqual(match?.quality, .leadingRun)
        XCTAssertEqual(match?.leftover, ["unlimited", "sport"])
    }

    func testAModelIsNotMatchedByAnUnrelatedQuery() {
        XCTAssertNil(VehicleTextMatch.match(model: "Wrangler", queryTokens: ["camry"]))
    }

    // MARK: - Model with no make, which is how people talk

    func testAModelOnItsOwnFindsItsMake() {
        guard case .model(_, let candidates) = plan("wrangler").intent else {
            return XCTFail("expected model candidates for a bare model name")
        }
        XCTAssertEqual(candidates.first?.make, "JEEP")
        XCTAssertEqual(candidates.first?.model, "Wrangler")
    }

    func testAModelNameThatIsAlsoSomebodysMakeIsStillTreatedAsAModel() {
        // vPIC's make list has 12,364 entries and "WRANGLER" is one of them —
        // an equipment manufacturer, not the Jeep. Resolving against the full
        // list before considering models turned a search for a Wrangler into
        // a search for that company. Found by running against the real index.
        XCTAssertNotNil(index.anyMake(named: "wrangler"), "the collision this guards against still exists")
        XCTAssertNil(index.passengerMake(named: "wrangler"), "but it is not a make anyone shopping for a car means")

        guard case .model(_, let candidates) = plan("wrangler").intent else {
            return XCTFail("a model name must win over an obscure like-named make")
        }
        XCTAssertEqual(candidates.first?.make, "JEEP")
    }

    func testAGenuinelyObscureMakeStillResolves() throws {
        // The long tail is still reachable, just consulted after models.
        guard let obscure = index.makes.first(where: { name in
            index.passengerMake(named: name) == nil
                && index.makesOffering(modelTokens: VehicleTextMatch.tokens(name)).isEmpty
                && !name.contains(" ")
                && name.count > 5
        }) else {
            throw XCTSkip("no suitable obscure make in this index")
        }
        guard case .make(let resolved) = plan(obscure).intent else {
            return XCTFail("\(obscure) should still resolve as a make")
        }
        XCTAssertEqual(resolved, obscure)
    }

    func testAModelOnItsOwnWorksForOtherMakesToo() {
        guard case .model(_, let candidates) = plan("camry").intent else {
            return XCTFail("expected model candidates")
        }
        XCTAssertEqual(candidates.first?.make, "TOYOTA")
    }

    // MARK: - Make only, and part of a make

    func testAMakeOnItsOwnAsksForThatMakesModels() {
        guard case .make(let make) = plan("Jeep").intent else {
            return XCTFail("expected a make-only query")
        }
        XCTAssertEqual(make, "JEEP")
    }

    func testPartOfAMakeOffersMakes() {
        guard case .makeSuggestions(let makes) = plan("jee").intent else {
            return XCTFail("expected make suggestions while still typing")
        }
        XCTAssertTrue(makes.contains("JEEP"), "got \(makes)")
    }

    func testASingleLetterOffersMakesRatherThanUnrelatedModels() {
        // Real regression. One letter used to be matched by prefix against
        // every model name in the index, so backspacing "2010 Jeep" down to
        // "j" answered with a Jaguar, a Jetta and a Journey — three unrelated
        // cars from three unrelated manufacturers, presented as results.
        XCTAssertTrue(
            index.makesOffering(modelTokens: ["j"]).isEmpty,
            "one letter must not match models by prefix"
        )
        let intent = plan("j").intent
        guard case .makeSuggestions(let makes) = intent else {
            return XCTFail("expected make suggestions for a single letter, got \(intent)")
        }
        XCTAssertTrue(makes.contains("JEEP"), "got \(makes)")
    }

    func testAShortModelNameIsStillFoundWhenItIsTypedInFull() {
        // The length rule bars a *prefix* match, not a short model. "GT" is
        // two characters and is a real car; barring it would be the cure
        // doing more damage than the disease.
        // A key path cannot address a tuple element, so the names are pulled
        // out with a closure.
        let hits = index.makesOffering(modelTokens: ["gt"])
        let names = hits.map { $0.model }
        XCTAssertTrue(
            names.contains { VehicleTextMatch.key($0) == "gt" },
            "a whole-word match on a two-letter model should survive, got \(names)"
        )
    }

    // MARK: - Aliases and word order

    func testCommonShorthandResolves() {
        for (typed, expected) in [("chevy", "CHEVROLET"), ("vw", "VOLKSWAGEN"), ("mercedes", "MERCEDES-BENZ")] {
            guard case .make(let make) = plan(typed).intent else {
                return XCTFail("\(typed) should resolve to a make, got \(plan(typed).intent)")
            }
            XCTAssertEqual(make, expected)
        }
    }

    func testEitherWordOrderParsesTheSameWay() {
        let a = plan("2010 Jeep Wrangler")
        let b = plan("Jeep Wrangler 2010")
        XCTAssertEqual(a.modelYear, 2010)
        XCTAssertEqual(b.modelYear, 2010)
        XCTAssertEqual(a.intent, b.intent)
    }

    func testAMultiWordMakeIsNotSplit() {
        guard case .makeAndModel(let make, let tokens) = plan("land rover discovery").intent else {
            return XCTFail("expected a multi-word make to resolve whole")
        }
        XCTAssertEqual(make, "LAND ROVER")
        XCTAssertEqual(tokens, ["discovery"])
    }

    // MARK: - Years

    func testAYearIsOptional() {
        XCTAssertNil(plan("Jeep Wrangler").modelYear)
        if case .tooShort = plan("Jeep Wrangler").intent {
            XCTFail("a query without a year must still be actionable")
        }
    }

    func testAnImplausibleYearIsNotTreatedAsOne() {
        // 1899 is before cars had model years; 2999 is a part number.
        XCTAssertNil(plan("1899 Jeep").modelYear)
        XCTAssertNil(plan("2999 Jeep").modelYear)
    }

    func testAnEngineSizeIsNotMistakenForAYear() {
        let query = plan("Jeep Wrangler 3800")
        XCTAssertNil(query.modelYear, "3800 is not a model year")
    }

    // MARK: - Nothing recognised

    func testAnUnrecognisedQueryIsStillCarriedToTheProvider() {
        // The index suggests; it never decides what exists. Something it has
        // never heard of must still reach vPIC rather than being refused.
        let intent = plan("zzzqqq").intent
        switch intent {
        case .unrecognised, .makeSuggestions, .model:
            break  // any of these still results in a provider request
        default:
            XCTFail("an unknown query must not be dead-ended, got \(intent)")
        }
    }

    func testAnEmptyQueryAsksForNothing() {
        XCTAssertEqual(plan("").intent, .tooShort)
        XCTAssertEqual(plan("   ").intent, .tooShort)
    }
}

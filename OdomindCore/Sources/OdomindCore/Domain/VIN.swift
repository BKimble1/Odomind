import Foundation

/// Vehicle identification number parsing and checks.
///
/// Lives in the portable core so the rules are unit-tested rather than trusted.
/// Nothing here ever logs or prints a VIN: it is one of the few genuinely
/// identifying values Odomind handles.
public enum VIN {
    public static let length = 17

    /// Letters that never appear in a VIN, because they are too easily confused
    /// with 0, 1 and 2.
    public static let forbiddenLetters: Set<Character> = ["I", "O", "Q"]

    public enum Problem: Hashable, Sendable {
        case wrongLength(Int)
        case forbiddenCharacter(Character)
        case invalidCharacter(Character)
        /// The check digit in position 9 does not match. Reported as a caution,
        /// not a rejection: vehicles built outside North America are not
        /// required to carry a valid one.
        case checkDigitMismatch(expected: Character, found: Character)

        public var isBlocking: Bool {
            switch self {
            case .wrongLength, .forbiddenCharacter, .invalidCharacter:
                return true
            case .checkDigitMismatch:
                return false
            }
        }

        public var message: String {
            switch self {
            case .wrongLength(let count):
                return "A VIN is \(VIN.length) characters. This one has \(count)."
            case .forbiddenCharacter(let character):
                return "VINs never contain the letter \(character). It is usually a \(VIN.lookalike(for: character))."
            case .invalidCharacter(let character):
                return "'\(character)' is not valid in a VIN."
            case .checkDigitMismatch:
                return "The check digit does not match. Double-check the characters — or continue, since vehicles built outside North America may not carry one."
            }
        }
    }

    static func lookalike(for character: Character) -> String {
        switch character {
        case "I": return "1"
        case "O": return "0"
        case "Q": return "0"
        default: return "different character"
        }
    }

    /// Uppercases and strips separators people naturally type or that a scanner
    /// picks up from a windshield plate.
    public static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func problems(in raw: String) -> [Problem] {
        let vin = normalize(raw)
        var found: [Problem] = []

        if vin.count != length {
            found.append(.wrongLength(vin.count))
        }
        for character in vin {
            if forbiddenLetters.contains(character) {
                found.append(.forbiddenCharacter(character))
            } else if !(character.isASCII && (character.isLetter || character.isNumber)) {
                found.append(.invalidCharacter(character))
            }
        }

        if vin.count == length, !found.contains(where: { $0.isBlocking }) {
            let characters = Array(vin)
            if let expected = checkDigit(for: characters) {
                let found9 = characters[8]
                if expected != found9 {
                    found.append(.checkDigitMismatch(expected: expected, found: found9))
                }
            }
        }

        return found
    }

    public static func isStructurallyValid(_ raw: String) -> Bool {
        !problems(in: raw).contains { $0.isBlocking }
    }

    /// The North American check digit for position 9, per 49 CFR 565.15.
    static func checkDigit(for characters: [Character]) -> Character? {
        guard characters.count == length else { return nil }
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        var sum = 0
        for (index, character) in characters.enumerated() {
            guard let value = transliterate(character) else { return nil }
            sum += value * weights[index]
        }
        let remainder = sum % 11
        return remainder == 10 ? "X" : Character(String(remainder))
    }

    static func transliterate(_ character: Character) -> Int? {
        if let digit = character.wholeNumberValue, character.isNumber { return digit }
        switch character {
        case "A", "J": return 1
        case "B", "K", "S": return 2
        case "C", "L", "T": return 3
        case "D", "M", "U": return 4
        case "E", "N", "V": return 5
        case "F", "W": return 6
        case "G", "P", "X": return 7
        case "H", "Y": return 8
        case "R", "Z": return 9
        default: return nil
        }
    }

    /// The model-year character in position 10, decoded to a year.
    ///
    /// The code repeats every 30 years, so a range is needed to disambiguate.
    /// Returns `nil` rather than guessing when the character is not a year code.
    public static func modelYear(from raw: String, notAfter latestPlausible: Int) -> Int? {
        let vin = normalize(raw)
        guard vin.count == length else { return nil }
        let character = Array(vin)[9]

        let codes: [Character] = [
            "A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "R", "S", "T", "V", "W", "X", "Y",
            "1", "2", "3", "4", "5", "6", "7", "8", "9"
        ]
        guard let index = codes.firstIndex(of: character) else { return nil }

        // The cycle that produced 1980 for code "A".
        var year = 1980 + index
        while year + 30 <= latestPlausible {
            year += 30
        }
        return year
    }
}

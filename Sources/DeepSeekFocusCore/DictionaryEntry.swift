import Foundation

public struct DictionaryDefinition: Codable, Equatable, Sendable {
    public var meaning: String
    public var example: String?

    public init(meaning: String, example: String? = nil) {
        self.meaning = meaning
        self.example = example
    }
}

public struct DictionaryExample: Codable, Equatable, Sendable {
    public var text: String
    public var translation: String?

    public init(text: String, translation: String? = nil) {
        self.text = text
        self.translation = translation
    }
}

public struct DictionaryEntry: Codable, Equatable, Sendable {
    public var term: String
    public var pronunciation: String?
    public var partOfSpeech: String?
    public var definitions: [DictionaryDefinition]
    public var examples: [DictionaryExample]
    public var synonyms: [String]
    public var notes: String?

    public init(
        term: String,
        pronunciation: String? = nil,
        partOfSpeech: String? = nil,
        definitions: [DictionaryDefinition] = [],
        examples: [DictionaryExample] = [],
        synonyms: [String] = [],
        notes: String? = nil
    ) {
        self.term = term
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.definitions = definitions
        self.examples = examples
        self.synonyms = synonyms
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case term
        case pronunciation
        case partOfSpeech
        case definitions
        case examples
        case synonyms
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decode(String.self, forKey: .term)
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation)
        partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech)
        definitions = try container.decodeIfPresent([DictionaryDefinition].self, forKey: .definitions) ?? []
        examples = try container.decodeIfPresent([DictionaryExample].self, forKey: .examples) ?? []
        synonyms = try container.decodeIfPresent([String].self, forKey: .synonyms) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    public static func parse(_ raw: String) -> DictionaryEntry? {
        let stripped = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = stripped.firstIndex(of: "{"),
              let end = stripped.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        let json = String(stripped[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DictionaryEntry.self, from: data)
    }
}

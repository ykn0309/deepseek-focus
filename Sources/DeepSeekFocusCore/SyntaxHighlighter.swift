import Foundation

/// Token kinds used by the lightweight, dependency-free code highlighter.
public enum SyntaxTokenKind: String, Equatable {
    case keyword
    case string
    case comment
    case number
    case function
    case type
    case variable
    case property
    case literal
}

public struct SyntaxToken: Equatable {
    public let range: Range<String.Index>
    public let kind: SyntaxTokenKind

    public init(range: Range<String.Index>, kind: SyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// Small, local highlighter for common code-block languages. It is deliberately
/// conservative: highlighting is a readability aid, and unknown languages still
/// get strings, comments and numbers highlighted.
public enum SyntaxHighlighter {
    public static func tokens(in code: String, language: String?) -> [SyntaxToken] {
        guard !code.isEmpty else { return [] }
        let config = SyntaxLanguage.configuration(for: language)
        var tokens: [SyntaxToken] = []
        var index = code.startIndex

        while index < code.endIndex {
            let character = code[index]

            if character.isWhitespace {
                index = code.index(after: index)
                continue
            }

            if let block = config.blockComments.first(where: { code[index...].hasPrefix($0.start) }) {
                let end = code.range(of: block.end, range: index..<code.endIndex)?.upperBound ?? code.endIndex
                tokens.append(SyntaxToken(range: index..<end, kind: .comment))
                index = end
                continue
            }

            if let marker = config.lineComments.first(where: { code[index...].hasPrefix($0) }),
               !config.hashCommentNeedsLeadingSpace || marker != "#" || isStartOfLine(index, in: code) {
                let end = code[index...].firstIndex(of: "\n") ?? code.endIndex
                tokens.append(SyntaxToken(range: index..<end, kind: .comment))
                index = end
                continue
            }

            if let quote = config.stringQuotes.first(where: { code[index...].hasPrefix($0) }) {
                let end = scanString(in: code, from: index, quote: quote)
                let stringRange = index..<end
                let kind: SyntaxTokenKind
                if config.jsonKeys, isJSONKey(in: code, range: stringRange) {
                    kind = .property
                } else {
                    kind = .string
                }
                tokens.append(SyntaxToken(range: stringRange, kind: kind))
                index = end
                continue
            }

            if config.shellVariables, character == "$" {
                let end = scanShellVariable(in: code, from: index)
                if end > code.index(after: index) {
                    tokens.append(SyntaxToken(range: index..<end, kind: .variable))
                    index = end
                    continue
                }
            }

            if config.htmlTags, character == "<" {
                if let end = scanHTMLTag(in: code, from: index) {
                    tokens.append(SyntaxToken(range: index..<end, kind: .type))
                    index = end
                    continue
                }
            }

            if character.isNumber {
                let end = scanNumber(in: code, from: index)
                tokens.append(SyntaxToken(range: index..<end, kind: .number))
                index = end
                continue
            }

            if isIdentifierStart(character) {
                let end = scanIdentifier(in: code, from: index)
                let range = index..<end
                let word = String(code[range])
                let lower = word.lowercased()
                var kind: SyntaxTokenKind?

                if config.literals.contains(lower) {
                    kind = .literal
                } else if config.caseInsensitiveKeywords
                    ? config.keywords.contains(lower)
                    : config.keywords.contains(word) {
                    kind = .keyword
                } else if config.types.contains(word) || config.types.contains(lower) {
                    kind = .type
                } else if config.commands.contains(word) || config.commands.contains(lower) {
                    kind = .function
                } else if isFunctionCall(after: end, in: code) {
                    kind = .function
                } else if config.propertiesBeforeColon, isFollowedByColon(after: end, in: code) {
                    kind = .property
                }

                if let kind {
                    tokens.append(SyntaxToken(range: range, kind: kind))
                }
                index = end
                continue
            }

            index = code.index(after: index)
        }

        return tokens
    }
}

private struct SyntaxLanguage {
    let lineComments: [String]
    let blockComments: [(start: String, end: String)]
    let stringQuotes: [String]
    let keywords: Set<String>
    let types: Set<String>
    let literals: Set<String>
    let commands: Set<String>
    let caseInsensitiveKeywords: Bool
    let shellVariables: Bool
    let jsonKeys: Bool
    let htmlTags: Bool
    let propertiesBeforeColon: Bool
    let hashCommentNeedsLeadingSpace: Bool

    static func configuration(for language: String?) -> SyntaxLanguage {
        let id = (language ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if id.contains("swift") { return swift }
        if id == "py" || id.contains("python") { return python }
        if id == "sh" || id == "bash" || id == "zsh" || id.contains("shell") || id == "console" {
            return shell
        }
        if id == "js" || id.contains("javascript") || id == "jsx" { return javascript }
        if id == "ts" || id.contains("typescript") || id == "tsx" { return typescript }
        if id.contains("json") { return json }
        if id.contains("html") || id.contains("xml") { return html }
        if id.contains("css") || id.contains("scss") || id.contains("less") { return css }
        if id.contains("sql") { return sql }
        if id == "go" || id.contains("golang") { return go }
        if id == "rs" || id.contains("rust") { return rust }
        if id.contains("java") || id.contains("kotlin") { return java }
        if id.contains("objective-c") || id == "objc" || id == "c" || id.contains("c++") || id == "cpp" {
            return cFamily
        }
        if id.contains("ruby") || id == "rb" { return ruby }
        if id.contains("yaml") || id == "yml" { return yaml }
        return generic
    }

    private static let generic = SyntaxLanguage(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["\"", "'", "`"],
        keywords: [],
        types: [],
        literals: ["true", "false", "nil", "null"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let swift = SyntaxLanguage(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["\"\"\"", "\"", "'"],
        keywords: [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "continue", "convenience", "defer", "deinit", "do", "dynamic", "else",
            "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func",
            "get", "guard", "if", "import", "in", "indirect", "init", "inout", "internal",
            "is", "lazy", "let", "mutating", "nonisolated", "nil", "open", "operator", "optional",
            "override", "private", "protocol", "public", "repeat", "required", "rethrows",
            "return", "self", "set", "some", "static", "struct", "subscript", "super", "switch",
            "throw", "throws", "true", "try", "typealias", "var", "weak", "where", "while", "willSet"
        ],
        types: [
            "Any", "Array", "Bool", "Character", "Data", "Date", "Dictionary", "Double", "Error",
            "Float", "Int", "Optional", "Result", "Self", "Set", "String", "URL", "UUID", "Void"
        ],
        literals: ["true", "false", "nil"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let python = SyntaxLanguage(
        lineComments: ["#"],
        blockComments: [],
        stringQuotes: ["\"\"\"", "'''", "\"", "'"],
        keywords: [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
            "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import",
            "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return",
            "True", "try", "while", "with", "yield"
        ],
        types: ["bool", "bytes", "dict", "float", "int", "list", "set", "str", "tuple", "type"],
        literals: ["true", "false", "none", "nil"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let shell = SyntaxLanguage(
        lineComments: ["#"],
        blockComments: [],
        stringQuotes: ["\"", "'", "`"],
        keywords: [
            "if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until",
            "case", "esac", "function", "select", "time", "return", "break", "continue",
            "export", "local", "readonly", "unset", "alias", "source", "true", "false"
        ],
        types: [],
        literals: ["true", "false"],
        commands: [
            "brew", "cd", "chmod", "cp", "curl", "docker", "echo", "git", "kubectl", "ls",
            "mkdir", "mv", "npx", "npm", "node", "pnpm", "python", "python3", "rm", "set",
            "source", "swift", "yarn"
        ],
        caseInsensitiveKeywords: false,
        shellVariables: true,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: true
    )

    private static let javascript = SyntaxLanguage(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["\"", "'", "`"],
        keywords: [
            "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "export", "extends", "false",
            "finally", "for", "from", "function", "get", "if", "import", "in", "instanceof",
            "let", "new", "null", "of", "return", "set", "static", "super", "switch", "this",
            "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield"
        ],
        types: ["Array", "Boolean", "Date", "Error", "Map", "Number", "Object", "Promise", "Set", "String", "Symbol"],
        literals: ["true", "false", "null", "undefined", "NaN"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let typescript = SyntaxLanguage(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["\"", "'", "`"],
        keywords: [
            "abstract", "any", "as", "async", "await", "boolean", "break", "case", "catch",
            "class", "const", "constructor", "continue", "declare", "default", "delete", "do",
            "else", "enum", "export", "extends", "false", "finally", "for", "from", "function",
            "get", "if", "implements", "import", "in", "infer", "instanceof", "interface",
            "keyof", "let", "module", "namespace", "never", "new", "null", "number", "object",
            "of", "private", "protected", "public", "readonly", "return", "set", "static",
            "string", "super", "switch", "this", "throw", "true", "try", "type", "typeof",
            "undefined", "unknown", "var", "void", "while", "yield"
        ],
        types: ["Array", "Boolean", "Date", "Error", "Map", "Number", "Object", "Promise", "Set", "String"],
        literals: ["true", "false", "null", "undefined"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let json = SyntaxLanguage(
        lineComments: [],
        blockComments: [],
        stringQuotes: ["\""],
        keywords: [],
        types: [],
        literals: ["true", "false", "null"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: true,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let html = SyntaxLanguage(
        lineComments: [],
        blockComments: [("<!--", "-->")],
        stringQuotes: ["\"", "'"],
        keywords: [],
        types: [],
        literals: ["true", "false", "null"],
        commands: [],
        caseInsensitiveKeywords: true,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: true,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let css = SyntaxLanguage(
        lineComments: [],
        blockComments: [("/*", "*/")],
        stringQuotes: ["\"", "'"],
        keywords: [],
        types: [],
        literals: ["true", "false", "null"],
        commands: [],
        caseInsensitiveKeywords: true,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: true,
        hashCommentNeedsLeadingSpace: false
    )

    private static let sql = SyntaxLanguage(
        lineComments: ["--"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["'", "\""],
        keywords: [
            "add", "all", "alter", "and", "as", "asc", "between", "by", "case", "column",
            "create", "delete", "desc", "distinct", "drop", "else", "end", "exists", "from",
            "group", "having", "in", "index", "insert", "into", "is", "join", "left", "like",
            "limit", "not", "null", "on", "or", "order", "outer", "primary", "references",
            "right", "select", "set", "table", "then", "union", "unique", "update", "values",
            "when", "where"
        ],
        types: ["bigint", "boolean", "date", "decimal", "float", "int", "integer", "json", "numeric", "text", "timestamp", "varchar"],
        literals: ["true", "false", "null"],
        commands: [],
        caseInsensitiveKeywords: true,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let go = SyntaxLanguage(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["`", "\"", "'"],
        keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else",
            "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
            "package", "range", "return", "select", "struct", "switch", "type", "var"
        ],
        types: ["bool", "byte", "error", "float32", "float64", "int", "int32", "int64", "rune", "string", "uint", "uint32", "uint64"],
        literals: ["true", "false", "nil"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let rust = SyntaxLanguage(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["\"", "'"],
        keywords: [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
            "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match",
            "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct",
            "super", "trait", "true", "type", "unsafe", "use", "where", "while"
        ],
        types: ["bool", "char", "f32", "f64", "i32", "i64", "Option", "Result", "String", "str", "u32", "u64", "usize", "Vec"],
        literals: ["true", "false"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let java = SyntaxLanguage(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["\"", "'"],
        keywords: [
            "abstract", "assert", "break", "case", "catch", "class", "const", "continue",
            "default", "do", "else", "enum", "extends", "final", "finally", "for", "if",
            "implements", "import", "instanceof", "interface", "native", "new", "package",
            "private", "protected", "public", "return", "static", "strictfp", "super",
            "switch", "synchronized", "this", "throw", "throws", "transient", "try", "volatile",
            "while"
        ],
        types: ["boolean", "byte", "char", "double", "float", "int", "long", "short", "String", "Object"],
        literals: ["true", "false", "null"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let cFamily = SyntaxLanguage(
        lineComments: ["//"],
        blockComments: [("/*", "*/")],
        stringQuotes: ["\"", "'"],
        keywords: [
            "auto", "break", "case", "class", "const", "continue", "default", "delete", "do",
            "else", "enum", "extern", "for", "friend", "goto", "if", "inline", "namespace",
            "new", "operator", "private", "protected", "public", "register", "return", "sizeof",
            "static", "struct", "switch", "template", "this", "throw", "try", "typedef",
            "typename", "union", "using", "virtual", "void", "volatile", "while"
        ],
        types: ["bool", "char", "double", "float", "int", "long", "short", "size_t", "std", "string", "uint32_t", "uint64_t", "void"],
        literals: ["true", "false", "nullptr", "NULL"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let ruby = SyntaxLanguage(
        lineComments: ["#"],
        blockComments: [],
        stringQuotes: ["\"", "'"],
        keywords: [
            "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do",
            "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next",
            "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then",
            "true", "undef", "unless", "until", "when", "while", "yield"
        ],
        types: ["Array", "Float", "Hash", "Integer", "String", "Symbol"],
        literals: ["true", "false", "nil"],
        commands: [],
        caseInsensitiveKeywords: false,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: false,
        hashCommentNeedsLeadingSpace: false
    )

    private static let yaml = SyntaxLanguage(
        lineComments: ["#"],
        blockComments: [],
        stringQuotes: ["\"", "'"],
        keywords: [],
        types: [],
        literals: ["true", "false", "null", "yes", "no"],
        commands: [],
        caseInsensitiveKeywords: true,
        shellVariables: false,
        jsonKeys: false,
        htmlTags: false,
        propertiesBeforeColon: true,
        hashCommentNeedsLeadingSpace: true
    )
}

private extension SyntaxHighlighter {
    static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    static func isIdentifierContinue(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    static func scanIdentifier(in code: String, from start: String.Index) -> String.Index {
        var cursor = code.index(after: start)
        while cursor < code.endIndex, isIdentifierContinue(code[cursor]) {
            cursor = code.index(after: cursor)
        }
        return cursor
    }

    static func scanNumber(in code: String, from start: String.Index) -> String.Index {
        var cursor = code.index(after: start)
        while cursor < code.endIndex {
            let character = code[cursor]
            if character.isNumber || character == "." || character == "_" || character == "x" || character == "X" {
                cursor = code.index(after: cursor)
            } else if character == "e" || character == "E" {
                cursor = code.index(after: cursor)
                if cursor < code.endIndex, code[cursor] == "+" || code[cursor] == "-" {
                    cursor = code.index(after: cursor)
                }
            } else {
                break
            }
        }
        return cursor
    }

    static func scanString(in code: String, from start: String.Index, quote: String) -> String.Index {
        var cursor = code.index(start, offsetBy: quote.count, limitedBy: code.endIndex) ?? code.endIndex
        let allowsNewlines = quote.count >= 3
        while cursor < code.endIndex {
            if code[cursor] == "\\" {
                cursor = code.index(cursor, offsetBy: 2, limitedBy: code.endIndex) ?? code.endIndex
                continue
            }
            if code[cursor...].hasPrefix(quote) {
                return code.index(cursor, offsetBy: quote.count, limitedBy: code.endIndex) ?? code.endIndex
            }
            if !allowsNewlines, code[cursor] == "\n" {
                return cursor
            }
            cursor = code.index(after: cursor)
        }
        return code.endIndex
    }

    static func scanShellVariable(in code: String, from start: String.Index) -> String.Index {
        var cursor = code.index(after: start)
        guard cursor < code.endIndex else { return cursor }
        if code[cursor] == "{" {
            cursor = code.index(after: cursor)
            while cursor < code.endIndex, code[cursor] != "}" {
                cursor = code.index(after: cursor)
            }
            if cursor < code.endIndex { cursor = code.index(after: cursor) }
            return cursor
        }
        while cursor < code.endIndex, isIdentifierContinue(code[cursor]) || code[cursor] == "?" || code[cursor] == "#" {
            cursor = code.index(after: cursor)
        }
        return cursor
    }

    static func isStartOfLine(_ index: String.Index, in code: String) -> Bool {
        guard index > code.startIndex else { return true }
        let previous = code[code.index(before: index)]
        return previous.isWhitespace
    }

    static func isFunctionCall(after index: String.Index, in code: String) -> Bool {
        var cursor = index
        while cursor < code.endIndex, code[cursor] == " " || code[cursor] == "\t" {
            cursor = code.index(after: cursor)
        }
        return cursor < code.endIndex && code[cursor] == "("
    }

    static func isFollowedByColon(after index: String.Index, in code: String) -> Bool {
        var cursor = index
        while cursor < code.endIndex, code[cursor] == " " || code[cursor] == "\t" {
            cursor = code.index(after: cursor)
        }
        return cursor < code.endIndex && code[cursor] == ":"
    }

    static func isJSONKey(in code: String, range: Range<String.Index>) -> Bool {
        var cursor = range.upperBound
        while cursor < code.endIndex, code[cursor] == " " || code[cursor] == "\t" {
            cursor = code.index(after: cursor)
        }
        return cursor < code.endIndex && code[cursor] == ":"
    }

    static func scanHTMLTag(in code: String, from start: String.Index) -> String.Index? {
        guard code[start...].hasPrefix("<") else { return nil }
        let end = code[start...].firstIndex(of: ">") ?? code.endIndex
        guard end > start else { return nil }
        return code.index(after: end)
    }
}

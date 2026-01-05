//
//  SyntaxHighlighter.swift
//  powertoys
//

import Foundation
import SwiftUI

enum SyntaxHighlighter {

    enum TokenType {
        case keyword
        case string
        case comment
        case number
        case type
        case function
        case property
        case `operator`

        var color: Color {
            switch self {
            case .keyword: return .pink
            case .string: return .red
            case .comment: return Color(nsColor: .systemGray)
            case .number: return .purple
            case .type: return .cyan
            case .function: return .blue
            case .property: return .teal
            case .operator: return .orange
            }
        }
    }

    struct LanguageDefinition {
        let keywords: Set<String>
        let types: Set<String>
        let stringPattern: String
        let commentPatterns: [String]
        let numberPattern: String
    }

    static let languages: [String: LanguageDefinition] = [
        "swift": LanguageDefinition(
            keywords: ["func", "var", "let", "if", "else", "guard", "return", "import", "class", "struct", "enum", "protocol", "extension", "private", "public", "internal", "fileprivate", "static", "override", "final", "lazy", "weak", "unowned", "async", "await", "throws", "throw", "try", "catch", "for", "in", "while", "repeat", "switch", "case", "default", "break", "continue", "fallthrough", "where", "self", "Self", "super", "init", "deinit", "subscript", "typealias", "associatedtype", "some", "any", "nil", "true", "false", "inout", "mutating", "nonmutating", "convenience", "required", "optional", "indirect", "dynamic", "get", "set", "willSet", "didSet", "defer", "do", "is", "as"],
            types: ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "URL", "Data", "Date", "UUID", "Void", "Any", "AnyObject", "Never"],
            stringPattern: #"\"(?:[^\"\\]|\\.)*\""#,
            commentPatterns: [#"//.*$"#, #"/\*[\s\S]*?\*/"#],
            numberPattern: #"\b\d+\.?\d*\b"#
        ),
        "python": LanguageDefinition(
            keywords: ["def", "class", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "as", "import", "from", "return", "yield", "raise", "pass", "break", "continue", "and", "or", "not", "in", "is", "lambda", "True", "False", "None", "global", "nonlocal", "assert", "del", "async", "await"],
            types: ["str", "int", "float", "bool", "list", "dict", "set", "tuple", "bytes", "type", "object"],
            stringPattern: #"(?:\"\"\"[\s\S]*?\"\"\"|\'\'\'[\s\S]*?\'\'\'|\"(?:[^\"\\]|\\.)*\"|\'(?:[^\'\\]|\\.)*\')"#,
            commentPatterns: [#"#.*$"#],
            numberPattern: #"\b\d+\.?\d*\b"#
        ),
        "javascript": LanguageDefinition(
            keywords: ["function", "const", "let", "var", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "throw", "try", "catch", "finally", "new", "delete", "typeof", "instanceof", "void", "this", "super", "class", "extends", "static", "get", "set", "async", "await", "yield", "import", "export", "from", "as", "true", "false", "null", "undefined", "NaN", "Infinity"],
            types: ["Array", "Object", "String", "Number", "Boolean", "Function", "Symbol", "BigInt", "Map", "Set", "WeakMap", "WeakSet", "Promise", "Date", "RegExp", "Error"],
            stringPattern: #"(?:\"(?:[^\"\\]|\\.)*\"|\'(?:[^\'\\]|\\.)*\'|`(?:[^`\\]|\\.)*`)"#,
            commentPatterns: [#"//.*$"#, #"/\*[\s\S]*?\*/"#],
            numberPattern: #"\b\d+\.?\d*\b"#
        ),
        "typescript": LanguageDefinition(
            keywords: ["function", "const", "let", "var", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "throw", "try", "catch", "finally", "new", "delete", "typeof", "instanceof", "void", "this", "super", "class", "extends", "static", "get", "set", "async", "await", "yield", "import", "export", "from", "as", "true", "false", "null", "undefined", "type", "interface", "enum", "namespace", "module", "declare", "abstract", "implements", "private", "public", "protected", "readonly", "keyof", "infer", "extends", "never", "unknown", "any"],
            types: ["Array", "Object", "String", "Number", "Boolean", "Function", "Symbol", "BigInt", "Map", "Set", "WeakMap", "WeakSet", "Promise", "Date", "RegExp", "Error", "Partial", "Required", "Readonly", "Record", "Pick", "Omit", "Exclude", "Extract", "NonNullable", "ReturnType", "InstanceType"],
            stringPattern: #"(?:\"(?:[^\"\\]|\\.)*\"|\'(?:[^\'\\]|\\.)*\'|`(?:[^`\\]|\\.)*`)"#,
            commentPatterns: [#"//.*$"#, #"/\*[\s\S]*?\*/"#],
            numberPattern: #"\b\d+\.?\d*\b"#
        ),
        "go": LanguageDefinition(
            keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var", "true", "false", "nil", "iota"],
            types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr"],
            stringPattern: #"(?:\"(?:[^\"\\]|\\.)*\"|`[^`]*`)"#,
            commentPatterns: [#"//.*$"#, #"/\*[\s\S]*?\*/"#],
            numberPattern: #"\b\d+\.?\d*\b"#
        ),
        "rust": LanguageDefinition(
            keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"],
            types: ["bool", "char", "str", "u8", "u16", "u32", "u64", "u128", "usize", "i8", "i16", "i32", "i64", "i128", "isize", "f32", "f64", "String", "Vec", "Option", "Result", "Box", "Rc", "Arc", "Cell", "RefCell"],
            stringPattern: #"\"(?:[^\"\\]|\\.)*\""#,
            commentPatterns: [#"//.*$"#, #"/\*[\s\S]*?\*/"#],
            numberPattern: #"\b\d+\.?\d*\b"#
        ),
        "bash": LanguageDefinition(
            keywords: ["if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until", "do", "done", "in", "function", "select", "time", "coproc", "return", "exit", "break", "continue", "local", "declare", "typeset", "export", "readonly", "unset", "shift", "source", "alias", "true", "false"],
            types: [],
            stringPattern: #"(?:\"(?:[^\"\\]|\\.)*\"|\'[^\']*\')"#,
            commentPatterns: [#"#.*$"#],
            numberPattern: #"\b\d+\b"#
        ),
        "json": LanguageDefinition(
            keywords: ["true", "false", "null"],
            types: [],
            stringPattern: #"\"(?:[^\"\\]|\\.)*\""#,
            commentPatterns: [],
            numberPattern: #"-?\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#
        )
    ]

    static func highlight(_ code: String, language: String?) -> AttributedString {
        var result = AttributedString(code)

        guard let lang = language?.lowercased() else { return result }
        guard let definition = languages[lang] ?? resolveLanguage(lang).flatMap({ languages[$0] }) else {
            return result
        }

        for pattern in definition.commentPatterns {
            applyPattern(pattern, to: &result, in: code, type: .comment)
        }

        applyPattern(definition.stringPattern, to: &result, in: code, type: .string)
        applyPattern(definition.numberPattern, to: &result, in: code, type: .number)

        for keyword in definition.keywords {
            applyWordPattern(keyword, to: &result, in: code, type: .keyword)
        }

        for type in definition.types {
            applyWordPattern(type, to: &result, in: code, type: .type)
        }

        return result
    }

    private static func resolveLanguage(_ lang: String) -> String? {
        let aliases: [String: String] = [
            "js": "javascript",
            "ts": "typescript",
            "py": "python",
            "sh": "bash",
            "shell": "bash",
            "zsh": "bash",
            "rs": "rust"
        ]
        return aliases[lang]
    }

    private static func applyPattern(_ pattern: String, to result: inout AttributedString, in code: String, type: TokenType) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }

        let nsCode = code as NSString
        let matches = regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length))

        for match in matches {
            guard let swiftRange = Range(match.range, in: code),
                  let attrStart = AttributedString.Index(swiftRange.lowerBound, within: result),
                  let attrEnd = AttributedString.Index(swiftRange.upperBound, within: result) else {
                continue
            }

            result[attrStart..<attrEnd].foregroundColor = type.color
        }
    }

    private static func applyWordPattern(_ word: String, to result: inout AttributedString, in code: String, type: TokenType) {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        applyPattern(pattern, to: &result, in: code, type: type)
    }
}

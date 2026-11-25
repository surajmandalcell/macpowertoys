import Foundation

/// Where a listener's row icon comes from, in the order Portman tries them.
nonisolated enum PortmanIconSource: String, Sendable {
    case tool, app, runtime, startedBy, fallback
}

/// The one place for the ssh glyph and the unknown-process icon (see `spec/icons.md`).
nonisolated enum PortmanRowIcon {
    static let sshSymbol = "network.badge.shield.half.filled"
    static let sshToolIDs: Set<String> = ["ssh", "openssh"]
    /// The unknown-process icon is iTerm's, else Terminal's, trimmed to its opaque bounds. Nothing is bundled.
    static let fallbackBundleID = "com.googlecode.iterm2"
    static let fallbackAppPath = "/System/Applications/Utilities/Terminal.app"
}

/// One process command line, read the way the dev-icon catalog's reference matcher (`check.mjs`) reads it.
nonisolated struct PortmanCommandContext {
    let argv: [String]
    let args: [String]
    let name: String
    let executable: String
    let title: String
    private(set) var module: String?
    private(set) var script: String?
    private(set) var following: [String] = []

    private static let takesValue: Set<String> = ["-W", "-X", "-r", "-d", "--require", "--import", "--loader",
                                                  "--experimental-loader", "--env-file", "--conditions", "-I", "-C", "-F"]

    init(argv: [String], title: String? = nil, executablePath: String? = nil) {
        self.argv = argv
        args = Array(argv.dropFirst())
        name = Self.basename(argv.first ?? "").lowercased()
        executable = Self.basename(executablePath ?? "").lowercased()
        self.title = (title ?? argv.joined(separator: " ")).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isPython = Self.matches(name, #"^(?:pythonw?|pypy)(?:\d+(?:\.\d+){0,2})?[td]?$"#)
        guard isPython || Self.matches(name, #"^(?:node(?:js)?|bun|deno|ruby(?:\d+(?:\.\d+)*)?|php(?:\d+(?:\.\d+)*)?|perl|lua|bash|sh|zsh)$"#)
        else { return }
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "-m" && isPython { module = index + 1 < args.count ? args[index + 1] : nil; return }
            if ["-c", "-e", "--eval", "-p", "--print"].contains(arg) { return }
            if arg == "--" || !arg.hasPrefix("-") {
                let scriptIndex = arg == "--" ? index + 1 : index
                script = scriptIndex < args.count ? args[scriptIndex] : nil
                following = Array(args.dropFirst(scriptIndex + 1))
                return
            }
            index += Self.takesValue.contains(arg) ? 2 : 1
        }
    }

    /// A ps-style command line, split like a shell would: quotes and backslashes group words.
    init(command: String) {
        self.init(argv: Self.split(command), title: command)
    }

    static func split(_ command: String) -> [String] {
        var words: [String] = []
        var word: String?
        var quote: Character?
        var escaped = false
        for character in command {
            if escaped { word = (word ?? "") + String(character); escaped = false; continue }
            if quote == "'" {
                if character == "'" { quote = nil } else { word = (word ?? "") + String(character) }
                continue
            }
            if character == "\\" { escaped = true; word = word ?? ""; continue }
            if quote == "\"" {
                if character == "\"" { quote = nil } else { word = (word ?? "") + String(character) }
                continue
            }
            if character == "'" || character == "\"" { quote = character; word = word ?? ""; continue }
            if character.isWhitespace {
                if let finished = word { words.append(finished) }
                word = nil
            } else {
                word = (word ?? "") + String(character)
            }
        }
        if let word { words.append(word) }
        return words
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || "_.$@+-".contains(character)
    }

    /// `signature` occurs in `arg` and does not run into a longer word on either side.
    static func contains(_ arg: String, signature: String) -> Bool {
        guard let first = signature.first, let last = signature.last else { return false }
        let haystack = signature.hasPrefix("/") && !arg.hasPrefix("/") ? "/" + arg : arg
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: signature, range: searchStart..<haystack.endIndex) {
            let before = found.lowerBound > haystack.startIndex ? haystack[haystack.index(before: found.lowerBound)] : nil
            let after = found.upperBound < haystack.endIndex ? haystack[found.upperBound] : nil
            if (!isWordCharacter(first) || !isWordCharacter(before)) && (!isWordCharacter(last) || !isWordCharacter(after)) {
                return true
            }
            searchStart = haystack.index(after: found.lowerBound)
        }
        return false
    }
}

nonisolated struct PortmanDevTool: Decodable, Sendable {
    struct Match: Decodable, Sendable {
        let exec, titlePrefix, argContains, pythonModule, scriptArg: [String]
        let argvPrefix: [[String]]?
        let argFlags: [String]?

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            func list(_ key: CodingKeys) throws -> [String] { try values.decodeIfPresent([String].self, forKey: key) ?? [] }
            exec = try list(.exec)
            titlePrefix = try list(.titlePrefix)
            argContains = try list(.argContains)
            pythonModule = try list(.pythonModule)
            scriptArg = try list(.scriptArg)
            argvPrefix = try values.decodeIfPresent([[String]].self, forKey: .argvPrefix)
            argFlags = try values.decodeIfPresent([String].self, forKey: .argFlags)
        }

        private enum CodingKeys: String, CodingKey {
            case exec, titlePrefix, argContains, pythonModule, scriptArg, argvPrefix, argFlags
        }
    }

    let id: String
    let name: String
    let kind: String
    let match: Match
    let priority: Int
    let icon: String?
    let examples: [String]?

    var isRuntime: Bool { kind == "runtime" }

    func matches(_ context: PortmanCommandContext) -> Bool {
        if match.titlePrefix.contains(where: { context.title.hasPrefix($0.lowercased()) }) { return true }
        if match.argvPrefix?.contains(where: { prefix in
            guard let head = prefix.first, head.lowercased() == context.name else { return false }
            return prefix.dropFirst().enumerated().allSatisfy { offset, expected in
                Self.sameCommandArg(expected, offset < context.args.count ? context.args[offset] : nil)
            }
        }) == true { return true }
        if match.exec.contains(where: { $0.lowercased() == context.name || $0.lowercased() == context.executable }),
           match.argFlags.map({ flags in flags.contains { flag in context.args.contains { arg in
               arg == flag || flag.count == 2 && flag.hasPrefix("-") && arg.hasPrefix(flag)
                   || flag.hasSuffix("=") && arg.hasPrefix(flag) } } }) ?? true {
            return true
        }
        if let module = context.module, match.pythonModule.contains(module) { return true }
        if !match.scriptArg.isEmpty {
            guard let script = context.script,
                  match.scriptArg.contains(PortmanCommandContext.basename(script)) else { return false }
            return match.argContains.isEmpty || match.argContains.contains { signature in
                ([script] + context.following).contains { arg in
                    signature.range(of: #"^[\w-]+$"#, options: .regularExpression) != nil
                        ? arg == signature : PortmanCommandContext.contains(arg, signature: signature)
                }
            }
        }
        return match.argContains.contains { signature in
            context.argv.contains { PortmanCommandContext.contains($0, signature: signature) }
        }
    }

    private static func sameCommandArg(_ expected: String, _ actual: String?) -> Bool {
        guard let actual else { return false }
        if expected == actual { return true }
        if expected.hasPrefix("node_modules/") { return actual.hasSuffix("/" + expected) }
        if expected.hasPrefix("./") { return actual.hasSuffix("/" + expected.dropFirst(2)) }
        return false
    }
}

nonisolated struct PortmanDevToolCatalog: Sendable {
    let items: [PortmanDevTool]
    let iconFolder: URL?

    /// Loaded once, on first use from the background scan.
    static let bundled: PortmanDevToolCatalog = {
        guard let folder = Bundle.main.url(forResource: "DevIcons", withExtension: "bundle"),
              let catalog = try? load(folder) else { return PortmanDevToolCatalog(items: [], iconFolder: nil) }
        return catalog
    }()

    static func load(_ folder: URL) throws -> PortmanDevToolCatalog {
        let data = try Data(contentsOf: folder.appendingPathComponent("catalog.json"))
        return PortmanDevToolCatalog(items: try JSONDecoder().decode([PortmanDevTool].self, from: data),
                                     iconFolder: folder.appendingPathComponent("png"))
    }

    /// Every match, highest priority first, then by id.
    func matching(_ context: PortmanCommandContext) -> [PortmanDevTool] {
        items.filter { $0.matches(context) }
            .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.id < $1.id }
    }

    func iconPath(for item: PortmanDevTool?) -> String? {
        guard let file = item?.icon, let iconFolder else { return nil }
        let path = iconFolder.appendingPathComponent(file).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}

/// Who runs a listener: the matched tool, the app that started it, and the row icon.
nonisolated struct PortmanOrigin: Sendable, Equatable {
    var appBundlePath: String?
    var toolName: String?
    var startedBy: String?
    var startedByAppPath: String?
    var iconPath: String?
    /// An SF Symbol drawn instead of an image, such as the ssh glyph.
    var symbol: String?
    var iconSource = PortmanIconSource.fallback

    /// Icon order: catalog tool, .app ancestor, catalog runtime, the app from the environment, then the glyph.
    static func resolve(_ context: PortmanCommandContext, catalog: PortmanDevToolCatalog, ancestor: String?,
                        environment: PortmanLaunchEnvironment?,
                        startedByApp: (path: String, name: String)?) -> PortmanOrigin {
        let matches = catalog.matching(context)
        let tool = matches.first { !$0.isRuntime }
        let runtime = matches.first(where: \.isRuntime)
        var origin = PortmanOrigin(appBundlePath: ancestor, toolName: (tool ?? runtime)?.name,
                                   startedBy: environment?.startedBy(appName: startedByApp?.name),
                                   startedByAppPath: startedByApp?.path)
        if context.name == "ssh" || tool.map({ PortmanRowIcon.sshToolIDs.contains($0.id) }) == true {
            origin.symbol = PortmanRowIcon.sshSymbol
            origin.iconSource = .tool
            return origin
        }
        let candidates: [(String?, PortmanIconSource)] = [
            (catalog.iconPath(for: tool), .tool), (ancestor, .app),
            (catalog.iconPath(for: runtime), .runtime), (startedByApp?.path, .startedBy)
        ]
        if let found = candidates.first(where: { $0.0 != nil }) {
            origin.iconPath = found.0
            origin.iconSource = found.1
        }
        return origin
    }
}

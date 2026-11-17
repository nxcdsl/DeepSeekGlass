import SwiftUI
import UIKit

// MARK: - Blocks

struct MDBlock: Identifiable {
    enum Kind {
        case heading(Int, String)
        case paragraph(String)
        case bullet(Int, String)
        case ordered(Int, Int, String)
        case code(String, String)
        case quote(String)
        case table([String], [[String]])
        case math(String)
        case divider
    }

    var id: Int
    var kind: Kind
}

enum MarkdownParser {
    static func parse(_ raw: String) -> [MDBlock] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MDBlock] = []
        var paragraph: [String] = []
        var index = 0
        var i = 0

        func nextID() -> Int {
            defer { index += 1 }
            return index
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll()
            guard !text.isEmpty else { return }
            blocks.append(MDBlock(id: nextID(), kind: .paragraph(text)))
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var code: [String] = []
                while i < lines.count {
                    let candidate = lines[i]
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    code.append(candidate)
                    i += 1
                }
                blocks.append(MDBlock(id: nextID(), kind: .code(language, code.joined(separator: "\n"))))
                continue
            }

            if trimmed.hasPrefix("$$") {
                flushParagraph()
                if trimmed.count > 4, trimmed.hasSuffix("$$") {
                    let body = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                    blocks.append(MDBlock(id: nextID(), kind: .math(body)))
                    i += 1
                    continue
                }
                i += 1
                var math: [String] = []
                while i < lines.count {
                    let candidate = lines[i]
                    if candidate.trimmingCharacters(in: .whitespaces).hasSuffix("$$") {
                        let body = candidate.replacingOccurrences(of: "$$", with: "")
                        math.append(body)
                        i += 1
                        break
                    }
                    math.append(candidate)
                    i += 1
                }
                blocks.append(MDBlock(id: nextID(), kind: .math(math.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(MDBlock(id: nextID(), kind: .divider))
                i += 1
                continue
            }

            if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(MDBlock(id: nextID(), kind: .heading(heading.0, heading.1)))
                i += 1
                continue
            }

            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let headers = cells(trimmed)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    guard candidate.contains("|"), !candidate.isEmpty else { break }
                    rows.append(cells(candidate))
                    i += 1
                }
                blocks.append(MDBlock(id: nextID(), kind: .table(headers, rows)))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quote.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(MDBlock(id: nextID(), kind: .quote(quote.joined(separator: "\n"))))
                continue
            }

            if let bullet = bulletItem(line) {
                flushParagraph()
                blocks.append(MDBlock(id: nextID(), kind: .bullet(bullet.0, bullet.1)))
                i += 1
                continue
            }

            if let ordered = orderedItem(line) {
                flushParagraph()
                blocks.append(MDBlock(id: nextID(), kind: .ordered(ordered.0, ordered.1, ordered.2)))
                i += 1
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }

        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func bulletItem(_ line: String) -> (Int, String)? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(marker) {
                return (leading / 2, String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> (Int, Int, String)? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let numberText = String(trimmed[..<dot])
        guard let number = Int(numberText), number >= 0, number < 1000 else { return nil }
        let after = trimmed.index(after: dot)
        guard after < trimmed.endIndex, trimmed[after] == " " else { return nil }
        return (leading / 2, number, String(trimmed[trimmed.index(after: after)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        let allowed = CharacterSet(charactersIn: "|-: ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - View

struct MarkdownView: View {
    var text: String
    @Environment(\.dsFontScale) private var scale

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            let size: CGFloat = level == 1 ? 23 : (level == 2 ? 20 : 18)
            inline(text, size: size, weight: .semibold)
                .padding(.top, level <= 2 ? 8 : 4)

        case .paragraph(let text):
            inline(text, size: 17)
                .lineSpacing(6 * CGFloat(scale))

        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .offset(y: -3)
                inline(text, size: 17)
                    .lineSpacing(5 * CGFloat(scale))
            }
            .padding(.leading, CGFloat(indent) * 18 + 4)

        case .ordered(let indent, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .dsFont(17, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                inline(text, size: 17)
                    .lineSpacing(5 * CGFloat(scale))
            }
            .padding(.leading, CGFloat(indent) * 18)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Theme.accent.opacity(0.45))
                    .frame(width: 3)
                inline(text, size: 16, color: .secondary)
                    .lineSpacing(5 * CGFloat(scale))
            }
            .padding(.vertical, 2)

        case .table(let headers, let rows):
            MarkdownTable(headers: headers, rows: rows)

        case .math(let latex):
            MathBlock(latex: latex)

        case .divider:
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 0.7)
                .padding(.vertical, 4)
        }
    }

    private func inline(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight = .regular,
        color: Color = .primary
    ) -> some View {
        Text(inlineAttributed(text, size: size * CGFloat(scale), weight: weight, color: color))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func inlineAttributed(
        _ raw: String,
        size: CGFloat,
        weight: Font.Weight,
        color: Color
    ) -> AttributedString {
        let prepared = LaTeX.inlineMath(in: raw)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var attributed = (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(prepared)
        attributed.font = .system(size: size, weight: weight)
        attributed.foregroundColor = color

        let runs = attributed.runs.map { ($0.range, $0.inlinePresentationIntent, $0.link) }
        for (range, intent, link) in runs {
            if let intent {
                if intent.contains(.code) {
                    attributed[range].font = .system(size: size * 0.92, design: .monospaced)
                    attributed[range].backgroundColor = Color.primary.opacity(0.07)
                }
                if intent.contains(.stronglyEmphasized) {
                    attributed[range].font = .system(size: size, weight: .semibold)
                }
                if intent.contains(.emphasized) {
                    attributed[range].font = .system(size: size, weight: weight).italic()
                }
            }
            if link != nil {
                attributed[range].foregroundColor = Theme.accent
            }
        }
        return attributed
    }
}

// MARK: - Code

struct CodeBlockView: View {
    var language: String
    var code: String
    @State private var copied = false
    @Environment(\.dsFontScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "代码" : language)
                    .dsFont(11, weight: .medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    Haptics.success()
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "square.on.square")
                        .dsFont(12, weight: .medium)
                        .foregroundStyle(copied ? Theme.accent : .secondary)
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制代码")
            }
            .padding(.horizontal, 13)
            .padding(.top, 9)
            .padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13 * CGFloat(scale), design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineSpacing(3)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 12)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
        }
    }
}

// MARK: - Table

struct MarkdownTable: View {
    var headers: [String]
    var rows: [[String]]
    @Environment(\.dsFontScale) private var scale

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(inline(header))
                            .dsFont(14, weight: .semibold)
                            .padding(.vertical, 9)
                            .frame(minWidth: 70, alignment: .leading)
                    }
                }
                .background(Color.primary.opacity(0.06))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { column, _ in
                            Text(inline(row[safe: column] ?? ""))
                                .dsFont(14)
                                .padding(.vertical, 8)
                                .frame(minWidth: 70, alignment: .leading)
                        }
                    }
                    .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
        }
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        attributed.font = .system(size: 14 * CGFloat(scale))
        return attributed
    }
}

// MARK: - Math

struct MathBlock: View {
    var latex: String
    @Environment(\.dsFontScale) private var scale

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(LaTeX.unicode(latex))
                .font(.system(size: 19 * CGFloat(scale), design: .serif))
                .italic()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

// MARK: - LaTeX to Unicode (display-only fallback)

enum LaTeX {
    private static let greek: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\epsilon": "ε",
        "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ", "\\iota": "ι", "\\kappa": "κ",
        "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\pi": "π",
        "\\rho": "ρ", "\\sigma": "σ", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
        "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω", "\\Gamma": "Γ", "\\Delta": "Δ",
        "\\Theta": "Θ", "\\Lambda": "Λ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Phi": "Φ",
        "\\Psi": "Ψ", "\\Omega": "Ω"
    ]

    private static let symbols: [String: String] = [
        "\\times": "×", "\\cdot": "·", "\\div": "÷", "\\pm": "±", "\\mp": "∓",
        "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥", "\\neq": "≠", "\\ne": "≠",
        "\\approx": "≈", "\\equiv": "≡", "\\infty": "∞", "\\sum": "∑", "\\prod": "∏",
        "\\int": "∫", "\\partial": "∂", "\\nabla": "∇", "\\in": "∈", "\\notin": "∉",
        "\\subset": "⊂", "\\supset": "⊃", "\\cup": "∪", "\\cap": "∩", "\\to": "→",
        "\\rightarrow": "→", "\\leftarrow": "←", "\\Rightarrow": "⇒", "\\Leftrightarrow": "⇔",
        "\\angle": "∠", "\\perp": "⊥", "\\parallel": "∥", "\\degree": "°", "\\circ": "∘"
    ]

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷",
        "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ",
        "k": "ᵏ", "m": "ᵐ", "p": "ᵖ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ"
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇",
        "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "i": "ᵢ", "o": "ₒ", "u": "ᵤ", "x": "ₓ", "n": "ₙ", "m": "ₘ"
    ]

    static func inlineMath(in text: String) -> String {
        guard text.contains("$") else { return text }
        var result = text
        let pattern = "(?<!\\\\)\\$([^$\\n]{1,120}?)\\$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let full = Range(match.range, in: result),
                  let inner = Range(match.range(at: 1), in: result) else { continue }
            let converted = unicode(String(result[inner]))
            result.replaceSubrange(full, with: converted)
        }
        return result
    }

    static func unicode(_ input: String) -> String {
        var s = input

        s = replace(#"\\frac\{([^{}]+)\}\{([^{}]+)\}"#, in: s) { "\($0[0])⁄\($0[1])" }
        s = replace(#"\\[dt]frac\{([^{}]+)\}\{([^{}]+)\}"#, in: s) { "\($0[0])⁄\($0[1])" }
        s = replace(#"\\sqrt\{([^{}]+)\}"#, in: s) { "√(\($0[0]))" }
        s = replace(#"\\(?:text|mathrm|mathbf)\{([^{}]*)\}"#, in: s) { $0[0] }

        for (key, value) in greek.sorted(by: { $0.key.count > $1.key.count }) {
            s = s.replacingOccurrences(of: key, with: value)
        }
        for (key, value) in symbols.sorted(by: { $0.key.count > $1.key.count }) {
            s = s.replacingOccurrences(of: key, with: value)
        }

        s = replace(#"\^\{([^{}]+)\}"#, in: s) { text in
            String(text[0].map { superscripts[$0] ?? $0 })
        }
        s = replace(#"\^([A-Za-z0-9+\-=()])"#, in: s) { text in
            String(text[0].map { superscripts[$0] ?? $0 })
        }
        s = replace(#"_\{([^{}]+)\}"#, in: s) { text in
            String(text[0].map { subscripts[$0] ?? $0 })
        }
        s = replace(#"_([A-Za-z0-9+\-=()])"#, in: s) { text in
            String(text[0].map { subscripts[$0] ?? $0 })
        }

        for token in ["\\left", "\\right", "\\,", "\\;", "\\!", "\\quad", "\\qquad", "\\displaystyle", "\\limits"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        s = s.replacingOccurrences(of: "\\\\", with: "\n")
        s = s.replacingOccurrences(of: "{", with: "")
        s = s.replacingOccurrences(of: "}", with: "")
        s = s.replacingOccurrences(of: "&", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ pattern: String, in source: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard !matches.isEmpty else { return source }
        var result = source
        for match in matches.reversed() {
            guard let full = Range(match.range, in: result) else { continue }
            var groups: [String] = []
            for group in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: group), in: result) {
                    groups.append(String(result[range]))
                } else {
                    groups.append("")
                }
            }
            result.replaceSubrange(full, with: transform(groups))
        }
        return result
    }
}

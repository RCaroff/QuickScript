import Cocoa

/// Convertit du texte contenant des séquences ANSI (CSI/SGR) en NSAttributedString
/// avec couleurs, bold, italic, underline appliqués. Les séquences non SGR
/// (terminées par autre chose que 'm') sont strippées silencieusement. Les
/// codes SGR non reconnus sont ignorés sans casser le rendu.
enum ANSIParser {

    static func attributedString(from text: String,
                                  baseFont: NSFont,
                                  baseColor: NSColor = NSColor.labelColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let esc: Character = "\u{1B}"

        var attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor,
        ]

        var index = text.startIndex
        var bufferStart = text.startIndex

        while index < text.endIndex {
            if text[index] != esc {
                index = text.index(after: index)
                continue
            }
            // Flush buffer
            if bufferStart < index {
                result.append(NSAttributedString(
                    string: String(text[bufferStart..<index]),
                    attributes: attrs
                ))
            }

            let afterEsc = text.index(after: index)
            // Séquence CSI : ESC + '['
            if afterEsc < text.endIndex && text[afterEsc] == "[" {
                let paramStart = text.index(after: afterEsc)
                var seqEnd = paramStart
                while seqEnd < text.endIndex && !text[seqEnd].isLetter {
                    seqEnd = text.index(after: seqEnd)
                }
                if seqEnd < text.endIndex {
                    let codeStr = String(text[paramStart..<seqEnd])
                    if text[seqEnd] == "m" {
                        applySGR(codeStr, to: &attrs, baseFont: baseFont, baseColor: baseColor)
                    }
                    index = text.index(after: seqEnd)
                    bufferStart = index
                    continue
                }
            }
            // ESC isolé ou séquence mal formée → skip ESC
            index = afterEsc
            bufferStart = index
        }

        if bufferStart < text.endIndex {
            result.append(NSAttributedString(
                string: String(text[bufferStart..<text.endIndex]),
                attributes: attrs
            ))
        }

        return result
    }

    /// Applique un ensemble de codes SGR (séparés par ';') à `attrs`.
    private static func applySGR(_ code: String,
                                  to attrs: inout [NSAttributedString.Key: Any],
                                  baseFont: NSFont,
                                  baseColor: NSColor) {
        let parts: [Int] = code.isEmpty
            ? [0]
            : code.split(separator: ";").compactMap { Int($0) }

        var bold = (attrs[.font] as? NSFont)?
            .fontDescriptor.symbolicTraits.contains(.bold) ?? false
        var italic = (attrs[.font] as? NSFont)?
            .fontDescriptor.symbolicTraits.contains(.italic) ?? false
        var underline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0

        var i = 0
        while i < parts.count {
            let n = parts[i]
            switch n {
            case 0:
                attrs[.foregroundColor] = baseColor
                attrs.removeValue(forKey: .backgroundColor)
                bold = false; italic = false; underline = false
            case 1:  bold = true
            case 3:  italic = true
            case 4:  underline = true
            case 22: bold = false
            case 23: italic = false
            case 24: underline = false
            case 30: attrs[.foregroundColor] = NSColor.textColor.withAlphaComponent(0.85)
            case 31: attrs[.foregroundColor] = NSColor.systemRed
            case 32: attrs[.foregroundColor] = NSColor.systemGreen
            case 33: attrs[.foregroundColor] = NSColor.systemYellow
            case 34: attrs[.foregroundColor] = NSColor.systemBlue
            case 35: attrs[.foregroundColor] = NSColor.systemPurple
            case 36: attrs[.foregroundColor] = NSColor.systemTeal
            case 37: attrs[.foregroundColor] = NSColor.secondaryLabelColor
            case 39: attrs[.foregroundColor] = baseColor
            case 90: attrs[.foregroundColor] = NSColor.systemGray
            case 91: attrs[.foregroundColor] = NSColor.systemPink
            case 92: attrs[.foregroundColor] = NSColor.systemMint
            case 93: attrs[.foregroundColor] = NSColor.systemOrange
            case 94: attrs[.foregroundColor] = NSColor.systemCyan
            case 95: attrs[.foregroundColor] = NSColor.systemPink
            case 96: attrs[.foregroundColor] = NSColor.systemTeal
            case 97: attrs[.foregroundColor] = baseColor
            case 40...47, 100...107: break
            case 49: attrs.removeValue(forKey: .backgroundColor)
            case 38, 48:
                if i + 1 < parts.count {
                    let mode = parts[i + 1]
                    if mode == 5, i + 2 < parts.count { i += 2 }
                    else if mode == 2, i + 4 < parts.count { i += 4 }
                }
            default: break
            }
            i += 1
        }

        var traits = NSFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        attrs[.font] = NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont

        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attrs.removeValue(forKey: .underlineStyle)
        }
    }
}

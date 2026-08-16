//
//  WrapTextLayout.swift
//  lucky7
//

import UIKit

enum WrapTextLayout {
    struct Result {
        let lines: [String]
        let didFit: Bool

        var text: String { lines.joined(separator: "\n") }
    }

    static func lines(
        for text: String,
        font: UIFont,
        maxWidth: CGFloat,
        maxLines: Int,
        truncatesOverflow: Bool = false
    ) -> Result {
        let words = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !words.isEmpty, maxLines > 0 else {
            return Result(lines: [], didFit: true)
        }

        let singleLine = words.joined(separator: " ")
        if measuredWidth(singleLine, font: font) <= maxWidth {
            return Result(lines: [singleLine], didFit: true)
        }

        if maxLines == 2, words.count > 1,
           let balanced = balancedTwoLines(words: words, font: font, maxWidth: maxWidth) {
            return Result(lines: balanced, didFit: true)
        }

        var lines: [String] = []
        var current = ""
        var didFit = true

        for (index, word) in words.enumerated() {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if measuredWidth(candidate, font: font) <= maxWidth {
                current = candidate
                continue
            }

            if current.isEmpty {
                didFit = false
                current = word
            } else {
                lines.append(current)
                current = word
            }

            if lines.count == maxLines {
                didFit = false
                current = ""
                break
            }

            if lines.count == maxLines - 1, index < words.count - 1 {
                let remainder = ([current] + Array(words[(index + 1)...])).joined(separator: " ")
                if measuredWidth(remainder, font: font) > maxWidth {
                    didFit = false
                    current = truncatesOverflow
                        ? ellipsized(remainder, font: font, maxWidth: maxWidth)
                        : remainder
                    break
                }
            }
        }

        if !current.isEmpty, lines.count < maxLines {
            lines.append(current)
        }

        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            didFit = false
        }

        if !didFit, truncatesOverflow, let lastIndex = lines.indices.last {
            lines[lastIndex] = ellipsized(lines[lastIndex], font: font, maxWidth: maxWidth)
        }

        return Result(lines: lines, didFit: didFit)
    }

    static func measuredWidth(_ text: String, font: UIFont) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: font.lineHeight * 1.4),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.width)
    }

    private static func balancedTwoLines(
        words: [String],
        font: UIFont,
        maxWidth: CGFloat
    ) -> [String]? {
        var best: (lines: [String], score: CGFloat)?

        for split in 1..<words.count {
            let first = words[..<split].joined(separator: " ")
            let second = words[split...].joined(separator: " ")
            let firstWidth = measuredWidth(first, font: font)
            let secondWidth = measuredWidth(second, font: font)
            guard firstWidth <= maxWidth, secondWidth <= maxWidth else { continue }

            // Prefer a balanced silhouette while gently favoring a longer first line.
            let imbalance = abs(firstWidth - secondWidth)
            let orphanPenalty = second.split(separator: " ").count == 1 ? maxWidth * 0.12 : 0
            let firstLinePenalty = secondWidth > firstWidth ? maxWidth * 0.04 : 0
            let score = imbalance + orphanPenalty + firstLinePenalty

            if best == nil || score < best!.score {
                best = ([first, second], score)
            }
        }

        return best?.lines
    }

    private static func ellipsized(_ text: String, font: UIFont, maxWidth: CGFloat) -> String {
        let ellipsis = "..."
        var base = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard measuredWidth(base, font: font) > maxWidth else { return base }
        guard measuredWidth(ellipsis, font: font) <= maxWidth else { return "" }

        while !base.isEmpty {
            if measuredWidth(base + ellipsis, font: font) <= maxWidth {
                return base + ellipsis
            }
            base.removeLast()
        }

        return ellipsis
    }
}

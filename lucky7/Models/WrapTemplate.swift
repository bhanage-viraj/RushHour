//
//  WrapTemplate.swift
//  lucky7
//

import Foundation
import CoreGraphics

enum WrapTemplate: String, CaseIterable, Identifiable, Sendable {
    case styled
    case clean
    case transparent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .styled: return "Styled"
        case .clean: return "Clean"
        case .transparent: return "Transparent"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .styled:
            return "Video with session title, focus duration, and date"
        case .clean:
            return "Video without text"
        case .transparent:
            return "Transparent session stats image"
        }
    }

    var hasVideoOverlay: Bool { self == .styled }
    var isTransparent: Bool { self == .transparent }
}

struct WrapShareMetadata: Sendable {
    let title: String
    let duration: String
    let date: String
}

/// Shared proportions from the canonical Figma Wrapped frame. Both the SwiftUI preview
/// and the Core Animation exporter use these values so saved media matches the screen.
enum WrapOverlayLayout {
    static let titleFontRatio: CGFloat = 0.041
    static let durationFontRatio: CGFloat = 0.145
    static let dateFontRatio: CGFloat = 0.035
    static let titleWidthRatio: CGFloat = 0.61
    static let durationWidthRatio: CGFloat = 0.76
    static let styledTopRatio: CGFloat = 0.054
    static let contentSpacingRatio: CGFloat = 0.010

    static let transparentBadgeTopRatio: CGFloat = 0.043
    static let transparentBadgeWidthRatio: CGFloat = 0.30
    static let transparentBadgeHeightRatio: CGFloat = 0.080
    static let transparentBadgeFontRatio: CGFloat = 0.032
    static let transparentBadgeGapRatio: CGFloat = 0.064

    static let lineHeightRatio: CGFloat = 1.30
}

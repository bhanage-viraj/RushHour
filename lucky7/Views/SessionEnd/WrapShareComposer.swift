//
//  WrapShareComposer.swift
//  lucky7
//

import SwiftUI
import UIKit

struct WrapShareComposer: View {
    private static let sharePanelHeight: CGFloat = 266
    private static let cardSize = CGSize(width: 255.84, height: 459.2)
    private static let cardSpacing: CGFloat = 26.24
    private static let cardTopPadding: CGFloat = 10

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WrapShareViewModel
    @State private var scrollTarget: WrapTemplate? = .styled
    private let initialTemplate: WrapTemplate

    init(
        sourceURL: URL,
        metadata: WrapShareMetadata,
        sourceContainsMetadata: Bool = false,
        initialTemplate: WrapTemplate = .styled
    ) {
        let resolvedTemplate: WrapTemplate = sourceContainsMetadata && initialTemplate == .clean
            ? .styled
            : initialTemplate
        self.initialTemplate = resolvedTemplate
        _scrollTarget = State(initialValue: resolvedTemplate)
        _viewModel = StateObject(
            wrappedValue: WrapShareViewModel(
                sourceURL: sourceURL,
                metadata: metadata,
                sourceContainsMetadata: sourceContainsMetadata,
                initialTemplate: resolvedTemplate
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.wrappedShareBlue
                    .ignoresSafeArea()

                Image("PatternBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .frame(height: 48)

                    templateCarousel(
                        in: CGSize(
                            width: proxy.size.width,
                            height: max(
                                proxy.size.height
                                    + proxy.safeAreaInsets.bottom
                                    - 48
                                    - Self.sharePanelHeight,
                                180
                            )
                        )
                    )
                    .frame(maxHeight: .infinity)

                    sharePanel
                        .frame(height: Self.sharePanelHeight)
                }
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])

                if viewModel.isWorking {
                    workingOverlay
                }

                if let result = viewModel.resultMessage {
                    resultBanner(result)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 58)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .task {
            await viewModel.prepare()
            scrollTarget = initialTemplate
            viewModel.selectedTemplate = initialTemplate
        }
        .onChange(of: scrollTarget) { _, template in
            guard let template else { return }
            viewModel.selectedTemplate = template
        }
        .onChange(of: viewModel.selectedTemplate) { _, template in
            if scrollTarget != template {
                scrollTarget = template
            }
        }
        .onDisappear {
            if viewModel.videoSharePayload == nil, viewModel.imageSharePayload == nil {
                viewModel.cleanup()
            }
        }
        .sheet(item: $viewModel.videoSharePayload) { payload in
            VideoShareSheet(payload: payload, onComplete: viewModel.completeSystemShare)
        }
        .sheet(item: $viewModel.imageSharePayload) { payload in
            ImageShareSheet(payload: payload, onComplete: viewModel.completeSystemShare)
        }
        .sheet(item: $viewModel.messageSharePayload) { payload in
            MessageShareSheet(payload: payload, onComplete: viewModel.completeMessageShare)
        }
        .alert("Could not prepare wrap", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        ZStack {
            Text("Share Sessions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                Button {
                    viewModel.cleanup()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    private func templateCarousel(in available: CGSize) -> some View {
        let cardSize = fittedCardSize(in: available)
        let sideMargin = max((available.width - cardSize.width) / 2, 0)
        let cardTopPadding = min(Self.cardTopPadding, max((available.height - cardSize.height) / 2, 0))

        return ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Self.cardSpacing) {
                ForEach(viewModel.availableTemplates) { template in
                    WrapTemplateCard(
                        image: viewModel.posterImage,
                        template: template,
                        metadata: viewModel.metadata,
                        sourceContainsMetadata: viewModel.sourceContainsMetadata
                    )
                    .frame(width: cardSize.width, height: cardSize.height)
                    .padding(.top, cardTopPadding)
                    .id(template)
                }
            }
            .scrollTargetLayout()
            .frame(height: available.height, alignment: .top)
        }
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $scrollTarget, anchor: .center)
        .scrollIndicators(.hidden)
        .accessibilityLabel("Share template carousel")
        .accessibilityValue(viewModel.selectedTemplate.displayName)
        .accessibilityAdjustableAction { direction in
            adjustTemplate(direction)
        }
    }

    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SHARE TO")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(height: 13, alignment: .top)

            HStack(spacing: 0) {
                ShareDestinationButton(
                    title: "Instagram\nStory",
                    assetName: "InstagramShareIcon",
                    action: viewModel.shareSelectedToInstagramStory
                )

                Spacer(minLength: 0)
                    .frame(maxWidth: 16)

                ShareDestinationButton(
                    title: "Instagram\nMessages",
                    assetName: "InstagramShareIcon",
                    action: viewModel.shareSelectedToInstagramMessages
                )

                Spacer(minLength: 0)
                    .frame(maxWidth: 16)

                ShareDestinationButton(
                    title: "Whatsapp",
                    assetName: "WhatsAppShareIcon",
                    action: viewModel.shareSelectedToWhatsApp
                )

                Spacer(minLength: 0)
                    .frame(maxWidth: 16)

                ShareDestinationButton(
                    title: "Messages",
                    assetName: "MessagesShareIcon",
                    action: viewModel.shareSelectedToMessages
                )

                Spacer(minLength: 0)
            }

            HStack(spacing: 16) {
                if viewModel.canCopySelected {
                    ShareUtilityButton(
                        title: "Copy",
                        systemImage: "document.on.document",
                        action: viewModel.copySelected
                    )
                }

                ShareUtilityButton(
                    title: "Save to\nPhoto",
                    systemImage: "square.and.arrow.down",
                    action: viewModel.saveSelected
                )

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
            .stroke(Color.black, lineWidth: 2)
        }
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text(viewModel.workingLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.workingLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func resultBanner(_ message: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                viewModel.clearResultMessage()
            }
        } label: {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Color.white, in: Capsule())
                .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismisses this message")
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }

    private func fittedCardSize(in available: CGSize) -> CGSize {
        let widthScale = max((available.width - 32) / Self.cardSize.width, 0)
        let heightScale = max((available.height - Self.cardTopPadding - 12) / Self.cardSize.height, 0)
        let scale = min(widthScale, heightScale, 1)
        return CGSize(
            width: Self.cardSize.width * scale,
            height: Self.cardSize.height * scale
        )
    }

    private func adjustTemplate(_ direction: AccessibilityAdjustmentDirection) {
        let templates = viewModel.availableTemplates
        guard let currentIndex = templates.firstIndex(of: viewModel.selectedTemplate) else {
            return
        }

        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(currentIndex + 1, templates.index(before: templates.endIndex))
        case .decrement:
            nextIndex = max(currentIndex - 1, templates.startIndex)
        @unknown default:
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            scrollTarget = templates[nextIndex]
        }
    }
}

private struct ShareDestinationButton: View {
    let title: String
    let assetName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(assetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 32, alignment: .top)
            }
            .frame(width: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShareActionButtonStyle())
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
    }
}

private struct ShareUtilityButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .frame(width: 48, height: 48)

                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 32, alignment: .top)
            }
            .frame(width: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShareActionButtonStyle())
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
    }
}

private struct ShareActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct WrapTemplateCard: View {
    let image: UIImage?
    let template: WrapTemplate
    let metadata: WrapShareMetadata
    var sourceContainsMetadata = false

    var body: some View {
        ZStack {
            if template.isTransparent {
                CheckerboardBackground()
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }

            if !(template == .styled && sourceContainsMetadata) {
                WrapMetadataOverlay(template: template, metadata: metadata)
                    .allowsHitTesting(false)
            }

        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black, lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(template.displayName) template")
        .accessibilityValue(template.accessibilityDescription)
    }
}

struct WrapMetadataOverlay: View {
    let template: WrapTemplate
    let metadata: WrapShareMetadata

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height)

            switch template {
            case .clean:
                Color.clear

            case .styled:
                metadataContent(unit: unit, width: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, proxy.size.height * WrapOverlayLayout.styledTopRatio)

            case .transparent:
                VStack(spacing: unit * WrapOverlayLayout.transparentBadgeGapRatio) {
                    Text("TRANSPARENT")
                        .font(.system(
                            size: unit * WrapOverlayLayout.transparentBadgeFontRatio,
                            weight: .bold
                        ))
                        .foregroundStyle(.white)
                        .frame(
                            width: unit * WrapOverlayLayout.transparentBadgeWidthRatio,
                            height: unit * WrapOverlayLayout.transparentBadgeHeightRatio
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color.white,
                                    lineWidth: max(unit * 0.0032, 1)
                                )
                        }

                    metadataContent(unit: unit, width: proxy.size.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, proxy.size.height * WrapOverlayLayout.transparentBadgeTopRatio)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func metadataContent(unit: CGFloat, width: CGFloat) -> some View {
        let titleWidth = width * WrapOverlayLayout.titleWidthRatio
        let titleLayout = fittedTitle(unit: unit, maxWidth: titleWidth)
        let durationSize = fittedDurationSize(
            unit: unit,
            maxWidth: width * WrapOverlayLayout.durationWidthRatio
        )

        VStack(spacing: unit * WrapOverlayLayout.contentSpacingRatio) {
            Text(titleLayout.text)
                .font(gothic(titleLayout.fontSize))
                .multilineTextAlignment(.center)
                .lineSpacing(titleLayout.fontSize * (WrapOverlayLayout.lineHeightRatio - 1))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: titleWidth)

            Text(metadata.duration)
                .font(gothic(durationSize))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: width * WrapOverlayLayout.durationWidthRatio)

            if !metadata.date.isEmpty {
                Text(metadata.date)
                    .font(.system(
                        size: unit * WrapOverlayLayout.dateFontRatio,
                        weight: .regular
                    ))
                    .lineLimit(1)
                    .opacity(0.70)
                    .frame(width: titleWidth)
            }
        }
    }

    private func fittedTitle(unit: CGFloat, maxWidth: CGFloat) -> (text: String, fontSize: CGFloat) {
        var size = unit * WrapOverlayLayout.titleFontRatio
        let minimumSize = unit * 0.024
        let step = max(unit * 0.002, 0.5)

        while size > minimumSize {
            let font = wrappedUIFont(size)
            let layout = WrapTextLayout.lines(
                for: metadata.title,
                font: font,
                maxWidth: maxWidth,
                maxLines: 2
            )
            if layout.didFit, !layout.lines.isEmpty {
                return (layout.text, size)
            }
            size -= step
        }

        let font = wrappedUIFont(minimumSize)
        let layout = WrapTextLayout.lines(
            for: metadata.title,
            font: font,
            maxWidth: maxWidth,
            maxLines: 2,
            truncatesOverflow: true
        )
        return (layout.text, minimumSize)
    }

    private func fittedDurationSize(unit: CGFloat, maxWidth: CGFloat) -> CGFloat {
        var size = unit * WrapOverlayLayout.durationFontRatio
        let minimumSize = unit * 0.09
        let step = max(unit * 0.002, 0.5)

        while size > minimumSize {
            if WrapTextLayout.measuredWidth(metadata.duration, font: wrappedUIFont(size)) <= maxWidth {
                return size
            }
            size -= step
        }
        return minimumSize
    }

    private func gothic(_ size: CGFloat) -> Font {
        .custom("SpecialGothicExpandedOne-Regular", size: size)
    }

    private func wrappedUIFont(_ size: CGFloat) -> UIFont {
        UIFont(name: "SpecialGothicExpandedOne-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .black)
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell = max(min(size.width, size.height) / 8, 14)
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))

            for row in 0..<rows {
                for column in 0..<columns {
                    let color = (row + column).isMultiple(of: 2)
                        ? Color(white: 0.25)
                        : Color(white: 0.34)
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * cell,
                                y: CGFloat(row) * cell,
                                width: cell,
                                height: cell
                            )
                        ),
                        with: .color(color)
                    )
                }
            }
        }
    }
}

#Preview("Portrait wrap templates") {
    ZStack {
        Color.wrappedShareBlue

        WrapTemplateCard(
            image: UIImage(named: "dummySnapshot1"),
            template: .styled,
            metadata: WrapShareMetadata(
                title: "Morning Session Rush!",
                duration: "3h 20m",
                date: "26 May 2026"
            )
        )
        .frame(width: 256, height: 459)
    }
}

#Preview("Landscape wrap templates") {
    ZStack {
        Color.wrappedShareBlue

        WrapTemplateCard(
            image: UIImage(named: "dummySnapshot2"),
            template: .styled,
            metadata: WrapShareMetadata(
                title: "Morning Session Rush!",
                duration: "3h 20m",
                date: "26 May 2026"
            )
        )
        .frame(width: 360, height: 203)
    }
}

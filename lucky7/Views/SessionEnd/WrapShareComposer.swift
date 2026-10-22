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

    init(
        sourceURL: URL,
        metadata: WrapShareMetadata,
        sourceContainsMetadata: Bool = false
    ) {
        _viewModel = StateObject(
            wrappedValue: WrapShareViewModel(
                sourceURL: sourceURL,
                metadata: metadata,
                sourceContainsMetadata: sourceContainsMetadata
            )
        )
    }

    private var isLandscapeWrap: Bool {
        guard let image = viewModel.posterImage else { return false }
        return image.size.width > image.size.height
    }

    var body: some View {
        NavigationStack {
            composerContent
                .ignoresSafeArea(.container, edges: isLandscapeWrap ? .all : [])
                .navigationTitle("Share Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(isLandscapeWrap ? .visible : .hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    if isLandscapeWrap {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                viewModel.cleanup()
                                dismiss()
                            } label: { Image(systemName: "chevron.left") }
                            .tint(.white)
                            .disabled(viewModel.isWorking)
                            .accessibilityLabel("Back")
                        }
                    }
                }
        }
        .overlay(alignment: .top) {
            if let result = viewModel.resultMessage {
                resultBanner(result)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await viewModel.prepare()
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
        .sheet(item: $viewModel.imageSharePayload, onDismiss: {
            viewModel.completeSystemShare(error: nil)
        }) { payload in
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

    private var composerContent: some View {
        GeometryReader { proxy in
            ZStack {
                Color.wrappedShareBlue
                    .ignoresSafeArea()

                if isLandscapeWrap {
                    let scale = min(proxy.size.width / 402, proxy.size.height / 874)
                    Image("LandscapeWrapSharePattern")
                        .resizable()
                        .frame(width: 786.807 * scale, height: 786.807 * scale)
                        .position(x: proxy.size.width / 2 + 0.4 * scale, y: 437.403 * scale)
                        .accessibilityHidden(true)

                    landscapeCarousel(in: CGSize(width: proxy.size.width, height: proxy.size.height * 0.965))
                        .frame(maxHeight: .infinity, alignment: .top)

                    landscapeSharePanel
                        .frame(height: 168)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                } else {
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
                }

                if viewModel.isWorking {
                    workingOverlay
                }

            }
        }
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
        let cardTopPadding = max((available.height - cardSize.height) / 2, 0)

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

    private func landscapeCarousel(in available: CGSize) -> some View {
        let width = min(max(available.width - 48, 0), 354.453)
        let aspect = viewModel.posterImage.map { $0.size.width / $0.size.height } ?? (354.453 / 197.48)
        let height = width / aspect
        let margin = max((available.height - height) / 2, 0)

        return ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(spacing: 15.495) {
                    ForEach(viewModel.availableTemplates) { template in
                        WrapTemplateCard(
                            image: viewModel.posterImage,
                            template: template,
                            metadata: viewModel.metadata,
                            sourceContainsMetadata: viewModel.sourceContainsMetadata
                        )
                        .frame(width: width, height: height)
                        .opacity(template == viewModel.selectedTemplate ? 1 : 0.5)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.22)) { scrollTarget = template }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Centers and selects this template")
                        .id(template)
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: .infinity)
            }
            .contentMargins(.vertical, margin, for: .scrollContent)
            .scrollEdgeEffectHidden(true, for: .top)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always, anchor: .center))
            .scrollPosition(id: $scrollTarget, anchor: .center)
            .scrollIndicators(.hidden)
            .frame(height: available.height)
            .accessibilityLabel("Share template carousel")
            .accessibilityValue(viewModel.selectedTemplate.displayName)
            .accessibilityAdjustableAction(adjustTemplate)
            .onAppear { reader.scrollTo(viewModel.selectedTemplate, anchor: .center) }
        }
    }

    private var landscapeSharePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SHARE TO")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(height: 13, alignment: .top)
                .padding(.horizontal, 20)

            shareActions
                .padding(.horizontal, 20)
        }
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .stroke(.black, lineWidth: 2)
        }
    }

    private var sharePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SHARE TO")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(height: 13, alignment: .top)

            shareActions
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

    private var shareActions: some View {
        HStack(spacing: 0) {
            ShareUtilityButton(
                title: "Save",
                image: Image(systemName: "square.and.arrow.down"),
                action: viewModel.saveSelectedToPhotos
            )
            .frame(maxWidth: .infinity)

            ShareUtilityButton(
                title: "Share",
                image: Image(systemName: "square.and.arrow.up"),
                action: viewModel.shareSelected
            )
            .frame(maxWidth: .infinity)

            ShareUtilityButton(
                title: "Instagram\nStory",
                image: Image("InstagramShareIcon"),
                iconSize: 48,
                action: viewModel.shareSelectedToInstagramStory
            )
            .frame(maxWidth: .infinity)

            ShareUtilityButton(
                title: "Messages",
                image: Image("MessagesShareIcon"),
                iconSize: 48,
                action: viewModel.shareSelectedToMessages
            )
            .frame(maxWidth: .infinity)
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
        var cardSize = Self.cardSize
        if let image = viewModel.posterImage, image.size.width > 0, image.size.height > 0 {
            // The poster already applies the video's preferred track transform.
            let aspectRatio = image.size.width / image.size.height
            let longSide = Self.cardSize.height
            cardSize = aspectRatio > 1
                ? CGSize(width: longSide, height: longSide / aspectRatio)
                : CGSize(width: longSide * aspectRatio, height: longSide)
        }
        let widthScale = max((available.width - 32) / cardSize.width, 0)
        let heightScale = max((available.height - Self.cardTopPadding - 12) / cardSize.height, 0)
        let scale = min(widthScale, heightScale, 1)
        return CGSize(
            width: cardSize.width * scale,
            height: cardSize.height * scale
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

private struct ShareUtilityButton: View {
    let title: String
    let image: Image
    var iconSize: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
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
            .frame(width: 68)
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
        Color.black
        .overlay {
            if template.isTransparent {
                GeometryReader { proxy in
                    if proxy.size.width > proxy.size.height {
                        Image("LandscapeWrapTransparencyGrid")
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .overlay(.black.opacity(0.6))
                    } else {
                        CheckerboardBackground()
                    }
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay {
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
            let unit = WrapOverlayLayout.unit(for: template, in: proxy.size)

            switch template {
            case .clean:
                Color.clear

            case .styled:
                metadataContent(unit: unit, width: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, proxy.size.height * WrapOverlayLayout.styledTopRatio(in: proxy.size))

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
                .padding(.top, proxy.size.height * WrapOverlayLayout.transparentBadgeTopRatio(in: proxy.size))
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

        VStack(spacing: unit * WrapOverlayLayout.logoSpacingRatio) {
            Image(WrapOverlayLayout.logoAssetName)
                .resizable()
                .scaledToFit()
                .frame(
                    width: unit * WrapOverlayLayout.logoWidthRatio,
                    height: unit * WrapOverlayLayout.logoArtworkHeightRatio
                )
                .frame(height: unit * WrapOverlayLayout.logoFrameHeightRatio)
                .accessibilityLabel("Rush Hour")

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
                        .opacity(0.90)
                        .frame(width: titleWidth)
                }
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

// No real video in previews, so the cards show their loading placeholder.
#Preview("Share composer") {
    WrapShareComposer(
        sourceURL: URL(fileURLWithPath: "/dev/null"),
        metadata: WrapShareMetadata(
            title: "Morning Session Rush!",
            duration: "3h 20m",
            date: "26 May 2026"
        )
    )
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

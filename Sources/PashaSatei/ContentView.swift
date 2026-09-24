import SwiftUI
import PhotosUI
import UIKit
import MapKit
import CoreLocation
@preconcurrency import Vision

enum AppRoute: Hashable {
    case result
    case compare(
        productName: String,
        barcode: String,
        brand: String,
        modelNumber: String
    )
}

struct Marketplace: Identifiable {
    let id = UUID()
    let name: String
    let feeRate: Double
    let searchBaseURL: String
}

private let marketplaces = [
    Marketplace(
        name: "メルカリ",
        feeRate: 0.10,
        searchBaseURL: "https://jp.mercari.com/search?keyword="
    ),
    Marketplace(
        name: "Yahoo!オークション",
        feeRate: 0.10,
        searchBaseURL: "https://auctions.yahoo.co.jp/search/search?p="
    ),
    Marketplace(
        name: "楽天ラクマ",
        feeRate: 0.10,
        searchBaseURL: "https://fril.jp/s?query="
    )
]

struct GeminiProductResponse: Codable {
    let ok: Bool
    let displayName: String?
    let brand: String?
    let productName: String?
    let variant: String?
    let modelNumber: String?
    let size: String?
    let category: String?
    let confidence: Double?
    let evidence: [String]?
    let candidates: [String]?
    let error: String?
}


struct YahooPriceItem: Codable, Identifiable {
    let name: String
    let price: Int
    let url: String
    let imageUrl: String?
    let seller: String?
    let condition: String?

    var id: String {
        url.isEmpty
        ? "\(name)-\(price)"
        : url
    }
}

struct YahooPriceResponse: Codable {
    let ok: Bool
    let source: String?
    let query: String?
    let count: Int
    let minPrice: Int
    let medianPrice: Int
    let maxPrice: Int
    let items: [YahooPriceItem]
    let error: String?
}

struct LocalRecognitionResult {
    let text: String
    let barcode: String
}


struct PremiumAppBackground: View {
    var body: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [
                    Color(
                        red: 0 / 255,
                        green: 84 / 255,
                        blue: 55 / 255
                    ).opacity(0.34),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 360
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color(
                        red: 4 / 255,
                        green: 15 / 255,
                        blue: 12 / 255
                    ).opacity(0.88),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct PremiumFeatureItem: View {
    let icon: String
    let title: String
    let subtitle: String

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(green.opacity(0.12))
                    .frame(width: 46, height: 46)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(green)
            }

            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ContentView: View {
    @State private var path: [AppRoute] = []
    @State private var selectedImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false

    @State private var productName = ""
    @State private var detectedBarcode = ""
    @State private var recognitionSource = ""
    @State private var confidence = 0
    @State private var brand = ""
    @State private var category = ""
    @State private var modelNumber = ""
    @State private var evidence: [String] = []
    @State private var candidates: [String] = []
    @State private var isRecognizing = false
    @State private var hasPreviousSearchResult = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                selectedPhoto: $selectedPhoto,
                showCamera: $showCamera,
                hasPreviousResult: hasPreviousSearchResult,
                onOpenPreviousResult: {
                    if hasPreviousSearchResult {
                        path.append(.result)
                    }
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .result:
                    ResultView(
                        image: selectedImage,
                        productName: $productName,
                        detectedBarcode: $detectedBarcode,
                        recognitionSource: $recognitionSource,
                        confidence: $confidence,
                        brand: $brand,
                        category: $category,
                        modelNumber: $modelNumber,
                        evidence: $evidence,
                        candidates: $candidates,
                        isRecognizing: $isRecognizing,
                        onCompare: {
                            let selectedName =
                                productName
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )

                            guard !selectedName.isEmpty,
                                  !isRecognizing else {
                                return
                            }

                            path.append(
                                .compare(
                                    productName: selectedName,
                                    barcode: detectedBarcode,
                                    brand: brand,
                                    modelNumber: modelNumber
                                )
                            )
                        }
                    )

                case let .compare(
                    selectedProductName,
                    selectedBarcode,
                    selectedBrand,
                    selectedModelNumber
                ):
                    CompareView(
                        productName: selectedProductName,
                        barcode: selectedBarcode,
                        brand: selectedBrand,
                        modelNumber: selectedModelNumber
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCamera) {
    CameraPicker(
        onImage: { image in
            selectedImage = image
            showCamera = false

            Task { @MainActor in
                isRecognizing = true
                hasPreviousSearchResult = true
                path.append(.result)
                await Task.yield()
                await recognize(image: image)
            }
        },
        onCancel: {
            showCamera = false
        }
    )
    .ignoresSafeArea()
}
        .onChange(of: selectedPhoto) { newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    return
                }

                selectedImage = image
                selectedPhoto = nil
                isRecognizing = true
                hasPreviousSearchResult = true
                path.append(.result)
                await Task.yield()
                await recognize(image: image)
            }
        }
    }

    @MainActor
    private func recognize(image: UIImage) async {
        isRecognizing = true

        productName = ""
        detectedBarcode = ""
        recognitionSource = ""
        confidence = 0
        brand = ""
        category = ""
        modelNumber = ""
        evidence = []
        candidates = []

        // 過去に安定していた方式：
        // 先にiPhone側でOCR/JANを取得し、その結果をGeminiへ渡す。
        let local =
            await LocalProductRecognizer.recognize(
                image: image
            )

        detectedBarcode = local.barcode

        let gemini =
            await GeminiProductAPI.analyze(
                image: image,
                ocrText: local.text,
                barcode: local.barcode
            )

        if let gemini, gemini.ok {
            let displayName =
                gemini.displayName?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

            let apiProductName =
                gemini.productName?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

            productName =
                !displayName.isEmpty
                ? displayName
                : apiProductName

            brand =
                gemini.brand?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

            category =
                gemini.category?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

            modelNumber =
                gemini.modelNumber?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

            let rawConfidence =
                gemini.confidence ?? 0

            confidence =
                rawConfidence <= 1
                ? Int((rawConfidence * 100).rounded())
                : Int(rawConfidence.rounded())

            evidence =
                gemini.evidence ?? []

            candidates =
                gemini.candidates ?? []

            if productName.isEmpty,
               let first = candidates.first {
                productName = first
            }

            if detectedBarcode.isEmpty {
                recognitionSource =
                    "Gemini画像認識 + OCR補助"
            } else {
                recognitionSource =
                    "Gemini画像認識 + JAN/EAN照合 + OCR補助"
            }
        } else {
            recognitionSource =
                detectedBarcode.isEmpty
                ? "画像文字認識"
                : "JAN/EAN + 画像文字認識"

            let lines =
                local.text
                    .components(separatedBy: .newlines)
                    .map {
                        $0.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }
                    .filter { !$0.isEmpty }

            productName =
                lines.prefix(2)
                    .joined(separator: " ")
        }

        isRecognizing = false
    }

}

struct HomeView: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var showCamera: Bool

    @State private var showUsageGuide = false

    let hasPreviousResult: Bool
    let onOpenPreviousResult: () -> Void

    var body: some View {
        ZStack {
            PremiumAppBackground()

            GeometryReader { geometry in
                HomeScreenContent(
                    selectedPhoto: $selectedPhoto,
                    showCamera: $showCamera,
                    showUsageGuide: $showUsageGuide,
                    hasPreviousResult: hasPreviousResult,
                    onOpenPreviousResult: onOpenPreviousResult,
                    compact: geometry.size.height < 780
                )
            }
        }
        .navigationBarHidden(true)
        .sheet(
            isPresented:
                $showUsageGuide
        ) {
            UsageGuideView()
        }
    }
}

struct HomeScreenContent: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var showCamera: Bool
    @Binding var showUsageGuide: Bool

    let hasPreviousResult: Bool
    let onOpenPreviousResult: () -> Void
    let compact: Bool

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomeHeroSection(
                compact: compact
            )

            Spacer(
                minLength:
                    compact ? 5 : 8
            )

            HomeGuideButton(
                compact: compact,
                action: {
                    showUsageGuide = true
                }
            )

            Spacer(
                minLength:
                    compact ? 5 : 8
            )

            HomeFeatureRow(
                compact: compact
            )

            Spacer(
                minLength:
                    compact ? 5 : 8
            )

            HomeCameraButton(
                compact: compact,
                action: {
                    showCamera = true
                }
            )

            Spacer(
                minLength:
                    compact ? 5 : 8
            )

            HomePhotoPicker(
                selectedPhoto:
                    $selectedPhoto,
                compact: compact
            )

            Spacer(
                minLength:
                    compact ? 5 : 8
            )

            if hasPreviousResult {
                HomePreviousButton(
                    compact: compact,
                    action:
                        onOpenPreviousResult
                )
            }

            Spacer(
                minLength:
                    compact ? 2 : 4
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 5)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
    }
}

struct HomeHeroSection: View {
    let compact: Bool

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack(spacing: 2) {
                    Text("パシャ")
                        .foregroundStyle(.white)

                    Text("査定")
                        .foregroundStyle(green)
                }
                .font(
                    .system(
                        size:
                            compact
                            ? 33
                            : 37,
                        weight: .black,
                        design: .rounded
                    )
                )

                Text(
                    "写真から、売れる相場を\nすばやくチェック"
                )
                .font(
                    .system(
                        size:
                            compact
                            ? 13.5
                            : 15,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    .white.opacity(0.94)
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                Text(
                    "価格をまとめて比較"
                )
                .font(
                    .system(
                        size:
                            compact
                            ? 10.5
                            : 11.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                MarketplaceLogoRow()
            }

            Spacer(minLength: 4)

            ResaleItemsHero(
                compact: compact
            )
        }
        .padding(.horizontal, 2)
        .frame(
            height:
                compact
                ? 220
                : 238
        )
    }
}


struct HomeGuideButton: View {
    let compact: Bool
    let action: () -> Void

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 13
                    )
                    .fill(
                        green.opacity(0.15)
                    )
                    .frame(
                        width: 50,
                        height: 50
                    )

                    Image(
                        systemName:
                            "lightbulb.fill"
                    )
                    .font(.title3)
                    .foregroundStyle(green)
                }

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        "使い方・撮影のコツ"
                    )
                    .font(.headline)

                    Text(
                        "正確に判定するためのポイントを見る"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.headline)
            }
            .padding(.horizontal, 14)
            .frame(
                maxWidth: .infinity,
                minHeight:
                    compact
                    ? 58
                    : 64
            )
            .background(
                LinearGradient(
                    colors: [
                        green.opacity(0.15),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 18
                )
                .stroke(
                    green.opacity(0.40),
                    lineWidth: 1
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18
                )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

struct HomeFeatureRow: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 5) {
            PremiumFeatureItem(
                icon: "sparkles",
                title: "AI商品判定",
                subtitle:
                    "写真から商品名・型番を特定"
            )

            PremiumFeatureItem(
                icon: "chart.bar.fill",
                title: "3サイト相場比較",
                subtitle:
                    "3サイトの価格を一括比較"
            )

            PremiumFeatureItem(
                icon: "tag.fill",
                title: "出品までスムーズ",
                subtitle:
                    "相場を見てすぐ出品"
            )
        }
        .frame(
            height:
                compact
                ? 78
                : 88
        )
    }
}

struct HomeCameraButton: View {
    let compact: Bool
    let action: () -> Void

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(
                    systemName:
                        "camera.fill"
                )
                .font(.title2)

                Text("カメラで撮影")
                    .font(.title3.bold())

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.headline)
            }
            .padding(.horizontal, 20)
            .frame(
                maxWidth: .infinity,
                minHeight:
                    compact
                    ? 60
                    : 68
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .background(
            LinearGradient(
                colors: [
                    Color(
                        red: 83 / 255,
                        green: 238 / 255,
                        blue: 154 / 255
                    ),
                    green
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .shadow(
            color:
                green.opacity(0.27),
            radius: 13,
            y: 4
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18
            )
        )
    }
}

struct HomePhotoPicker: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    let compact: Bool

    var body: some View {
        PhotosPicker(
            selection: $selectedPhoto,
            matching: .images
        ) {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        "photo.fill"
                )
                .font(.title3)

                Text("写真を選ぶ")
                    .font(.headline)

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.subheadline.bold())
            }
            .padding(.horizontal, 18)
            .frame(
                maxWidth: .infinity,
                minHeight:
                    compact
                    ? 54
                    : 60
            )
            .background(
                Color.white.opacity(0.075)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 17
                )
                .stroke(
                    Color.white.opacity(0.18),
                    lineWidth: 1
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 17
                )
            )
        }
        .foregroundStyle(.white)
    }
}

struct HomePreviousButton: View {
    let compact: Bool
    let action: () -> Void

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        "clock.arrow.circlepath"
                )

                Text(
                    "前回の検索結果を見る"
                )
                .font(.subheadline.bold())

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption.bold())
            }
            .padding(.horizontal, 16)
            .frame(
                maxWidth: .infinity,
                minHeight:
                    compact
                    ? 46
                    : 50
            )
            .background(
                green.opacity(0.08)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 15
                )
                .stroke(
                    green.opacity(0.34),
                    lineWidth: 1
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 15
                )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(green)
    }
}

struct MarketplaceLogoRow: View {
    var body: some View {
        HStack(spacing: 10) {
            MarketplaceIconTile {
                MercariLocalMark()
            }

            MarketplaceIconTile {
                YahooFleamarketLocalMark()
            }

            MarketplaceIconTile {
                RakumaLocalMark()
            }
        }
    }
}

struct MarketplaceIconTile<Content: View>: View {
    @ViewBuilder let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        RoundedRectangle(
            cornerRadius: 10
        )
        .fill(Color.white)
        .frame(
            width: 43,
            height: 43
        )
        .overlay {
            content
                .padding(5)
        }
        .overlay(
            RoundedRectangle(
                cornerRadius: 10
            )
            .stroke(
                Color.white.opacity(0.20),
                lineWidth: 1
            )
        )
    }
}

struct MercariLocalMark: View {
    var body: some View {
        ZStack(
            alignment: .topTrailing
        ) {
            MercariHexagon()
                .fill(
                    Color(
                        red: 242 / 255,
                        green: 53 / 255,
                        blue: 47 / 255
                    )
                )
                .padding(2)

            Text("m")
                .font(
                    .system(
                        size: 20,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .offset(
                    x: -7,
                    y: 8
                )

            Circle()
                .fill(
                    Color(
                        red: 77 / 255,
                        green: 181 / 255,
                        blue: 229 / 255
                    )
                )
                .frame(
                    width: 13,
                    height: 13
                )
                .offset(
                    x: -1,
                    y: 1
                )
        }
    }
}

struct MercariHexagon: Shape {
    func path(
        in rect: CGRect
    ) -> Path {
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.midX,
                y: rect.minY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
                    + rect.height * 0.27
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX,
                y: rect.maxY
                    - rect.height * 0.27
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.midX,
                y: rect.maxY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.maxY
                    - rect.height * 0.27
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
                    + rect.height * 0.27
            )
        )
        path.closeSubpath()

        return path
    }
}

struct YahooFleamarketLocalMark: View {
    private let red = Color(
        red: 255 / 255,
        green: 38 / 255,
        blue: 83 / 255
    )

    private let yellow = Color(
        red: 255 / 255,
        green: 178 / 255,
        blue: 48 / 255
    )

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer(
                    minLength: 3
                )

                ZStack(
                    alignment: .top
                ) {
                    Triangle()
                        .fill(red)
                        .frame(
                            width: 28,
                            height: 19
                        )

                    Rectangle()
                        .fill(yellow)
                        .frame(
                            width: 30,
                            height: 5
                        )
                        .offset(y: 15)
                }

                HStack(spacing: 6) {
                    RoundedRectangle(
                        cornerRadius: 2
                    )
                    .fill(red)
                    .frame(
                        width: 10,
                        height: 12
                    )

                    RoundedRectangle(
                        cornerRadius: 2
                    )
                    .fill(red)
                    .frame(
                        width: 10,
                        height: 12
                    )
                }

                Spacer(
                    minLength: 1
                )
            }

            Path { path in
                path.move(
                    to: CGPoint(
                        x: 22,
                        y: 2
                    )
                )
                path.addLine(
                    to: CGPoint(
                        x: 22,
                        y: 10
                    )
                )
            }
            .stroke(
                yellow,
                lineWidth: 2
            )

            Triangle()
                .fill(yellow)
                .frame(
                    width: 9,
                    height: 7
                )
                .rotationEffect(
                    .degrees(90)
                )
                .offset(
                    x: 6,
                    y: -12
                )
        }
    }
}

struct Triangle: Shape {
    func path(
        in rect: CGRect
    ) -> Path {
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.midX,
                y: rect.minY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX,
                y: rect.maxY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.maxY
            )
        )
        path.closeSubpath()

        return path
    }
}

struct RakumaLocalMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 5
            )
            .fill(Color.white)

            HStack(spacing: 0) {
                ZStack {
                    Color(
                        red: 39 / 255,
                        green: 77 / 255,
                        blue: 181 / 255
                    )

                    Text("R")
                        .font(
                            .system(
                                size: 13,
                                weight: .bold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(.white)
                }

                Color.white

                Color(
                    red: 225 / 255,
                    green: 54 / 255,
                    blue: 72 / 255
                )
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 5
                )
            )
            .padding(2)
        }
    }
}

struct ResaleItemsHero: View {
    let compact: Bool

    // ⑥ スマホ・カメラ・ヘッドホン。オフラインでも表示できるよう画像を同梱。
    private static let heroImage: UIImage = {
        let encoded = """
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
"""
        guard let data = Data(
            base64Encoded: encoded,
            options: .ignoreUnknownCharacters
        ), let image = UIImage(data: data) else {
            return UIImage()
        }
        return image
    }()

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    green.opacity(0.12)
                )

            RoundedRectangle(
                cornerRadius: 24
            )
            .fill(
                Color.black.opacity(0.36)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 24
                )
                .stroke(
                    green.opacity(0.48),
                    lineWidth: 1
                )
            )
            .frame(
                width:
                    compact
                    ? 126
                    : 140,
                height:
                    compact
                    ? 178
                    : 194
            )

            Image(uiImage: Self.heroImage)
                .resizable()
                .scaledToFill()
            .frame(
                width:
                    compact
                    ? 112
                    : 126,
                height:
                    compact
                    ? 164
                    : 180
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 19
                )
            )
            .overlay {
                Image(
                    systemName:
                        "viewfinder"
                )
                .font(
                    .system(
                        size:
                            compact
                            ? 52
                            : 60,
                        weight: .bold
                    )
                )
                .foregroundStyle(green)
                .shadow(
                    color:
                        green.opacity(0.55),
                    radius: 10
                )
            }

            VStack {
                HStack {
                    Spacer()

                    PriceBubble(
                        title: "メルカリ",
                        price: "12,980円"
                    )
                }

                Spacer()

                HStack {
                    PriceBubble(
                        title: "Yahoo!フリマ",
                        price: "13,500円"
                    )

                    Spacer()

                    PriceBubble(
                        title: "楽天ラクマ",
                        price: "11,800円"
                    )
                }
            }
            .padding(
                compact
                ? 3
                : 5
            )
        }
        .frame(
            width:
                compact
                ? 160
                : 176,
            height:
                compact
                ? 200
                : 216
        )
    }
}

struct PriceBubble: View {
    let title: String
    let price: String

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 1
        ) {
            Text(title)
                .font(
                    .system(
                        size: 7,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .white.opacity(0.90)
                )

            Text(price)
                .font(
                    .system(
                        size: 9,
                        weight: .black
                    )
                )
                .foregroundStyle(green)
        }
        .padding(
            .horizontal,
            7
        )
        .padding(
            .vertical,
            5
        )
        .background(
            Color(
                red: 4 / 255,
                green: 24 / 255,
                blue: 18 / 255
            ).opacity(0.96)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 8
            )
            .stroke(
                green.opacity(0.60),
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8
            )
        )
    }
}

struct UsageGuideView: View {
    @Environment(\.dismiss)
    private var dismiss

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 18
                    ) {
                        GuideSection(
                            number: "1",
                            title: "写真の撮り方",
                            text:
                                "商品全体ができるだけ大きく写るように撮影してください。ケース・箱・周囲の物が一緒に写ると、関連商品として認識される場合があります。1回で正しい結果が出ない場合は、少し角度を変えてもう一度撮影してください。正面だけでなく、背面・側面・型番が見える面も有効です。"
                        )

                        GuideSection(
                            number: "2",
                            title: "型番やロゴを写す",
                            text:
                                "メーカー名、ロゴ、型番、モデル番号が見えるように撮ると精度が上がります。スマートフォン、家電、カメラなどは、背面やラベルの型番が特に重要です。"
                        )

                        GuideSection(
                            number: "3",
                            title: "バーコードがあれば活用",
                            text:
                                "JANコードやバーコードがある商品は、コードがはっきり見えるように撮影すると、より正確に商品を特定しやすくなります。"
                        )

                        GuideSection(
                            number: "4",
                            title: "分かっている情報は入力",
                            text:
                                "AIの判定結果が違う場合や、商品名・型番が分かっている場合は、商品名の入力欄を修正してください。例えば「arrows We」だけでなく「arrows We F-51B」のように型番まで入れると、販売サイトの検索精度が上がります。"
                        )

                        GuideSection(
                            number: "5",
                            title: "候補を切り替えて確認",
                            text:
                                "最初の候補が違う場合は「近い候補から選ぶ」から別の候補を選択してください。型番や商品名が合っている候補を選んでから販売先比較へ進むと、検索結果が安定しやすくなります。"
                        )

                        GuideSection(
                            number: "6",
                            title: "検索結果が少ない場合",
                            text:
                                "販売サイトによって、現在出品されている商品数は異なります。商品名や型番を確認し、必要なら候補を切り替えて再検索してください。売り切れ商品や関連商品は除外されるため、表示件数が少なくなる場合があります。"
                        )

                        GuideSection(
                            number: "7",
                            title: "価格を見るとき",
                            text:
                                "最安値には状態の悪い商品や特殊な条件の商品が含まれる場合があります。実際の販売相場を見るときは中央値付近の商品を中心に確認するのがおすすめです。最安値・中央値・最高値をタップすると、それぞれの価格帯の商品を確認できます。"
                        )

                        GuideSection(
                            number: "8",
                            title: "撮影時のチェック",
                            bullets: [
                                "明るい場所で撮影する",
                                "商品を画面の中央に置く",
                                "商品全体を写す",
                                "型番・ロゴが読めるようにする",
                                "ケースや付属品をできるだけ外す",
                                "背景に別の商品を置かない",
                                "ぼやけた写真や暗い写真は避ける"
                            ]
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 8
                        ) {
                            Label(
                                "ご注意",
                                systemImage:
                                    "info.circle.fill"
                            )
                            .font(.headline)
                            .foregroundStyle(green)

                            Text(
                                "AI判定や各販売サイトの検索結果は参考情報です。商品の状態、付属品、カラー、容量、販売時期などによって実際の販売価格は異なります。出品前に商品名・型番・状態をご自身でも確認してください。"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                        }
                        .padding(16)
                        .background(
                            Color(
                                red: 24 / 255,
                                green: 24 / 255,
                                blue: 26 / 255
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 18
                            )
                            .stroke(
                                green.opacity(0.35),
                                lineWidth: 1
                            )
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18
                            )
                        )
                    }
                    .padding(18)
                }
            }
            .navigationTitle(
                "パシャ査定 使い方ガイド"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundStyle(green)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct GuideSection: View {
    let number: String
    let title: String
    var text: String? = nil
    var bullets: [String] = []

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack(spacing: 10) {
                Text(number)
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .frame(
                        width: 28,
                        height: 28
                    )
                    .background(green)
                    .clipShape(Circle())

                Text(title)
                    .font(.headline)
            }

            if let text {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            if !bullets.isEmpty {
                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(
                        bullets,
                        id: \.self
                    ) { item in
                        HStack(
                            alignment: .top,
                            spacing: 8
                        ) {
                            Image(
                                systemName:
                                    "checkmark.circle.fill"
                            )
                            .foregroundStyle(green)

                            Text(item)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color(
                red: 24 / 255,
                green: 24 / 255,
                blue: 26 / 255
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18
            )
        )
    }
}

struct FeatureBadge: View {
    let text: String
    let icon: String

    var body: some View {
        Label(
            text,
            systemImage: icon
        )
        .font(.caption.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.white.opacity(0.08)
        )
        .clipShape(Capsule())
    }
}

struct StepCard: View {
    let number: String
    let title: String
    let icon: String

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        VStack(spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(
                    width: 26,
                    height: 26
                )
                .background(green)
                .clipShape(Circle())

            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(green)

            Text(title)
                .font(.caption.bold())
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 96
        )
        .background(
            Color(
                red: 24 / 255,
                green: 24 / 255,
                blue: 26 / 255
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16
            )
        )
    }
}

struct ResultView: View {
    let image: UIImage?

    @Environment(\.openURL)
    private var openURL

    @Binding var productName: String
    @Binding var detectedBarcode: String
    @Binding var recognitionSource: String
    @Binding var confidence: Int
    @Binding var brand: String
    @Binding var category: String
    @Binding var modelNumber: String
    @Binding var evidence: [String]
    @Binding var candidates: [String]
    @Binding var isRecognizing: Bool

    let onCompare: () -> Void

    @State private var originalProductName = ""
    @State private var originalBarcode = ""
    @State private var originalRecognitionSource = ""
    @State private var originalConfidence = 0
    @State private var originalBrand = ""
    @State private var originalCategory = ""
    @State private var originalModelNumber = ""
    @State private var originalEvidence: [String] = []
    @State private var hasCapturedOriginal = false

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        ZStack {
            PremiumAppBackground()

            ScrollView {
                VStack(spacing: 18) {

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 270)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 22
                                )
                            )
                    }

                    if isRecognizing {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(green)
                                .scaleEffect(1.25)

                            Text("AIが画像を検索・照合しています…")
                                .font(.headline)

                            Text("商品名・ブランド・型番を確認中です")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("通常5〜15秒ほどで判定します")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text("正確な商品が出ない場合は、角度や写す面を変えて撮り直してみてください。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(green)

                            Text("AIの商品判定")
                                .font(.headline)

                            Spacer()

                            if confidence > 0 {
                                Text("参考 \(confidence)%")
                                    .font(.caption.bold())
                                    .foregroundStyle(green)
                            }
                        }

                        TextField(
                            "商品名を確認・修正",
                            text: $productName
                        )
                        .font(.title3.bold())
                        .padding(14)
                        .background(
                            Color.white.opacity(0.07)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12
                            )
                        )

                        Text("認識が違う場合は商品名を直接修正できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        Color(
                            red: 24 / 255,
                            green: 24 / 255,
                            blue: 26 / 255
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                    )

                    InfoCard(
                        title: "認識方法",
                        value:
                            recognitionSource.isEmpty
                            ? "判定中"
                            : recognitionSource,
                        icon: "sparkles"
                    )

                    if !brand.isEmpty {
                        InfoCard(
                            title: "ブランド",
                            value: brand,
                            icon: "tag.fill"
                        )
                    }

                    if !modelNumber.isEmpty {
                        InfoCard(
                            title: "型番",
                            value: modelNumber,
                            icon: "number"
                        )
                    }

                    if !category.isEmpty {
                        InfoCard(
                            title: "カテゴリ",
                            value: category,
                            icon: "square.grid.2x2.fill"
                        )
                    }

                    if !detectedBarcode.isEmpty {
                        InfoCard(
                            title: "JAN / EAN",
                            value: detectedBarcode,
                            icon: "barcode"
                        )
                    }

                    if !evidence.isEmpty {
                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {
                            Text("判定の根拠")
                                .font(.headline)

                            ForEach(
                                evidence.prefix(5),
                                id: \.self
                            ) { item in
                                HStack(
                                    alignment: .top
                                ) {
                                    Image(
                                        systemName:
                                            "checkmark.circle.fill"
                                    )
                                    .foregroundStyle(green)

                                    Text(item)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            Color(
                                red: 24 / 255,
                                green: 24 / 255,
                                blue: 26 / 255
                            )
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18
                            )
                        )
                    }

                    if !candidates.isEmpty || hasCapturedOriginal {
                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {
                            Text("近い候補から選ぶ")
                                .font(.headline)

                            if hasCapturedOriginal && !originalProductName.isEmpty {
                                CandidateRow(
                                    title: originalProductName,
                                    isSelected: productName == originalProductName && recognitionSource != "近い候補から選択",
                                    green: green,
                                    onSelect: restoreOriginal,
                                    onConfirm: {
                                        openGoogleSearch(originalProductName)
                                    }
                                )
                            }

                            ForEach(
                                candidates.prefix(3),
                                id: \.self
                            ) { candidate in
                                CandidateRow(
                                    title: candidate,
                                    isSelected: productName == candidate && recognitionSource == "近い候補から選択",
                                    green: green,
                                    onSelect: {
                                        selectCandidate(candidate)
                                    },
                                    onConfirm: {
                                        openGoogleSearch(candidate)
                                    }
                                )
                            }
                        }
                    }

                    Button(action: onCompare) {
                        Label(
                            "販売先と手取り額を比較",
                            systemImage: "chart.bar.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(.white)
                        .background(green)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 16
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        isRecognizing
                        || productName
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                    .opacity(
                        isRecognizing
                        || productName
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                        ? 0.55
                        : 1.0
                    )
                }
                .padding(16)
            }
        }
        .navigationTitle("商品確認")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !isRecognizing {
                captureOriginalIfNeeded()
            }
        }
        .onChange(of: isRecognizing) { newValue in
            if !newValue {
                captureOriginalIfNeeded()
            }
        }
    }

    private func captureOriginalIfNeeded() {
        guard !hasCapturedOriginal,
              !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        originalProductName = productName
        originalBarcode = detectedBarcode
        originalRecognitionSource = recognitionSource
        originalConfidence = confidence
        originalBrand = brand
        originalCategory = category
        originalModelNumber = modelNumber
        originalEvidence = evidence
        hasCapturedOriginal = true
    }

    private func selectCandidate(_ candidate: String) {
        captureOriginalIfNeeded()
        productName = candidate
        detectedBarcode = ""
        recognitionSource = "近い候補から選択"
        confidence = 0
        brand = ""
        category = ""
        modelNumber = ""
        evidence = []
    }

    private func restoreOriginal() {
        guard hasCapturedOriginal else { return }

        productName = originalProductName
        detectedBarcode = originalBarcode
        recognitionSource = originalRecognitionSource
        confidence = originalConfidence
        brand = originalBrand
        category = originalCategory
        modelNumber = originalModelNumber
        evidence = originalEvidence
    }

    private func openGoogleSearch(_ text: String) {
        let encoded = text.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? text

        if let url = URL(
            string: "https://www.google.com/search?q=\(encoded)"
        ) {
            openURL(url)
        }
    }
}

struct CandidateRow: View {
    let title: String
    let isSelected: Bool
    let green: Color
    let onSelect: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(title)
                            .font(.subheadline.bold())
                            .multilineTextAlignment(.leading)

                        Text(
                            isSelected
                            ? "選択中"
                            : "この候補を選ぶ"
                        )
                        .font(.caption.bold())
                    }

                    Spacer()

                    Image(
                        systemName:
                            isSelected
                            ? "checkmark.circle.fill"
                            : "arrow.right.circle.fill"
                    )
                    .font(.title3)
                }
                .foregroundStyle(
                    isSelected
                    ? Color.black
                    : green
                )
                .padding(12)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .background(
                    isSelected
                    ? green
                    : green.opacity(0.12)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                )
            }
            .buttonStyle(.plain)

            Button(action: onConfirm) {
                VStack(spacing: 4) {
                    Image(
                        systemName:
                            "arrow.up.right.square"
                    )
                    .font(.title3)

                    Text("確認")
                        .font(.caption.bold())
                }
                .foregroundStyle(green)
                .frame(width: 56, height: 54)
                .background(
                    Color.white.opacity(0.06)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.065),
                    green.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 14
            )
            .stroke(
                green.opacity(0.16),
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14
            )
        )
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let icon: String

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(green)
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    green.opacity(0.12)
                )
                .clipShape(Circle())

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)
            }

            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.065),
                    green.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 18
            )
            .stroke(
                green.opacity(0.18),
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18
            )
        )
    }
}

struct CompareView: View {
    let productName: String
    let barcode: String
    let brand: String
    let modelNumber: String

    @State private var salePrices: [String: String] = [:]
    @State private var shippingCosts: [String: String] = [:]

    @State private var mercariPrice: YahooPriceResponse?
    @State private var isLoadingMercari = false
    @State private var mercariError = ""

    @State private var yahooPrice: YahooPriceResponse?
    @State private var isLoadingYahoo = false
    @State private var yahooError = ""

    @State private var rakumaPrice: YahooPriceResponse?
    @State private var isLoadingRakuma = false
    @State private var rakumaError = ""

    @StateObject
    private var nearbyStoreLocator =
        NearbyBuybackStoreLocator()

    @Environment(\.openURL)
    private var openURL

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        ZStack {
            PremiumAppBackground()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        Text(
                            productName.isEmpty
                            ? "商品"
                            : productName
                        )
                        .font(.title2.bold())

                        if !barcode.isEmpty {
                            Text("JAN / EAN: \(barcode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    UsedPriceCard(
                        title: "メルカリ 現在出品中相場",
                        countLabel: "現在出品中",
                        emptyMessage: "この商品はメルカリの現在出品中の商品で該当商品が見つかりませんでした。",
                        data: mercariPrice,
                        isLoading: isLoadingMercari,
                        errorText: mercariError,
                        onRetry: {
                            Task {
                                await loadMercariPrice()
                            }
                        }
                    )

                    UsedPriceCard(
                        title: "Yahoo!ショッピング 中古相場",
                        countLabel: "中古",
                        emptyMessage: "この商品はYahoo!ショッピングの中古検索で該当商品が見つかりませんでした。",
                        data: yahooPrice,
                        isLoading: isLoadingYahoo,
                        errorText: yahooError,
                        onRetry: {
                            Task {
                                await loadYahooPrice()
                            }
                        }
                    )

                    UsedPriceCard(
                        title: "楽天ラクマ 現在出品中相場",
                        countLabel: "現在出品中",
                        emptyMessage: "この商品は楽天ラクマの現在出品中の商品で該当商品が見つかりませんでした。",
                        data: rakumaPrice,
                        isLoading: isLoadingRakuma,
                        errorText: rakumaError,
                        onRetry: {
                            Task {
                                await loadRakumaPrice()
                            }
                        }
                    )


                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        Text("この商品を出品する")
                            .font(.headline)

                        Text(
                            "各販売サイトの出品画面を直接開きます"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            SellSiteButton(
                                title: "メルカリ",
                                systemImage: "shippingbox.fill",
                                urlString: "https://jp.mercari.com/sell"
                            )

                            SellSiteButton(
                                title: "Yahoo!フリマ",
                                systemImage: "cart.fill",
                                urlString: "https://paypayfleamarket.yahoo.co.jp/sell"
                            )

                            SellSiteButton(
                                title: "楽天ラクマ",
                                systemImage: "bag.fill",
                                urlString: "https://fril.jp/item/new"
                            )
                        }
                    }
                    .padding(16)
                    .background(
                        Color(
                            red: 24 / 255,
                            green: 24 / 255,
                            blue: 26 / 255
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                        .stroke(
                            green.opacity(0.35),
                            lineWidth: 1
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                    )

                    NearbyBuybackStoresCard(
                        locator: nearbyStoreLocator,
                        searchTerm: buybackSearchTerm
                    )

                }
                .padding(16)
            }
        }
        .navigationTitle("販売先比較")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: productName) {
            // First load after a build/cold start can be slower.
            // Load the two fast marketplaces first, then Rakuma.
            // This prevents the heavier Rakuma request from competing with
            // Mercari/Yahoo on the very first comparison screen.
            async let mercariTask: Void = loadMercariPrice()
            async let yahooTask: Void = loadYahooPrice()

            _ = await (
                mercariTask,
                yahooTask
            )

            await loadRakumaPrice()
        }
    }

    private var buybackSearchTerm: String {
        let source =
            "\(brand) \(productName) \(modelNumber)"
                .lowercased()

        if source.contains("iphone")
            || source.contains("スマホ")
            || source.contains("android")
            || source.contains("pixel")
            || source.contains("galaxy")
            || source.contains("arrows")
            || source.contains("aquos") {
            return "スマホ 買取"
        }

        if source.contains("ギター")
            || source.contains("guitar")
            || source.contains("ベース")
            || source.contains("楽器") {
            return "楽器 買取"
        }

        if source.contains("カメラ")
            || source.contains("camera")
            || source.contains("nikon")
            || source.contains("canon")
            || source.contains("sony α") {
            return "カメラ 買取"
        }

        if source.contains("時計")
            || source.contains("watch")
            || source.contains("rolex")
            || source.contains("seiko") {
            return "時計 買取"
        }

        if source.contains("ゲーム")
            || source.contains("switch")
            || source.contains("playstation")
            || source.contains("xbox") {
            return "ゲーム 買取"
        }

        if source.contains("macbook")
            || source.contains("パソコン")
            || source.contains("pc")
            || source.contains("ipad")
            || source.contains("タブレット") {
            return "パソコン 買取"
        }

        return "買取店"
    }

    private var stableSearchCandidates: [String] {
        var values: [String] = []

        func add(_ raw: String) {
            let value =
                raw.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            guard !value.isEmpty,
                  !values.contains(value) else {
                return
            }

            values.append(value)
        }

        // Most stable key: brand + model number.
        if !modelNumber
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {

            let brandModel =
                [
                    brand,
                    modelNumber
                ]
                .map {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            add(brandModel)
            add(modelNumber)
        }

        // Keep the recognized display/product name as a fallback.
        add(productName)

        // Last fallback: remove common condition/carrier words that can
        // make marketplace searches unnecessarily narrow.
        var simplified = productName

        let removableWords = [
            "新品未使用",
            "新品",
            "未使用",
            "中古",
            "美品",
            "ジャンク",
            "SIMフリー",
            "SIMロック解除済み",
            "docomo",
            "au",
            "SoftBank",
            "softbank",
            "楽天モバイル",
            "ワイモバイル",
            "Y!mobile",
            "UQ",
            "本体のみ",
            "送料無料"
        ]

        for word in removableWords {
            simplified =
                simplified.replacingOccurrences(
                    of: word,
                    with: "",
                    options: [.caseInsensitive]
                )
        }

        simplified =
            simplified
                .split(
                    whereSeparator: {
                        $0.isWhitespace
                    }
                )
                .joined(separator: " ")

        add(simplified)

        return Array(values.prefix(4))
    }

    @MainActor
    private func loadMercariPrice() async {
        let candidates =
            stableSearchCandidates

        guard !candidates.isEmpty else {
            return
        }

        isLoadingMercari = true
        mercariError = ""

        var bestResult: YahooPriceResponse?

        for query in candidates {
            let result =
                await MercariPriceAPI.fetch(
                    productName: query
                )

            if let result,
               result.ok {
                if bestResult == nil
                    || result.count > (bestResult?.count ?? 0) {
                    bestResult = result
                }

                // Enough body listings were found. Avoid unnecessary extra calls.
                if result.count >= 8 {
                    break
                }
            }
        }

        // A first request can hit a freshly started Cloud Run instance.
        // Retry once automatically instead of making the user go back and
        // select another candidate to warm the service.
        if bestResult == nil || (bestResult?.count ?? 0) == 0 {
            try? await Task.sleep(
                nanoseconds: 800_000_000
            )

            if let retryQuery = candidates.first {
                let retry =
                    await MercariPriceAPI.fetch(
                        productName: retryQuery
                    )

                if let retry,
                   retry.ok,
                   retry.count > (bestResult?.count ?? 0) {
                    bestResult = retry
                }
            }
        }

        mercariPrice = bestResult

        if let bestResult,
           bestResult.ok {
            mercariError = ""
        } else {
            mercariError =
                bestResult?.error?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                ?? "メルカリの現在出品価格を取得できませんでした。"
        }

        isLoadingMercari = false
    }

    @MainActor
    private func loadYahooPrice() async {
        let candidates =
            stableSearchCandidates

        guard !candidates.isEmpty
                || !barcode
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty else {
            return
        }

        isLoadingYahoo = true
        yahooError = ""

        // Yahoo can use JAN/EAN, so keep it on every attempt.
        let queries =
            candidates.isEmpty
            ? [productName]
            : candidates

        var bestResult: YahooPriceResponse?

        for query in queries {
            let result =
                await YahooPriceAPI.fetch(
                    productName: query,
                    barcode: barcode
                )

            if let result,
               result.ok {
                if bestResult == nil
                    || result.count > (bestResult?.count ?? 0) {
                    bestResult = result
                }

                if result.count >= 8 {
                    break
                }
            }
        }

        if bestResult == nil || (bestResult?.count ?? 0) == 0 {
            try? await Task.sleep(
                nanoseconds: 800_000_000
            )

            let retryQuery =
                queries.first
                ?? productName

            let retry =
                await YahooPriceAPI.fetch(
                    productName: retryQuery,
                    barcode: barcode
                )

            if let retry,
               retry.ok,
               retry.count > (bestResult?.count ?? 0) {
                bestResult = retry
            }
        }

        yahooPrice = bestResult

        if let bestResult,
           bestResult.ok {
            yahooError = ""
        } else {
            yahooError =
                bestResult?.error?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                ?? "Yahoo!中古価格を取得できませんでした。"
        }

        isLoadingYahoo = false
    }

    @MainActor
    private func loadRakumaPrice() async {
        let candidates =
            Array(
                stableSearchCandidates
                    .prefix(3)
            )

        guard !candidates.isEmpty else {
            return
        }

        isLoadingRakuma = true
        rakumaError = ""

        // Rakuma is slower than the other services, so search the stable
        // candidate names in parallel and keep the result with the most hits.
        let results =
            await withTaskGroup(
                of: YahooPriceResponse?.self
            ) { group in
                for query in candidates {
                    group.addTask {
                        await RakumaPriceAPI.fetch(
                            productName: query
                        )
                    }
                }

                var collected:
                    [YahooPriceResponse] = []

                for await result in group {
                    if let result,
                       result.ok {
                        collected.append(result)
                    }
                }

                return collected
            }

        var bestResult =
            results.max {
                $0.count < $1.count
            }

        // One automatic retry only when all parallel searches returned zero.
        if bestResult == nil
            || (bestResult?.count ?? 0) == 0 {

            try? await Task.sleep(
                nanoseconds: 500_000_000
            )

            if let retryQuery =
                candidates.first {

                let retry =
                    await RakumaPriceAPI.fetch(
                        productName: retryQuery
                    )

                if let retry,
                   retry.ok {
                    bestResult = retry
                }
            }
        }

        rakumaPrice = bestResult

        if let bestResult,
           bestResult.ok {
            rakumaError = ""
        } else {
            rakumaError =
                bestResult?.error?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                ?? "楽天ラクマの現在出品価格を取得できませんでした。"
        }

        isLoadingRakuma = false
    }

    private var bestMarketName: String? {
        marketplaces
            .map {
                (
                    $0.name,
                    netAmount(for: $0)
                )
            }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func numericValue(
        _ text: String
    ) -> Double {
        Double(
            text.replacingOccurrences(
                of: ",",
                with: ""
            )
        ) ?? 0
    }

    private func netAmount(
        for market: Marketplace
    ) -> Double {
        let price = numericValue(
            salePrices[market.name] ?? ""
        )

        let shipping = numericValue(
            shippingCosts[market.name] ?? ""
        )

        return max(
            0,
            price
            - (price * market.feeRate)
            - shipping
        )
    }

    private func binding(
        for key: String,
        dictionary: Binding<[String: String]>
    ) -> Binding<String> {
        Binding(
            get: {
                dictionary.wrappedValue[key] ?? ""
            },
            set: {
                dictionary.wrappedValue[key] = $0
            }
        )
    }

    private func openMarket(
        market: Marketplace
    ) {
        let keyword =
            productName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !keyword.isEmpty else {
            return
        }

        let encoded =
            keyword.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? ""

        if let url = URL(
            string: market.searchBaseURL + encoded
        ) {
            openURL(url)
        }
    }
}


struct NearbyBuybackStore: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let phoneNumber: String?
    let websiteURL: URL?
    let distanceMeters: CLLocationDistance
    let mapItem: MKMapItem

    var distanceText: String {
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters.rounded()))m"
        }

        return String(
            format:
                "%.1fkm",
            distanceMeters / 1000
        )
    }
}

@MainActor
final class NearbyBuybackStoreLocator:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate {

    @Published
    var stores: [NearbyBuybackStore] = []

    @Published
    var isLoading = false

    @Published
    var message = "現在地から近い買取店を探します"

    private let manager =
        CLLocationManager()

    private var pendingSearchTerm =
        "買取店"

    private var didRequestSearch = false

    override init() {
        super.init()

        manager.delegate = self
        manager.desiredAccuracy =
            kCLLocationAccuracyHundredMeters
    }

    func start(
        searchTerm: String
    ) {
        pendingSearchTerm =
            searchTerm.isEmpty
            ? "買取店"
            : searchTerm

        guard !didRequestSearch else {
            return
        }

        didRequestSearch = true

        switch manager.authorizationStatus {
        case .notDetermined:
            message =
                "近くの買取店を表示するため位置情報を確認します"
            manager
                .requestWhenInUseAuthorization()

        case .authorizedAlways,
             .authorizedWhenInUse:
            requestLocation()

        case .denied,
             .restricted:
            message =
                "位置情報を許可すると近くの買取店3件を表示できます"

        @unknown default:
            message =
                "位置情報を確認できませんでした"
        }
    }

    func retry(
        searchTerm: String
    ) {
        pendingSearchTerm =
            searchTerm.isEmpty
            ? "買取店"
            : searchTerm

        didRequestSearch = true

        switch manager.authorizationStatus {
        case .authorizedAlways,
             .authorizedWhenInUse:
            requestLocation()

        case .notDetermined:
            manager
                .requestWhenInUseAuthorization()

        case .denied,
             .restricted:
            message =
                "設定から位置情報を許可してください"

        @unknown default:
            break
        }
    }

    private func requestLocation() {
        isLoading = true
        message =
            "近くの買取店を検索しています…"

        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways,
                 .authorizedWhenInUse:
                requestLocation()

            case .denied,
                 .restricted:
                isLoading = false
                message =
                    "位置情報を許可すると近くの買取店3件を表示できます"

            default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location =
                locations.last else {
            return
        }

        Task { @MainActor in
            searchNearby(
                from: location
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            isLoading = false
            message =
                "現在地を取得できませんでした。もう一度お試しください。"
        }
    }

    private func searchNearby(
        from location: CLLocation
    ) {
        isLoading = true
        message =
            "大手の買取店を検索しています…"

        // 一般利用しやすく、家電・スマホ・PC・ゲーム等を扱う
        // 大手チェーンを中心に検索する。
        let preferredChains = [
            "BOOKOFF",
            "ブックオフ",
            "HARD OFF",
            "ハードオフ",
            "OFF HOUSE",
            "オフハウス",
            "GEO",
            "ゲオ"
        ]

        // 高級ブランド・衣類中心など、今回の用途に合わない店を除外。
        let excludedKeywords = [
            "ブランド",
            "古着",
            "洋服",
            "衣料",
            "着物",
            "ジュエリー",
            "宝石",
            "貴金属",
            "時計専門",
            "バッグ専門"
        ]

        // 商品名を付けると、近くの店舗が検索結果から漏れることがある。
        // まず店舗名を近距離で探し、広域の結果も合わせて距離順に並べる。
        let searchQueries =
            preferredChains.flatMap { chain in
                [
                    (chain, 3000.0),
                    (chain, 12000.0)
                ]
            }

        let searchRadius:
            CLLocationDistance = 12000

        let group =
            DispatchGroup()

        let lock =
            NSLock()

        var collected:
            [MKMapItem] = []

        for (query, radius) in searchQueries {
            group.enter()

            let request =
                MKLocalSearch.Request()

            request.naturalLanguageQuery =
                query

            request.region =
                MKCoordinateRegion(
                    center:
                        location.coordinate,
                    latitudinalMeters:
                        radius * 2,
                    longitudinalMeters:
                        radius * 2
                )

            MKLocalSearch(
                request: request
            )
            .start {
                response,
                _ in

                if let items =
                        response?.mapItems {
                    lock.lock()
                    collected.append(
                        contentsOf:
                            items
                    )
                    lock.unlock()
                }

                group.leave()
            }
        }

        group.notify(
            queue: .main
        ) {
            var seen =
                Set<String>()

            let candidates =
                collected
                .compactMap {
                    item
                    -> NearbyBuybackStore? in

                    guard let itemLocation =
                            item.placemark.location else {
                        return nil
                    }

                    let distance =
                        location.distance(
                            from:
                                itemLocation
                        )

                    guard
                        distance
                        <= searchRadius
                    else {
                        return nil
                    }

                    let name =
                        item.name?
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                        ?? ""

                    guard
                        !name.isEmpty
                    else {
                        return nil
                    }

                    let upperName =
                        name.uppercased()

                    let isPreferredChain =
                        preferredChains.contains {
                            chain in

                            upperName.contains(
                                chain.uppercased()
                            )
                        }

                    guard
                        isPreferredChain
                    else {
                        return nil
                    }

                    let isExcluded =
                        excludedKeywords.contains {
                            keyword in

                            name.contains(
                                keyword
                            )
                        }

                    guard
                        !isExcluded
                    else {
                        return nil
                    }

                    let address =
                        [
                            item.placemark
                                .administrativeArea,
                            item.placemark
                                .locality,
                            item.placemark
                                .subLocality,
                            item.placemark
                                .thoroughfare
                        ]
                        .compactMap { $0 }
                        .joined()

                    // Apple マップに URL がない駅前店は、確認済みの公式店舗ページを使う。
                    // 住所でも照合し、同名の別店舗に適用しない。
                    let isHachiojiStationBookoff =
                        (upperName.contains("BOOKOFF")
                            || name.contains("ブックオフ"))
                        && name.contains("八王子駅北口店")
                        && address.contains("旭町")

                    let officialStationURL =
                        isHachiojiStationBookoff
                        ? URL(
                            string:
                                "https://www.bookoff.co.jp/shop/shop20130.html"
                        )
                        : nil

                    // 公式ページも地図の URL もない店舗は表示しない。
                    guard let websiteURL =
                        officialStationURL ?? item.url else {
                        return nil
                    }

                    let key =
                        "\(name)|\(address)"

                    guard
                        !seen.contains(key)
                    else {
                        return nil
                    }

                    seen.insert(key)

                    return NearbyBuybackStore(
                        name: name,
                        address: address,
                        phoneNumber:
                            item.phoneNumber,
                        websiteURL:
                            websiteURL,
                        distanceMeters:
                            distance,
                        mapItem: item
                    )
                }
                .sorted {
                    $0.distanceMeters
                    < $1.distanceMeters
                }

            self.stores =
                Array(
                    candidates.prefix(3)
                )

            self.isLoading = false

            if self.stores.isEmpty {
                self.message =
                    "12km以内に条件に合う大手買取店が見つかりませんでした"
            } else if self.stores.count < 3 {
                self.message =
                    "近くの大手買取店を表示しています"
            } else {
                self.message =
                    "大手買取店を近い順に3件表示しています"
            }
        }
    }
}

struct NearbyBuybackStoresCard: View {
    @ObservedObject
    var locator:
        NearbyBuybackStoreLocator

    let searchTerm: String

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("近くの大手買取店")
                        .font(.headline)

                    Text(locator.message)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                }

                Spacer()

                if locator.isLoading {
                    ProgressView()
                        .tint(green)
                } else {
                    Button {
                        locator.retry(
                            searchTerm:
                                searchTerm
                        )
                    } label: {
                        Image(
                            systemName:
                                "arrow.clockwise"
                        )
                        .foregroundStyle(
                            green
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !locator.stores.isEmpty {
                ForEach(
                    Array(
                        locator.stores
                            .enumerated()
                    ),
                    id: \.element.id
                ) {
                    index,
                    store in

                    NearbyBuybackStoreRow(
                        rank:
                            index + 1,
                        store:
                            store
                    )

                    if index
                        < locator.stores.count - 1 {
                        Divider()
                            .overlay(
                                Color.white
                                    .opacity(0.10)
                            )
                    }
                }
            } else if !locator.isLoading {
                Button {
                    locator.retry(
                        searchTerm:
                            searchTerm
                    )
                } label: {
                    Label(
                        "近くの買取店を検索",
                        systemImage:
                            "location.fill"
                    )
                    .font(
                        .subheadline.bold()
                    )
                    .foregroundStyle(green)
                    .frame(
                        maxWidth:
                            .infinity
                    )
                    .padding(
                        .vertical,
                        11
                    )
                    .background(
                        green.opacity(0.08)
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.06),
                    green.opacity(0.035)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 18
            )
            .stroke(
                green.opacity(0.28),
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18
            )
        )
        .onAppear {
            locator.start(
                searchTerm:
                    searchTerm
            )
        }
    }
}

struct NearbyBuybackStoreRow: View {
    let rank: Int
    let store: NearbyBuybackStore

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack(
                alignment: .top,
                spacing: 10
            ) {
                Text("\(rank)")
                    .font(
                        .caption.bold()
                    )
                    .foregroundStyle(
                        .black
                    )
                    .frame(
                        width: 26,
                        height: 26
                    )
                    .background(green)
                    .clipShape(Circle())

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(store.name)
                        .font(
                            .subheadline.bold()
                        )
                        .foregroundStyle(
                            .white
                        )

                    HStack(spacing: 8) {
                        Text(
                            store.distanceText
                        )
                        .font(
                            .caption.bold()
                        )
                        .foregroundStyle(
                            green
                        )

                        if !store.address.isEmpty {
                            Text(
                                store.address
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                            .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    store.mapItem
                        .openInMaps(
                            launchOptions: [
                                MKLaunchOptionsDirectionsModeKey:
                                    MKLaunchOptionsDirectionsModeDriving
                            ]
                        )
                } label: {
                    Label(
                        "地図で見る",
                        systemImage:
                            "map.fill"
                    )
                }
                .buttonStyle(
                    NearbyStoreActionStyle()
                )

                if let phone =
                        store.phoneNumber,
                   let telURL =
                        URL(
                            string:
                                "tel://\(phone.filter { $0.isNumber || $0 == "+" })"
                        ) {
                    Link(
                        destination:
                            telURL
                    ) {
                        Label(
                            "電話",
                            systemImage:
                                "phone.fill"
                        )
                    }
                    .buttonStyle(
                        NearbyStoreActionStyle()
                    )
                }

                if let websiteURL =
                        store.websiteURL {
                    Link(
                        destination:
                            websiteURL
                    ) {
                        Label(
                            "店舗サイト",
                            systemImage:
                                "safari.fill"
                        )
                    }
                    .buttonStyle(
                        NearbyStoreActionStyle()
                    )
                }
            }
        }
        .padding(
            .vertical,
            3
        )
    }
}

struct NearbyStoreActionStyle:
    ButtonStyle {

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    func makeBody(
        configuration:
            Configuration
    ) -> some View {
        configuration.label
            .font(
                .caption.bold()
            )
            .foregroundStyle(green)
            .padding(
                .horizontal,
                10
            )
            .padding(
                .vertical,
                7
            )
            .background(
                green.opacity(
                    configuration.isPressed
                    ? 0.16
                    : 0.08
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10
                )
            )
    }
}

struct SellSiteButton: View {
    let title: String
    let systemImage: String
    let urlString: String

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                VStack(spacing: 7) {
                    Image(systemName: systemImage)
                        .font(.title3)

                    Text(title)
                        .font(.caption.bold())
                        .multilineTextAlignment(.center)

                    Text("出品")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 78
                )
                .foregroundStyle(green)
                .background(
                    green.opacity(0.10)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: 14
                    )
                    .stroke(
                        green.opacity(0.35),
                        lineWidth: 1
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14
                    )
                )
            }
            .buttonStyle(.plain)
        }
    }
}

enum PriceBandSelection {
    case low
    case median
    case high
}

struct UsedPriceCard: View {
    let title: String
    let countLabel: String
    let emptyMessage: String
    let data: YahooPriceResponse?
    let isLoading: Bool
    let errorText: String
    let onRetry: () -> Void

    @State private var selectedBand:
        PriceBandSelection = .median

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    private var selectedItems: [YahooPriceItem] {
        guard let data,
              !data.items.isEmpty else {
            return []
        }

        switch selectedBand {
        case .low:
            return Array(
                data.items
                    .sorted { $0.price < $1.price }
                    .prefix(5)
            )

        case .median:
            return Array(
                data.items
                    .sorted {
                        abs($0.price - data.medianPrice)
                        < abs($1.price - data.medianPrice)
                    }
                    .prefix(5)
            )
            .sorted { $0.price < $1.price }

        case .high:
            return Array(
                data.items
                    .sorted { $0.price > $1.price }
                    .prefix(5)
            )
        }
    }

    private var selectedBandTitle: String {
        switch selectedBand {
        case .low:
            return "最安値付近の商品"
        case .median:
            return "中央値付近の商品"
        case .high:
            return "最高値付近の商品"
        }
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                Label(
                    title,
                    systemImage:
                        "cart.fill"
                )
                .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(green)
                }
            }

            if isLoading {
                Text(
                    "中古価格を取得しています…"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

            } else if let data, data.ok {
                if data.count > 0 {
                    HStack(spacing: 10) {
                        Button {
                            selectedBand = .low
                        } label: {
                            PriceStat(
                                title: "最安値",
                                value: data.minPrice,
                                isSelected:
                                    selectedBand == .low
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            selectedBand = .median
                        } label: {
                            PriceStat(
                                title: "中央値",
                                value: data.medianPrice,
                                isSelected:
                                    selectedBand == .median
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            selectedBand = .high
                        } label: {
                            PriceStat(
                                title: "最高値",
                                value: data.maxPrice,
                                isSelected:
                                    selectedBand == .high
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text(
                        "\(countLabel) \(data.count)件を取得"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(
                        "価格をタップすると、その価格帯の商品を表示します"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    if !selectedItems.isEmpty {
                        Divider()

                        Text(selectedBandTitle)
                            .font(.subheadline.bold())

                        ForEach(
                            selectedItems
                        ) { item in
                            if let url =
                                URL(
                                    string:
                                        item.url
                                ) {
                                Link(
                                    destination: url
                                ) {
                                    HStack(
                                        alignment: .top,
                                        spacing: 10
                                    ) {
                                        VStack(
                                            alignment: .leading,
                                            spacing: 4
                                        ) {
                                            Text(item.name)
                                                .font(
                                                    .subheadline
                                                )
                                                .lineLimit(2)

                                            if let seller =
                                                item.seller,
                                               !seller.isEmpty {
                                                Text(seller)
                                                    .font(
                                                        .caption2
                                                    )
                                                    .foregroundStyle(
                                                        .secondary
                                                    )
                                            }
                                        }

                                        Spacer()

                                        Text(
                                            "\(item.price.formatted())円"
                                        )
                                        .font(
                                            .headline
                                        )
                                        .foregroundStyle(
                                            green
                                        )
                                    }
                                    .padding(10)
                                    .background(
                                        Color.white
                                            .opacity(
                                                0.05
                                            )
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius:
                                                10
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                } else {
                    Text(
                        emptyMessage
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Button(
                        action: onRetry
                    ) {
                        Label(
                            "もう一度検索",
                            systemImage:
                                "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(green)
                }

            } else {
                Text(
                    errorText.isEmpty
                    ? "中古価格を取得できませんでした。"
                    : errorText
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button(
                    action: onRetry
                ) {
                    Label(
                        "もう一度検索",
                        systemImage:
                            "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(green)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(
                        red: 18 / 255,
                        green: 30 / 255,
                        blue: 26 / 255
                    ),
                    Color(
                        red: 20 / 255,
                        green: 20 / 255,
                        blue: 22 / 255
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 18
            )
            .stroke(
                green.opacity(0.35),
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18
            )
        )
    }
}

struct PriceStat: View {
    let title: String
    let value: Int
    let isSelected: Bool

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(
                "\(value.formatted())円"
            )
            .font(.subheadline.bold())
            .foregroundStyle(green)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(10)
        .background(
            isSelected
            ? green.opacity(0.12)
            : Color.white.opacity(0.05)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 10
            )
            .stroke(
                isSelected
                ? green.opacity(0.65)
                : Color.clear,
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 10
            )
        )
    }
}

struct MarketplaceCard: View {
    let market: Marketplace

    @Binding var salePrice: String
    @Binding var shippingCost: String

    let isBest: Bool
    let onSearch: () -> Void

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    private var salePriceValue: Double {
        Double(
            salePrice
                .replacingOccurrences(
                    of: ",",
                    with: ""
                )
        ) ?? 0
    }

    private var shippingValue: Double {
        Double(
            shippingCost
                .replacingOccurrences(
                    of: ",",
                    with: ""
                )
        ) ?? 0
    }

    private var fee: Double {
        salePriceValue
        * market.feeRate
    }

    private var netAmount: Double {
        max(
            0,
            salePriceValue
            - fee
            - shippingValue
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Text(market.name)
                    .font(.title3.bold())

                Spacer()

                if isBest {
                    Text("現在の最高手取り")
                        .font(.caption2.bold())
                        .foregroundStyle(.black)
                        .padding(
                            .horizontal,
                            9
                        )
                        .padding(
                            .vertical,
                            5
                        )
                        .background(green)
                        .clipShape(Capsule())
                } else {
                    Text(
                        "手数料 約\(Int(market.feeRate * 100))%"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Button(
                action: onSearch
            ) {
                HStack {
                    Label(
                        "\(market.name)で相場を見る",
                        systemImage:
                            "arrow.up.right.square"
                    )
                    .font(.headline)

                    Spacer()

                    Image(
                        systemName:
                            "chevron.right"
                    )
                }
                .foregroundStyle(green)
                .padding(12)
                .background(
                    green.opacity(0.10)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                )
            }
            .buttonStyle(.plain)

            Divider()

            HStack {
                Text("想定販売価格")

                Spacer()

                TextField(
                    "0",
                    text: $salePrice
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(
                    .trailing
                )
                .frame(width: 100)

                Text("円")
            }

            HStack {
                Text("送料")

                Spacer()

                TextField(
                    "0",
                    text: $shippingCost
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(
                    .trailing
                )
                .frame(width: 100)

                Text("円")
            }

            HStack {
                Text("販売手数料")
                Spacer()
                Text(
                    "\(Int(fee.rounded()))円"
                )
            }

            Divider()

            HStack {
                Text("予想手取り")
                Spacer()
                Text(
                    "\(Int(netAmount.rounded()))円"
                )
                .font(.title2.bold())
                .foregroundStyle(green)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.065),
                    Color(
                        red: 4 / 255,
                        green: 25 / 255,
                        blue: 18 / 255
                    ).opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 18
            )
            .stroke(
                isBest
                ? green.opacity(0.65)
                : Color.clear,
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18
            )
        )
    }
}

enum RakumaPriceAPI {
    private static let endpoint =
        "https://pasha-satei-vision-api-500716860725.asia-northeast1.run.app"

    static func fetch(
        productName: String
    ) async -> YahooPriceResponse? {
        guard let url = URL(string: endpoint) else {
            return nil
        }

        let body: [String: Any] = [
            "action": "rakumaUsedPrice",
            "productName": productName
        ]

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: body
        ) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = jsonData
        request.timeoutInterval = 35

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse,
                  200...299 ~= http.statusCode else {
                return nil
            }

            return try JSONDecoder().decode(
                YahooPriceResponse.self,
                from: data
            )
        } catch {
            return nil
        }
    }
}

enum MercariPriceAPI {
    private static let endpoint =
        "https://pasha-satei-vision-api-500716860725.asia-northeast1.run.app"

    static func fetch(
        productName: String
    ) async -> YahooPriceResponse? {
        guard let url = URL(string: endpoint) else {
            return nil
        }

        let body: [String: Any] = [
            "action": "mercariUsedPrice",
            "productName": productName
        ]

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: body
        ) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = jsonData
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse,
                  200...299 ~= http.statusCode else {
                return nil
            }

            return try JSONDecoder().decode(
                YahooPriceResponse.self,
                from: data
            )
        } catch {
            return nil
        }
    }
}

enum YahooPriceAPI {
    private static let endpoint =
        "https://pasha-satei-vision-api-500716860725.asia-northeast1.run.app"

    static func fetch(
        productName: String,
        barcode: String
    ) async -> YahooPriceResponse? {

        guard let url =
                URL(string: endpoint)
        else {
            return nil
        }

        let body: [String: Any] = [
            "action": "yahooUsedPrice",
            "productName": productName,
            "barcode": barcode
        ]

        guard let jsonData =
                try? JSONSerialization
                    .data(
                        withJSONObject: body
                    )
        else {
            return nil
        }

        var request =
            URLRequest(url: url)

        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.httpBody = jsonData
        request.timeoutInterval = 20

        do {
            let (data, response) =
                try await URLSession
                    .shared
                    .data(
                        for: request
                    )

            guard let http =
                    response
                    as? HTTPURLResponse,
                  200...299 ~=
                    http.statusCode
            else {
                return nil
            }

            return try JSONDecoder()
                .decode(
                    YahooPriceResponse.self,
                    from: data
                )

        } catch {
            return nil
        }
    }
}

enum GeminiProductAPI {
    private static let endpoint =
        "https://pasha-satei-vision-api-500716860725.asia-northeast1.run.app"

    // Uploading the original iPhone photo can be several MB.
    // A 1600 px long edge preserves logos/model text well enough for Gemini
    // while greatly reducing JPEG/Base64 upload time.
    private static func preparedImage(
        _ image: UIImage
    ) -> UIImage {
        let maxEdge: CGFloat = 1600
        let size = image.size
        let longest = max(size.width, size.height)

        guard longest > maxEdge,
              size.width > 0,
              size.height > 0 else {
            return image
        }

        let scale = maxEdge / longest
        let target = CGSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(
            size: target,
            format: format
        ).image { _ in
            image.draw(
                in: CGRect(
                    origin: .zero,
                    size: target
                )
            )
        }
    }

    private static func centerCrop(
        _ image: UIImage
    ) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        guard width > 0,
              height > 0 else {
            return image
        }

        // Keep a generous 82% center region so a slightly off-center product
        // is still retained while background / nearby cases are reduced.
        let cropScale: CGFloat = 0.82
        let cropWidth = width * cropScale
        let cropHeight = height * cropScale

        let rect = CGRect(
            x: (width - cropWidth) / 2,
            y: (height - cropHeight) / 2,
            width: cropWidth,
            height: cropHeight
        ).integral

        guard let cropped =
                cgImage.cropping(to: rect) else {
            return image
        }

        return UIImage(
            cgImage: cropped,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }

    static func analyze(
        image: UIImage,
        ocrText: String,
        barcode: String
    ) async -> GeminiProductResponse? {

        guard let url =
                URL(string: endpoint) else {
            return nil
        }

        let uploadImage =
            preparedImage(image)

        let focusedImage =
            preparedImage(
                centerCrop(image)
            )

        guard let imageData =
                uploadImage.jpegData(
                    compressionQuality: 0.72
                ),
              let focusedImageData =
                focusedImage.jpegData(
                    compressionQuality: 0.70
                ) else {
            return nil
        }

        // Limit OCR text sent to the server so accidental long OCR output
        // cannot inflate the request or distract product identification.
        let compactOCR =
            String(ocrText.prefix(1200))

        let body: [String: Any] = [
            "imageBase64":
                imageData
                    .base64EncodedString(),
            "focusedImageBase64":
                focusedImageData
                    .base64EncodedString(),
            "ocrText": compactOCR,
            "barcode": barcode
        ]

        guard let jsonData =
                try? JSONSerialization
                    .data(
                        withJSONObject: body
                    ) else {
            return nil
        }

        var request =
            URLRequest(url: url)

        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.httpBody = jsonData

        // Do not let a slow Cloud Run/Gemini request hold the camera result
        // screen for 30-60 seconds.
        request.timeoutInterval = 16

        do {
            let (data, response) =
                try await URLSession
                    .shared
                    .data(
                        for: request
                    )

            guard let http =
                    response
                    as? HTTPURLResponse,
                  200...299 ~=
                    http.statusCode else {
                return nil
            }

            return try JSONDecoder()
                .decode(
                    GeminiProductResponse.self,
                    from: data
                )
        } catch {
            return nil
        }
    }
}

enum LocalProductRecognizer {
    static func recognize(
        image: UIImage
    ) async -> LocalRecognitionResult {

        guard let cgImage =
                image.cgImage else {
            return LocalRecognitionResult(
                text: "",
                barcode: ""
            )
        }

        async let textTask =
            recognizeText(cgImage)

        async let barcodeTask =
            recognizeBarcode(cgImage)

        return await LocalRecognitionResult(
            text: textTask,
            barcode: barcodeTask
        )
    }

    private static func recognizeText(
        _ cgImage: CGImage
    ) async -> String {

        await withCheckedContinuation {
            continuation in

            let request =
                VNRecognizeTextRequest {
                    request,
                    error in

                    guard error == nil else {
                        continuation.resume(
                            returning: ""
                        )
                        return
                    }

                    let observations =
                        request.results
                        as? [
                            VNRecognizedTextObservation
                        ]
                        ?? []

                    let lines =
                        observations
                            .compactMap {
                                $0
                                    .topCandidates(1)
                                    .first?
                                    .string
                            }

                    continuation.resume(
                        returning:
                            lines.joined(
                                separator: "\n"
                            )
                    )
                }

            // OCR is supplemental evidence. Gemini still performs the main
            // visual recognition, so prefer low latency here.
            request.recognitionLevel =
                .fast

            request.usesLanguageCorrection =
                false

            request.recognitionLanguages = [
                "ja-JP",
                "en-US"
            ]

            let handler =
                VNImageRequestHandler(
                    cgImage: cgImage
                )

            DispatchQueue.global(
                qos: .userInitiated
            )
            .async {
                do {
                    try handler.perform(
                        [request]
                    )
                } catch {
                    continuation.resume(
                        returning: ""
                    )
                }
            }
        }
    }

    private static func recognizeBarcode(
        _ cgImage: CGImage
    ) async -> String {

        await withCheckedContinuation {
            continuation in

            let request =
                VNDetectBarcodesRequest {
                    request,
                    error in

                    guard error == nil else {
                        continuation.resume(
                            returning: ""
                        )
                        return
                    }

                    let observations =
                        request.results
                        as? [
                            VNBarcodeObservation
                        ]
                        ?? []

                    let value =
                        observations
                            .compactMap {
                                $0.payloadStringValue
                            }
                            .first {
                                code in

                                let digits =
                                    code.allSatisfy {
                                        $0.isNumber
                                    }

                                let validLength =
                                    [8, 12, 13]
                                        .contains(
                                            code.count
                                        )

                                return digits
                                    && validLength
                            }
                        ?? ""

                    continuation.resume(
                        returning: value
                    )
                }

            request.symbologies = [
                .ean13,
                .ean8,
                .upce
            ]

            let handler =
                VNImageRequestHandler(
                    cgImage: cgImage
                )

            DispatchQueue.global(
                qos: .userInitiated
            )
            .async {
                do {
                    try handler.perform(
                        [request]
                    )
                } catch {
                    continuation.resume(
                        returning: ""
                    )
                }
            }
        }
    }
}

struct CameraPicker:
    UIViewControllerRepresentable {

    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator()
        -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(
        context: Context
    ) -> UIImagePickerController {

        let picker =
            UIImagePickerController()

        picker.sourceType =
            UIImagePickerController
                .isSourceTypeAvailable(
                    .camera
                )
            ? .camera
            : .photoLibrary

        picker.delegate =
            context.coordinator

        return picker
    }

    func updateUIViewController(
        _ uiViewController:
            UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator:
        NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {

        let parent: CameraPicker

        init(
            _ parent: CameraPicker
        ) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker:
                UIImagePickerController,
            didFinishPickingMediaWithInfo info:
                [
                    UIImagePickerController
                        .InfoKey: Any
                ]
        ) {
            guard let image =
                    info[
                        .originalImage
                    ] as? UIImage else {
                parent.onCancel()
                return
            }

            parent.onImage(image)
        }

        func imagePickerControllerDidCancel(
            _ picker:
                UIImagePickerController
        ) {
            parent.onCancel()
        }
    }
}

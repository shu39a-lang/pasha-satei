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

            RemoteGuitarHero(
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

struct RemoteGuitarHero: View {
    let compact: Bool

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

            AsyncImage(
                url: URL(
                    string:
                        "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=700&q=88"
                )
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    Color(
                        red: 10 / 255,
                        green: 26 / 255,
                        blue: 20 / 255
                    )

                    ProgressView()
                        .tint(green)
                }
            }
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
            "近くの買取店を検索しています…"

        let searchQueries =
            Array(
                Set([
                    pendingSearchTerm,
                    "買取店",
                    "リサイクルショップ",
                    "中古 買取"
                ])
            )

        let searchRadius:
            CLLocationDistance = 12000

        let group =
            DispatchGroup()

        let lock =
            NSLock()

        var collected:
            [MKMapItem] = []

        for query in searchQueries {
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
                        searchRadius * 2,
                    longitudinalMeters:
                        searchRadius * 2
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

                    guard distance <= searchRadius else {
                        return nil
                    }

                    let name =
                        item.name?
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                        ?? "買取店"

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

                    let key =
                        "\(name)|\(address)"

                    guard !seen.contains(key) else {
                        return nil
                    }

                    seen.insert(key)

                    return NearbyBuybackStore(
                        name: name,
                        address: address,
                        phoneNumber:
                            item.phoneNumber,
                        websiteURL:
                            item.url,
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
                    "現在地から12km以内に買取店が見つかりませんでした"
            } else if self.stores.count < 3 {
                self.message =
                    "現在地から12km以内の近い店舗を表示しています"
            } else {
                self.message =
                    "現在地から近い順に3件表示しています"
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
                    Text("近くの買取店")
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

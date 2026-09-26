import SwiftUI
import PhotosUI
import Photos
import UIKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
@preconcurrency import Vision

enum AppRoute: Hashable {
    case result
    case compare(
        productName: String,
        barcode: String,
        brand: String,
        modelNumber: String,
        draftID: String
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

struct ListingTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        self.text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct SavedListingDraft: Codable {
    var id: String
    var productName: String
    var barcode: String
    var brand: String
    var modelNumber: String
    var body: String = ""
    var checkedPhotos: [String] = []
    var salePrices: [String: String] = [:]
    var shippingCosts: [String: String] = [:]
    var extraPhotoCount: Int = 0
}

private enum ListingDraftStore {
    private static let latestKey = "pasha.latestListingDraftID"

    private static var root: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let url = base.appendingPathComponent("ListingDrafts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func folder(_ id: String) -> URL? {
        guard UUID(uuidString: id) != nil, let root else { return nil }
        let url = root.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load(_ id: String) -> SavedListingDraft? {
        guard let url = folder(id)?.appendingPathComponent("draft.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedListingDraft.self, from: data)
    }

    static func latest() -> SavedListingDraft? {
        guard let id = UserDefaults.standard.string(forKey: latestKey) else { return nil }
        return load(id)
    }

    static func update(
        id: String, productName: String, barcode: String,
        brand: String, modelNumber: String,
        change: (inout SavedListingDraft) -> Void = { _ in }
    ) {
        guard let directory = folder(id) else { return }
        var draft = load(id) ?? SavedListingDraft(
            id: id, productName: productName, barcode: barcode,
            brand: brand, modelNumber: modelNumber
        )
        draft.productName = productName
        draft.barcode = barcode
        draft.brand = brand
        draft.modelNumber = modelNumber
        change(&draft)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        do {
            try data.write(to: directory.appendingPathComponent("draft.json"), options: .atomic)
            UserDefaults.standard.set(id, forKey: latestKey)
        } catch {
            // The editable values remain visible even if local storage is unavailable.
        }
    }

    static func photo(id: String, index: Int) -> UIImage? {
        guard let directory = folder(id), index >= 0,
              let data = try? Data(contentsOf: directory.appendingPathComponent("photo_\(index).jpg"))
        else { return nil }
        return UIImage(data: data)
    }

    static func savePhotos(id: String, main: UIImage?, extras: [UIImage]) {
        guard let directory = folder(id) else { return }
        let photos = (main.map { [$0] } ?? []) + extras
        for (index, image) in photos.enumerated() {
            let longest = max(image.size.width, image.size.height)
            let ratio = longest > 1600 ? 1600 / longest : 1
            let storedImage: UIImage
            if ratio < 1 {
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                storedImage = UIGraphicsImageRenderer(size: size).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
            } else {
                storedImage = image
            }
            guard let data = storedImage.jpegData(compressionQuality: 0.78) else { continue }
            try? data.write(
                to: directory.appendingPathComponent("photo_\(index).jpg"), options: .atomic
            )
        }
        // Remove an old last photo after the user deletes it from the draft.
        var index = photos.count
        while FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("photo_\(index).jpg").path
        ) {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent("photo_\(index).jpg")
            )
            index += 1
        }
    }
}


struct PremiumAppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 10 / 255, green: 11 / 255, blue: 14 / 255)
            RadialGradient(
                colors: [
                    Color(red: 42 / 255, green: 83 / 255, blue: 84 / 255).opacity(0.24),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 460
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
    @State private var draftID = UUID().uuidString

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
                        image: $selectedImage,
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
                                    modelNumber: modelNumber,
                                    draftID: draftID
                                )
                            )
                        }
                    )
                    .id(draftID)

                case let .compare(
                    selectedProductName,
                    selectedBarcode,
                    selectedBrand,
                    selectedModelNumber,
                    selectedDraftID
                ):
                    CompareView(
                        image: $selectedImage,
                        productName: selectedProductName,
                        barcode: selectedBarcode,
                        brand: selectedBrand,
                        modelNumber: selectedModelNumber,
                        draftID: selectedDraftID
                    )
                    .id(selectedDraftID)
                }
            }
        }
        .onAppear {
            guard !hasPreviousSearchResult,
                  let saved = ListingDraftStore.latest() else { return }
            draftID = saved.id
            productName = saved.productName
            detectedBarcode = saved.barcode
            brand = saved.brand
            modelNumber = saved.modelNumber
            selectedImage = ListingDraftStore.photo(id: saved.id, index: 0)
            hasPreviousSearchResult = true
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCamera) {
    CameraPicker(
        onImage: { image in
            draftID = UUID().uuidString
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

                draftID = UUID().uuidString
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 15 : 20) {
                HomeHeroSection(compact: compact)

                HomeCameraButton(compact: compact) {
                    showCamera = true
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    HomePhotoPicker(selectedPhoto: $selectedPhoto, compact: compact)
                    if hasPreviousResult {
                        HomePreviousButton(compact: compact, action: onOpenPreviousResult)
                    }
                }

                HomeGuideButton(compact: compact) {
                    showUsageGuide = true
                }

                HomeFeatureRow(compact: compact)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 7)
            .padding(.bottom, 25)
        }
        .scrollIndicators(.hidden)
    }
}

struct HomeHeroSection: View {
    let compact: Bool
    private let copper = Color(red: 240 / 255, green: 166 / 255, blue: 116 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(copper)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("パシャ査定")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("PASHA SATEI")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(copper)
                    }
                }
                Spacer()
                MarketplaceLogoRow()
                    .scaleEffect(0.73, anchor: .trailing)
                    .frame(width: 118, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("写真から、売れる相場へ。")
                    .font(.system(size: compact ? 21 : 25, weight: .bold))
                    .foregroundStyle(.white)
                Text("写真1枚で商品を判定し、3サイトの販売中価格を比較")
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.white.opacity(0.76))
            }

            Image(uiImage: ResaleItemsHero.heroImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 133 : 163)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Text("撮影する商品を選ぶ")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.75))
                        .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }
}

struct HomeGuideButton: View {
    let compact: Bool
    let action: () -> Void

    private let green = Color(
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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

    private let copper = Color(red: 240 / 255, green: 166 / 255, blue: 116 / 255)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: compact ? 60 : 70, weight: .regular))
                    .foregroundStyle(Color(red: 16 / 255, green: 22 / 255, blue: 25 / 255))
                    .frame(width: compact ? 132 : 150, height: compact ? 132 : 150)
                    .background(copper, in: Circle())
                    .shadow(color: copper.opacity(0.29), radius: 23)
                Text("写真を撮る")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("写真を撮る")
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
            HStack(spacing: 5) {
                Image(
                    systemName:
                        "photo.fill"
                )
                .font(.title3)

                Text("写真を選ぶ")
                    .font(.subheadline.bold())

                
            }
            .padding(.horizontal, 9)
            .frame(
                maxWidth: .infinity,
                minHeight: 50
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
    )

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(
                    systemName:
                        "clock.arrow.circlepath"
                )

                Text(
                    "前の結果を見る"
                )
                .font(.subheadline.bold())

                
            }
            .padding(.horizontal, 9)
            .frame(
                maxWidth: .infinity,
                minHeight: 50
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
    static let heroImage: UIImage = {
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
                    green.opacity(0.20),
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
                            ? 42
                            : 48,
                        weight: .regular
                    )
                )
                .foregroundStyle(green.opacity(0.30))
                .shadow(
                    color:
                        green.opacity(0.08),
                    radius: 4
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
    @Binding var image: UIImage?

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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
    @Binding var image: UIImage?
    let productName: String
    let barcode: String
    let brand: String
    let modelNumber: String
    let draftID: String

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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
    )

    var body: some View {
        ZStack {
            PremiumAppBackground()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 165)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

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
                        Text("この商品を出品するには")
                            .font(.headline)

                        Text(
                            "写真・文章・価格を準備してから出品先を開きます"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ListingPreparationCard(
                            image: image,
                            productName: productName,
                            barcode: barcode,
                            brand: brand,
                            modelNumber: modelNumber,
                            draftID: draftID,
                            salePrices: $salePrices,
                            shippingCosts: $shippingCosts,
                            bestMarketName: bestMarketName,
                            onSearch: { market in openMarket(market: market) }
                        )
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
        .onAppear {
            if let saved = ListingDraftStore.load(draftID) {
                salePrices = saved.salePrices
                shippingCosts = saved.shippingCosts
            }
            persistPriceFields()
        }
        .onChange(of: salePrices) { _ in persistPriceFields() }
        .onChange(of: shippingCosts) { _ in persistPriceFields() }
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

    private func persistPriceFields() {
        ListingDraftStore.update(
            id: draftID, productName: productName, barcode: barcode,
            brand: brand, modelNumber: modelNumber
        ) { draft in
            draft.salePrices = salePrices
            draft.shippingCosts = shippingCosts
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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

struct ListingPreparationCard: View {
    let image: UIImage?
    let productName: String
    let barcode: String
    let brand: String
    let modelNumber: String
    let draftID: String
    @Binding var salePrices: [String: String]
    @Binding var shippingCosts: [String: String]
    let bestMarketName: String?
    let onSearch: (Marketplace) -> Void

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var extraPhotos: [UIImage] = []
    @State private var showCamera = false
    @State private var showTextExporter = false
    @State private var draftBody = ""
    @State private var statusMessage = ""
    @State private var checkedPhotos: Set<String> = []

    private let photoChecks = ["正面", "裏面", "側面", "型番", "傷・汚れ", "付属品"]

    private let green = Color(
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
    )
    private let blue = Color(red: 240 / 255, green: 166 / 255, blue: 116 / 255)

    private var allPhotos: [UIImage] {
        (image.map { [$0] } ?? []) + extraPhotos
    }

    private var fullDraft: String {
        draftBody
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("写真と文章を整えて出品")
                .font(.subheadline.bold())

            Text("入力した文章・価格・追加写真は、このiPhoneに自動保存されます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("① 写真を確認して保存")
                .font(.caption.bold())
                .foregroundStyle(blue)

            Text("撮影できたものに印を付けてください。不要な項目はそのままで大丈夫です。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                ForEach(photoChecks, id: \.self) { item in
                    Button {
                        if checkedPhotos.contains(item) {
                            checkedPhotos.remove(item)
                        } else {
                            checkedPhotos.insert(item)
                        }
                        persistDraft()
                    } label: {
                        Label(item, systemImage: checkedPhotos.contains(item) ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(blue.opacity(checkedPhotos.contains(item) ? 0.25 : 0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(blue)
                }
            }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    Label("写真を追加", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    showCamera = true
                } label: {
                    Label("撮影して追加", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(extraPhotos.count >= 9)
            }
            .font(.caption.bold())
            .foregroundStyle(blue)
            .buttonStyle(.plain)

            if !allPhotos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 66, height: 76)
                                .clipped()
                                .accessibilityLabel("査定に使用した写真")
                        }

                        ForEach(extraPhotos.indices, id: \.self) { index in
                            Image(uiImage: extraPhotos[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 66, height: 76)
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        extraPhotos.remove(at: index)
                                        persistDraft(savePhotos: true)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white)
                                    }
                                    .accessibilityLabel("追加した写真を削除")
                                }
                        }
                    }
                }

                Button {
                    Task { await savePhotosToLibrary() }
                } label: {
                    Label("写真アプリに保存（\(allPhotos.count)枚）", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .font(.caption.bold())
                .buttonStyle(.plain)
            }

            Divider()

            Text("② 商品名と説明文をコピー")
                .font(.caption.bold())
                .foregroundStyle(green)

            Text(productName.isEmpty ? "商品名がありません" : productName)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                UIPasteboard.general.string = productName
                statusMessage = "商品名をコピーしました"
            } label: {
                Label("商品名をコピー", systemImage: "textformat")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(green, lineWidth: 1))
            }
            .font(.caption.bold())
            .foregroundStyle(green)
            .buttonStyle(.plain)
            .disabled(productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text("出品用の文章（空欄は編集できます）")
                .font(.caption)

            TextEditor(text: $draftBody)
                .frame(height: 180)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                UIPasteboard.general.string = draftBody
                statusMessage = "出品用の文章をコピーしました"
            } label: {
                Label("出品用の文章をコピー", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(green)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .font(.caption.bold())
            .buttonStyle(.plain)

            Button {
                showTextExporter = true
            } label: {
                Label("出品用の文章をテキスト保存", systemImage: "doc.badge.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(green.opacity(0.65), lineWidth: 1)
                    )
            }
            .font(.caption.bold())
            .foregroundStyle(green)
            .buttonStyle(.plain)

            Divider()

            Text("③ 出品先を開く")
                .font(.caption.bold())
                .foregroundStyle(green)

            HStack(spacing: 10) {
                SellSiteButton(title: "メルカリ", systemImage: "shippingbox.fill", urlString: "https://jp.mercari.com/sell")
                SellSiteButton(title: "Yahoo!フリマ", systemImage: "cart.fill", urlString: "https://paypayfleamarket.yahoo.co.jp/sell")
                SellSiteButton(title: "楽天ラクマ", systemImage: "bag.fill", urlString: "https://fril.jp/item/new")
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(green)
            }

            Text("メルカリでは保存した写真を使ってAI出品サポートを利用できます。他の販売サイトでは、必要な項目を記入して文章を貼り付けてください。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: restoreDraft)
        .onChange(of: draftBody) { _ in persistDraft() }
        .onChange(of: selectedPhotos) { items in
            guard !items.isEmpty else { return }
            Task { @MainActor in
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       extraPhotos.count < 9 {
                        extraPhotos.append(image)
                    }
                }
                selectedPhotos = []
                persistDraft(savePhotos: true)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onImage: { photo in
                    if extraPhotos.count < 9 {
                        extraPhotos.append(photo)
                        persistDraft(savePhotos: true)
                    }
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .fileExporter(
            isPresented: $showTextExporter,
            document: ListingTextDocument(text: fullDraft),
            contentType: .plainText,
            defaultFilename: "パシャ査定_出品文"
        ) { result in
            switch result {
            case .success:
                statusMessage = "文章をファイルに保存しました"
            case .failure:
                statusMessage = "文章を保存できませんでした"
            }
        }
    }

    private func restoreDraft() {
        if let saved = ListingDraftStore.load(draftID) {
            checkedPhotos = Set(saved.checkedPhotos)
            let hasMain = ListingDraftStore.photo(id: draftID, index: 0) != nil
            let firstExtraIndex = hasMain ? 1 : 0
            extraPhotos = (0..<min(saved.extraPhotoCount, 9)).compactMap {
                ListingDraftStore.photo(id: draftID, index: firstExtraIndex + $0)
            }
            let previousAutomaticBody = automaticDraftBody(model: modelNumber)
            draftBody = saved.body.isEmpty || saved.body == previousAutomaticBody
                ? defaultDraftBody : saved.body
        } else {
            draftBody = defaultDraftBody
        }
        persistDraft(savePhotos: true)
    }

    private var defaultDraftBody: String {
        automaticDraftBody(model: completeModelNumber)
    }

    private var completeModelNumber: String {
        let original = modelNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty,
              let range = productName.range(of: original, options: .caseInsensitive) else {
            return original
        }
        let suffix = productName[range.upperBound...].prefix { character in
            character.unicodeScalars.allSatisfy { $0.isASCII }
                && (character.isLetter || character.isNumber || character == "-")
        }
        return original + suffix
    }

    private func automaticDraftBody(model: String) -> String {
        [
            "ブランド：\(brand)",
            "型番：\(model)",
            "状態：",
            "動作確認：",
            "付属品：",
            "追記表示："
        ].joined(separator: "\n")
    }

    private func persistDraft(savePhotos: Bool = false) {
        ListingDraftStore.update(
            id: draftID, productName: productName, barcode: barcode,
            brand: brand, modelNumber: modelNumber
        ) { draft in
            draft.body = draftBody
            draft.checkedPhotos = photoChecks.filter { checkedPhotos.contains($0) }
            draft.extraPhotoCount = extraPhotos.count
        }
        if savePhotos {
            ListingDraftStore.savePhotos(id: draftID, main: image, extras: extraPhotos)
        }
    }

    @MainActor
    private func savePhotosToLibrary() async {
        let photos = allPhotos
        guard !photos.isEmpty else { return }

        guard Bundle.main.object(
            forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription"
        ) != nil else {
            statusMessage = "写真の保存設定がありません。アプリの設定を確認してください。"
            return
        }

        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            statusMessage = "写真への保存を許可してください"
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for photo in photos {
                    PHAssetChangeRequest.creationRequestForAsset(from: photo)
                }
            }
            statusMessage = "\(photos.count)枚を写真アプリに保存しました"
        } catch {
            statusMessage = "写真を保存できませんでした"
        }
    }
}

struct SellSiteButton: View {
    let title: String
    let systemImage: String
    let urlString: String

    private let green = Color(
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        red: 129 / 255,
        green: 223 / 255,
        blue: 209 / 255
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
        _ image: UIImage,
        maxEdge: CGFloat = 1600
    ) -> UIImage {
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
                centerCrop(image),
                maxEdge: 1200
            )

        guard let imageData =
                uploadImage.jpegData(
                    compressionQuality: 0.72
                ),
              let focusedImageData =
                focusedImage.jpegData(
                    compressionQuality: 0.65
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
                resizedForVision(image).cgImage else {
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

    // Vision can spend unnecessary time scanning a full-resolution iPhone
    // photo. Keep enough pixels for model numbers and JAN/EAN barcodes.
    private static func resizedForVision(_ image: UIImage) -> UIImage {
        let maxEdge: CGFloat = 2200
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxEdge, size.width > 0, size.height > 0 else {
            return image
        }
        let ratio = maxEdge / longest
        let target = CGSize(width: floor(size.width * ratio),
                            height: floor(size.height * ratio))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
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

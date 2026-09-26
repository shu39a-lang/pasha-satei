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
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 160 : 180)
                .background(Color.black)
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
                            .frame(maxWidth: .infinity)
                            .frame(height: 164)
                            .background(Color(red: 29 / 255, green: 33 / 255, blue: 38 / 255))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "camera.aperture")
                        Text("撮影した写真と商品情報")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color(red: 226 / 255, green: 237 / 255, blue: 249 / 255))
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                                .foregroundStyle(Color(red: 255 / 255, green: 214 / 255, blue: 67 / 255))

                            Spacer()

                            if confidence > 0 {
                                Text("参考 \(confidence)%")
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 255 / 255, green: 220 / 255, blue: 84 / 255))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 104 / 255, green: 78 / 255, blue: 24 / 255).opacity(0.60), in: Capsule())
                                    .overlay(Capsule().stroke(Color(red: 255 / 255, green: 220 / 255, blue: 84 / 255).opacity(0.8), lineWidth: 1))
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
                        LinearGradient(
                            colors: [Color(red: 55 / 255, green: 52 / 255, blue: 43 / 255),
                                     Color(red: 27 / 255, green: 30 / 255, blue: 35 / 255)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(red: 255 / 255, green: 214 / 255, blue: 67 / 255).opacity(0.6), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

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
                            "販売先の価格比較",
                            systemImage: "chart.bar.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(.black)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 255 / 255, green: 244 / 255, blue: 167 / 255),
                                         Color(red: 255 / 255, green: 214 / 255, blue: 67 / 255),
                                         Color(red: 193 / 255, green: 137 / 255, blue: 27 / 255),
                                         Color(red: 255 / 255, green: 222 / 255, blue: 91 / 255)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
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

    private let green = Color(red: 226 / 255, green: 237 / 255, blue: 249 / 255)

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
                    Color(red: 115 / 255, green: 127 / 255, blue: 139 / 255),
                    Color(red: 41 / 255, green: 47 / 255, blue: 55 / 255),
                    Color(red: 80 / 255, green: 90 / 255, blue: 101 / 255)
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
                green.opacity(0.82),
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
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 130)
                            .background(Color(red: 33 / 255, green: 37 / 255, blue: 43 / 255))
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
                        .foregroundStyle(Color(red: 255 / 255, green: 214 / 255, blue: 67 / 255))

                        if !barcode.isEmpty {
                            Text("JAN / EAN: \(barcode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("販売中の相場を比べる")
                        .font(.headline)
                        .foregroundStyle(Color(red: 226 / 255, green: 237 / 255, blue: 249 / 255))
                        .frame(maxWidth: .infinity, alignment: .leading)

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
                            .foregroundStyle(Color(red: 255 / 255, green: 214 / 255, blue: 67 / 255))

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
                        LinearGradient(
                            colors: [Color(red: 112 / 255, green: 84 / 255, blue: 28 / 255),
                                     Color(red: 43 / 255, green: 42 / 255, blue: 38 / 255),
                                     Color(red: 91 / 255, green: 72 / 255, blue: 30 / 255)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                        .stroke(
                            Color(red: 255 / 255, green: 214 / 255, blue: 67 / 255).opacity(0.55),
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

struct LuxurySectionTitle: View {
    let number: String
    let title: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .background(accent, in: RoundedRectangle(cornerRadius: 8))
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.black)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.92), accent, accent.opacity(0.72), accent],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
    private let blue = Color(red: 226 / 255, green: 237 / 255, blue: 249 / 255)
    private let gold = Color(red: 255 / 255, green: 214 / 255, blue: 67 / 255)

    private var allPhotos: [UIImage] {
        (image.map { [$0] } ?? []) + extraPhotos
    }

    private var fullDraft: String {
        draftBody
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("写真と文章を整えて出品")
            }
            .font(.title3.bold())
            .foregroundStyle(gold)

            Text("入力した文章・価格・追加写真は、このiPhoneに自動保存されます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            LuxurySectionTitle(number: "01", title: "写真を確認して保存", accent: blue)

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
            .padding(8)
            .background(Color(red: 59 / 255, green: 66 / 255, blue: 73 / 255).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12))

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
                        .foregroundStyle(Color(red: 20 / 255, green: 27 / 255, blue: 34 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .font(.caption.bold())
                .buttonStyle(.plain)
            }

            Divider()

            LuxurySectionTitle(number: "02", title: "商品名と説明文をコピー", accent: gold)

            Text(productName.isEmpty ? "商品名がありません" : productName)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    LinearGradient(colors: [gold.opacity(0.24), gold.opacity(0.07)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(gold.opacity(0.5), lineWidth: 1))
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
                .background(Color(red: 60 / 255, green: 66 / 255, blue: 73 / 255).opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(blue.opacity(0.5), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                UIPasteboard.general.string = draftBody
                statusMessage = "出品用の文章をコピーしました"
            } label: {
                Label("出品用の文章をコピー", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(gold)
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

            LuxurySectionTitle(number: "03", title: "出品先を開く", accent: green)

            HStack(spacing: 10) {
                SellSiteButton(title: "メルカリ", systemImage: "shippingbox.fill", urlString: "https://jp.mercari.com/sell")
                SellSiteButton(title: "Yahoo!フリマ", systemImage: "cart.fill", urlString: "https://paypayfleamarket.yahoo.co.jp/sell")
                SellSiteButton(title: "楽天ラクマ", systemImage: "bag.fill", urlString: "https://fril.jp/item/new")
            }
            .padding(8)
            .background(Color(red: 25 / 255, green: 52 / 255, blue: 51 / 255).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))

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

    private var green: Color {
        if title.contains("メルカリ") { return Color(red: 255 / 255, green: 214 / 255, blue: 67 / 255) }
        if title.contains("Yahoo") { return Color(red: 226 / 255, green: 237 / 255, blue: 249 / 255) }
        return Color(red: 129 / 255, green: 223 / 255, blue: 209 / 255)
    }

    private var metalSurface: Color {
        if title.contains("メルカリ") {
            return Color(red: 60 / 255, green: 47 / 255, blue: 31 / 255)
        }
        if title.contains("Yahoo") {
            return Color(red: 54 / 255, green: 62 / 255, blue: 72 / 255)
        }
        return Color(red: 26 / 255, green: 58 / 255, blue: 55 / 255)
    }

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
                        .tint(.black)
                }
            }
            .padding(10)
            .foregroundStyle(.black)
            .background(
                LinearGradient(colors: [Color.white.opacity(0.92), green, green.opacity(0.72), green],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 10)
            )

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
                                    selectedBand == .low,
                                accent: green
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
                                    selectedBand == .median,
                                accent: green
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
                                    selectedBand == .high,
                                accent: green
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
                    metalSurface,
                    Color(red: 26 / 255, green: 28 / 255, blue: 32 / 255),
                    metalSurface.opacity(0.8)
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
                green.opacity(0.55),
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
        .overlay(alignment: .top) {
            Capsule().fill(green).frame(width: 90, height: 3).padding(.top, 2)
        }
    }
}

struct PriceStat: View {
    let title: String
    let value: Int
    let isSelected: Bool
    let accent: Color

    private var green: Color { accent }

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

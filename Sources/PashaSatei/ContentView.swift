import SwiftUI
import PhotosUI
import UIKit
import Vision

enum AppRoute: Hashable {
    case result
    case compare
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
    let confidence: Int?
    let evidence: [String]?
    let candidates: [String]?
    let error: String?
}

struct LocalRecognitionResult {
    let text: String
    let barcode: String
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

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                selectedPhoto: $selectedPhoto,
                showCamera: $showCamera
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .result:
                    ResultView(
                        image: selectedImage,
                        productName: $productName,
                        detectedBarcode: detectedBarcode,
                        recognitionSource: recognitionSource,
                        confidence: confidence,
                        brand: brand,
                        category: category,
                        modelNumber: modelNumber,
                        evidence: evidence,
                        candidates: candidates,
                        isRecognizing: isRecognizing,
                        onCompare: {
                            path.append(.compare)
                        }
                    )

                case .compare:
                    CompareView(
                        productName: productName,
                        barcode: detectedBarcode
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(
    isPresented: $showCamera,
    onDismiss: {
        guard let image = selectedImage else {
            return
        }

        Task {
            await recognize(image: image)
            path.append(.result)
        }
    }
) {
    CameraPicker(
        image: $selectedImage,
        onFinish: {
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
                await recognize(image: image)
                path.append(.result)
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

        async let localTask =
            LocalProductRecognizer.recognize(image: image)

        async let geminiTask =
            GeminiProductAPI.analyze(image: image)

        let local = await localTask
        let gemini = await geminiTask

        detectedBarcode = local.barcode

        if let gemini, gemini.ok {
            let name =
                gemini.displayName?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

            productName = name

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

            confidence =
                gemini.confidence ?? 0

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

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        HStack(spacing: 4) {
                            Text("パシャ")
                                .font(
                                    .system(
                                        size: 38,
                                        weight: .black
                                    )
                                )

                            Text("査定")
                                .font(
                                    .system(
                                        size: 38,
                                        weight: .black
                                    )
                                )
                                .foregroundStyle(green)
                        }

                        Text(
                            "どこで売れば一番手取りが多いか比較"
                        )
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(green.opacity(0.12))
                                .frame(
                                    width: 120,
                                    height: 120
                                )

                            Image(
                                systemName:
                                    "viewfinder.circle.fill"
                            )
                            .font(.system(size: 72))
                            .foregroundStyle(green)
                        }

                        Text("撮るだけで商品をAI判定")
                            .font(.title2.bold())

                        Text(
                            "バーコードが無くても、写真全体からブランド・商品名・型番・容量などを判断します。"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                        HStack(spacing: 8) {
                            FeatureBadge(
                                text: "AI画像認識",
                                icon: "sparkles"
                            )

                            FeatureBadge(
                                text: "JAN対応",
                                icon: "barcode.viewfinder"
                            )

                            FeatureBadge(
                                text: "価格比較",
                                icon: "chart.bar.fill"
                            )
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(
                                    red: 9 / 255,
                                    green: 38 / 255,
                                    blue: 28 / 255
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
                            cornerRadius: 26
                        )
                        .stroke(
                            green.opacity(0.35),
                            lineWidth: 1
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 26
                        )
                    )

                    HStack(spacing: 10) {
                        StepCard(
                            number: "1",
                            title: "撮影",
                            icon: "camera.fill"
                        )

                        StepCard(
                            number: "2",
                            title: "AI特定",
                            icon: "sparkles"
                        )

                        StepCard(
                            number: "3",
                            title: "価格比較",
                            icon: "chart.bar.fill"
                        )
                    }

                    Button {
                        showCamera = true
                    } label: {
                        Label(
                            "カメラで撮影",
                            systemImage: "camera.fill"
                        )
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(green)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                    )

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            "写真を選ぶ",
                            systemImage: "photo.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Color(
                                red: 28 / 255,
                                green: 28 / 255,
                                blue: 30 / 255
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 18
                            )
                            .stroke(
                                Color.white.opacity(0.15),
                                lineWidth: 1
                            )
                        )
                    }
                    .foregroundStyle(.white)
                }
                .padding(18)
            }
        }
        .navigationBarHidden(true)
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

    @Binding var productName: String

    let detectedBarcode: String
    let recognitionSource: String
    let confidence: Int
    let brand: String
    let category: String
    let modelNumber: String
    let evidence: [String]
    let candidates: [String]
    let isRecognizing: Bool

    let onCompare: () -> Void

    private let green = Color(
        red: 39 / 255,
        green: 211 / 255,
        blue: 119 / 255
    )

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

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
                        VStack(spacing: 10) {
                            ProgressView()
                                .tint(green)

                            Text(
                                "AIが商品を判定しています…"
                            )
                            .font(.headline)
                        }
                        .padding()
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        HStack {
                            Image(
                                systemName:
                                    "sparkles"
                            )
                            .foregroundStyle(green)

                            Text("AIの商品判定")
                                .font(.headline)

                            Spacer()

                            if confidence > 0 {
                                Text(
                                    "参考 \(confidence)%"
                                )
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

                        Text(
                            "認識が違う場合は商品名を直接修正できます。"
                        )
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

                    if !candidates.isEmpty {
                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {
                            Text("その他の候補")
                                .font(.headline)

                            ForEach(
                                candidates.prefix(3),
                                id: \.self
                            ) { candidate in
                                Button {
                                    productName =
                                        candidate
                                } label: {
                                    HStack {
                                        Text(candidate)

                                        Spacer()

                                        Image(
                                            systemName:
                                                "chevron.right"
                                        )
                                    }
                                    .padding(12)
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
                        }
                    }

                    Button(action: onCompare) {
                        Label(
                            "販売先と手取り額を比較",
                            systemImage:
                                "chart.bar.fill"
                        )
                        .font(.headline)
                        .frame(
                            maxWidth: .infinity
                        )
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
                }
                .padding(16)
            }
        }
        .navigationTitle("商品確認")
        .navigationBarTitleDisplayMode(.inline)
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

struct CompareView: View {
    let productName: String
    let barcode: String

    @State private var salePrices:
        [String: String] = [:]

    @State private var shippingCosts:
        [String: String] = [:]

    @Environment(\.openURL)
    private var openURL

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    Text(
                        productName.isEmpty
                        ? "商品"
                        : productName
                    )
                    .font(.title2.bold())

                    if !barcode.isEmpty {
                        Text(
                            "JAN / EAN: \(barcode)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Text(
                        "各サービスの相場を確認して、販売価格と送料を入力すると予想手取り額を計算できます。"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    ForEach(marketplaces) {
                        market in

                        MarketplaceCard(
                            market: market,
                            salePrice: binding(
                                for: market.name,
                                dictionary:
                                    $salePrices
                            ),
                            shippingCost: binding(
                                for: market.name,
                                dictionary:
                                    $shippingCosts
                            ),
                            onSearch: {
                                openMarket(
                                    market: market
                                )
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("販売先比較")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(
        for key: String,
        dictionary:
            Binding<[String: String]>
    ) -> Binding<String> {
        Binding(
            get: {
                dictionary.wrappedValue[key]
                ?? ""
            },
            set: {
                dictionary.wrappedValue[key]
                = $0
            }
        )
    }

    private func openMarket(
        market: Marketplace
    ) {
        let keyword =
            productName
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !keyword.isEmpty else {
            return
        }

        let encoded =
            keyword.addingPercentEncoding(
                withAllowedCharacters:
                    .urlQueryAllowed
            ) ?? ""

        if let url =
            URL(
                string:
                    market.searchBaseURL
                    + encoded
            ) {
            openURL(url)
        }
    }
}

struct MarketplaceCard: View {
    let market: Marketplace

    @Binding var salePrice: String
    @Binding var shippingCost: String

    let onSearch: () -> Void

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

                Text(
                    "手数料 約\(Int(market.feeRate * 100))%"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(
                action: onSearch
            ) {
                Label(
                    "\(market.name)で相場を見る",
                    systemImage:
                        "arrow.up.right.square"
                )
                .font(.headline)
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
                .foregroundStyle(.green)
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
}

enum GeminiProductAPI {
    private static let endpoint =
        "https://pasha-satei-vision-api-500716860725.asia-northeast1.run.app"

    static func analyze(
        image: UIImage
    ) async -> GeminiProductResponse? {

        guard let url =
                URL(string: endpoint),
              let imageData =
                image.jpegData(
                    compressionQuality: 0.78
                ) else {
            return nil
        }

        let body: [String: Any] = [
            "imageBase64":
                imageData
                    .base64EncodedString()
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
        request.timeoutInterval = 45

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

            request.recognitionLevel =
                .accurate

            request.usesLanguageCorrection =
                true

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

    @Binding var image: UIImage?
    let onFinish: () -> Void

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
            parent.image =
                info[
                    .originalImage
                ] as? UIImage

            parent.onFinish()
        }

        func imagePickerControllerDidCancel(
            _ picker:
                UIImagePickerController
        ) {
            parent.onFinish()
        }
    }
}

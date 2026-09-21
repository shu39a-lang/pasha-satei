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

struct ContentView: View {
    @State private var path: [AppRoute] = []
    @State private var selectedImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false

    @State private var productName = ""
    @State private var detectedText = ""
    @State private var detectedBarcode = ""
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
                        detectedText: detectedText,
                        detectedBarcode: detectedBarcode,
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $selectedImage) {
                showCamera = false

                guard let image = selectedImage else {
                    return
                }

                Task {
                    await recognize(image: image)
                    path.append(.result)
                }
            }
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
        detectedText = ""
        detectedBarcode = ""

        let result = await ProductRecognizer.recognize(image: image)

        detectedText = result.text
        detectedBarcode = result.barcode
        productName = result.productCandidate

        isRecognizing = false
    }
}

struct HomeView: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var showCamera: Bool

    private let green = Color(
        red: 32 / 255,
        green: 177 / 255,
        blue: 90 / 255
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {

                VStack(alignment: .leading, spacing: 5) {
                    Text("パシャ査定")
                        .font(.system(size: 34, weight: .bold))

                    Text("どこで売れば一番手取りが多いか比較")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(green)

                    Text("売りたい商品を撮影")
                        .font(.title3.bold())

                    Text(
                        "商品名・型番・バーコードが見えるように撮影すると、商品を特定しやすくなります。"
                    )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22))

                Button {
                    showCamera = true
                } label: {
                    Label(
                        "カメラで撮影",
                        systemImage: "camera.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(green)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images
                ) {
                    Label(
                        "写真を選ぶ",
                        systemImage: "photo"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                Color.gray.opacity(0.3),
                                lineWidth: 1.5
                            )
                    )
                }
                .foregroundStyle(.primary)
            }
            .padding(16)
        }
        .navigationBarHidden(true)
    }
}

struct ResultView: View {
    let image: UIImage?

    @Binding var productName: String

    let detectedText: String
    let detectedBarcode: String
    let isRecognizing: Bool

    let onCompare: () -> Void

    private let green = Color(
        red: 32 / 255,
        green: 177 / 255,
        blue: 90 / 255
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 230)
                        .background(Color.black)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 18)
                        )
                }

                if isRecognizing {
                    ProgressView(
                        "商品情報を読み取っています…"
                    )
                    .padding()
                }

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text("商品名・型番")
                        .font(.headline)

                    TextField(
                        "商品名または型番",
                        text: $productName
                    )
                    .textFieldStyle(.roundedBorder)

                    Text(
                        "認識結果が違う場合は直接修正できます。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !detectedBarcode.isEmpty {
                    InfoRow(
                        title: "バーコード",
                        value: detectedBarcode
                    )
                }

                if !detectedText.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text("写真から読み取った文字")
                            .font(.headline)

                        Text(detectedText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .background(
                        Color(.secondarySystemBackground)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14)
                    )
                }

                Button(action: onCompare) {
                    Label(
                        "販売先と手取り額を比較",
                        systemImage: "chart.bar.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(green)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .navigationTitle("商品確認")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)
            }

            Spacer()
        }
        .padding()
        .background(
            Color(.secondarySystemBackground)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 14)
        )
    }
}

struct CompareView: View {
    let productName: String
    let barcode: String

    @State private var salePrices: [String: String] = [:]
    @State private var shippingCosts: [String: String] = [:]

    @Environment(\.openURL) private var openURL

    private let green = Color(
        red: 32 / 255,
        green: 177 / 255,
        blue: 90 / 255
    )

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(productName.isEmpty ? "商品" : productName)
                        .font(.title2.bold())

                    if !barcode.isEmpty {
                        Text("JAN/EAN: \(barcode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(
                    "各サービスの販売相場を確認し、想定販売価格と送料を入力すると手取り額を自動計算します。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                ForEach(marketplaces) { market in
                    MarketplaceCard(
                        market: market,
                        productName: productName,
                        salePrice: binding(
                            for: market.name,
                            dictionary: $salePrices
                        ),
                        shippingCost: binding(
                            for: market.name,
                            dictionary: $shippingCosts
                        ),
                        onSearch: {
                            openMarket(
                                market: market
                            )
                        }
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    Text("買取店でも比較")
                        .font(.title3.bold())

                    Button {
                        let query =
                            productName.isEmpty
                            ? "買取店"
                            : "\(productName) 買取"

                        let encoded =
                            query.addingPercentEncoding(
                                withAllowedCharacters:
                                    .urlQueryAllowed
                            ) ?? ""

                        if let url = URL(
                            string:
                            "https://www.google.com/search?q=\(encoded)"
                        ) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(
                                systemName:
                                    "building.2.fill"
                            )

                            Text(
                                "買取店の査定価格を調べる"
                            )
                                .font(.headline)

                            Spacer()

                            Image(
                                systemName:
                                    "arrow.up.right.square"
                            )
                        }
                        .padding()
                        .foregroundStyle(.white)
                        .background(green)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 14
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
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
            productName.trimmingCharacters(
                in: .whitespacesAndNewlines
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
    let productName: String

    @Binding var salePrice: String
    @Binding var shippingCost: String

    let onSearch: () -> Void

    private var salePriceValue: Double {
        Double(
            salePrice.replacingOccurrences(
                of: ",",
                with: ""
            )
        ) ?? 0
    }

    private var shippingValue: Double {
        Double(
            shippingCost.replacingOccurrences(
                of: ",",
                with: ""
            )
        ) ?? 0
    }

    private var fee: Double {
        salePriceValue * market.feeRate
    }

    private var netAmount: Double {
        max(
            0,
            salePriceValue - fee - shippingValue
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

            Button(action: onSearch) {
                HStack {
                    Image(
                        systemName:
                            "magnifyingglass"
                    )

                    Text(
                        "\(market.name)で相場を見る"
                    )

                    Spacer()

                    Image(
                        systemName:
                            "arrow.up.right.square"
                    )
                }
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
                .multilineTextAlignment(.trailing)
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
                .multilineTextAlignment(.trailing)
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
                .foregroundStyle(
                    netAmount > 0
                    ? .green
                    : .primary
                )
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemBackground)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 18)
        )
    }
}

struct RecognitionResult {
    let text: String
    let barcode: String
    let productCandidate: String
}

enum ProductRecognizer {

    static func recognize(
        image: UIImage
    ) async -> RecognitionResult {

        guard let cgImage = image.cgImage else {
            return RecognitionResult(
                text: "",
                barcode: "",
                productCandidate: ""
            )
        }

        async let textResult =
            recognizeText(cgImage)

        async let barcodeResult =
            recognizeBarcode(cgImage)

        let text = await textResult
        let barcode = await barcodeResult

        let candidate =
            makeProductCandidate(
                from: text
            )

        return RecognitionResult(
            text: text,
            barcode: barcode,
            productCandidate: candidate
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
                        as? [VNRecognizedTextObservation]
                        ?? []

                    let lines =
                        observations.compactMap {
                            $0.topCandidates(1)
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
            ).async {
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
                        as? [VNBarcodeObservation]
                        ?? []

                    let barcode =
                        observations
                        .compactMap {
                            $0.payloadStringValue
                        }
                        .first
                        ?? ""

                    continuation.resume(
                        returning: barcode
                    )
                }

            let handler =
                VNImageRequestHandler(
                    cgImage: cgImage
                )

            DispatchQueue.global(
                qos: .userInitiated
            ).async {
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

    private static func makeProductCandidate(
        from text: String
    ) -> String {

        let lines =
            text.components(
                separatedBy: .newlines
            )
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter {
                !$0.isEmpty
            }

        guard !lines.isEmpty else {
            return ""
        }

        let modelLines =
            lines.filter {
                line in

                let hasLetter =
                    line.rangeOfCharacter(
                        from: .letters
                    ) != nil

                let hasNumber =
                    line.rangeOfCharacter(
                        from: .decimalDigits
                    ) != nil

                return hasLetter
                    && hasNumber
                    && line.count <= 40
            }

        if let model =
            modelLines.first {

            if let brand =
                lines.first,
               brand != model {

                return "\(brand) \(model)"
            }

            return model
        }

        return lines
            .prefix(2)
            .joined(separator: " ")
    }
}

struct CameraPicker:
    UIViewControllerRepresentable {

    @Binding var image: UIImage?

    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(
        context: Context
    ) -> UIImagePickerController {

        let picker =
            UIImagePickerController()

        picker.sourceType =
            UIImagePickerController
                .isSourceTypeAvailable(.camera)
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

        init(_ parent: CameraPicker) {
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
                info[.originalImage]
                as? UIImage

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

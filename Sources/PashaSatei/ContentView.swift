import SwiftUI
import PhotosUI
import UIKit

enum AppRoute: Hashable {
    case result
    case sell
}

struct ContentView: View {
    @State private var path: [AppRoute] = []
    @State private var selectedImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var productName = ""

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                selectedPhoto: $selectedPhoto,
                showCamera: $showCamera,
                onSample: {
                    selectedImage = nil
                    productName = "ワイヤレスヘッドホン"
                    path.append(.result)
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .result:
                    ResultView(
                        image: selectedImage,
                        productName: $productName,
                        onSell: {
                            path.append(.sell)
                        }
                    )

                case .sell:
                    SellOptionsView(productName: productName)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $selectedImage) {
                showCamera = false

                if selectedImage != nil {
                    productName = ""
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

                await MainActor.run {
                    selectedImage = image
                    productName = ""
                    path.append(.result)
                }
            }
        }
    }
}

struct HomeView: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var showCamera: Bool

    let onSample: () -> Void

    private let green = Color(
        red: 32 / 255,
        green: 177 / 255,
        blue: 90 / 255
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("パシャ査定")
                            .font(.system(size: 34, weight: .bold))

                        Text("撮って、調べて、売る場所まで比較")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(green)

                    Text("商品の写真を撮影")
                        .font(.title3.bold())

                    Text("写真を撮るか、iPhoneに保存されている写真を選んでください。")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .padding(.horizontal, 15)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))

                Button {
                    showCamera = true
                } label: {
                    Label("カメラで撮影", systemImage: "camera.fill")
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
                    Label("写真を選ぶ", systemImage: "photo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.35), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Button("サンプルで試す", action: onSample)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            .padding(16)
        }
        .background(Color.white)
        .navigationBarHidden(true)
    }
}

struct ResultView: View {
    let image: UIImage?

    @Binding var productName: String

    let onSell: () -> Void

    @Environment(\.openURL) private var openURL

    private let green = Color(
        red: 32 / 255,
        green: 177 / 255,
        blue: 90 / 255
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {

                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                    } else {
                        ZStack {
                            Color(.secondarySystemBackground)

                            Image(systemName: "shippingbox")
                                .font(.system(size: 80))
                                .foregroundStyle(green)
                        }
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 8) {
                    Text("商品名")
                        .font(.headline)

                    TextField(
                        "例：SONY WH-1000XM5",
                        text: $productName
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .textInputAutocapitalization(.never)

                    Text("商品名や型番を入力すると、実際の販売サイトを検索できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {

                    Text("販売価格を調べる")
                        .font(.title3.bold())

                    SearchButton(
                        title: "Amazonで新品価格を見る",
                        subtitle: "Amazon.co.jp",
                        icon: "cart.fill",
                        color: green
                    ) {
                        openSearch(
                            base: "https://www.amazon.co.jp/s?k=",
                            keyword: productName
                        )
                    }

                    SearchButton(
                        title: "楽天市場で価格を見る",
                        subtitle: "楽天市場",
                        icon: "bag.fill",
                        color: green
                    ) {
                        openSearch(
                            base: "https://search.rakuten.co.jp/search/mall/",
                            keyword: productName
                        )
                    }

                    SearchButton(
                        title: "Yahoo!ショッピングで見る",
                        subtitle: "Yahoo!ショッピング",
                        icon: "cart",
                        color: green
                    ) {
                        openSearch(
                            base: "https://shopping.yahoo.co.jp/search?p=",
                            keyword: productName
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {

                    Text("中古相場を調べる")
                        .font(.title3.bold())

                    SearchButton(
                        title: "メルカリで中古価格を見る",
                        subtitle: "実際の出品価格を確認",
                        icon: "tag.fill",
                        color: green
                    ) {
                        openSearch(
                            base: "https://jp.mercari.com/search?keyword=",
                            keyword: productName
                        )
                    }
                }

                Button(action: onSell) {
                    HStack {
                        Image(systemName: "yensign.circle.fill")

                        Text("売る場所を比較する")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Text("※ 表示価格を固定せず、各サービスの現在の検索結果を確認する方式に変更しました。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .navigationTitle("査定・価格比較")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openSearch(base: String, keyword: String) {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !word.isEmpty else {
            return
        }

        guard let encoded =
                word.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ),
              let url = URL(string: base + encoded) else {
            return
        }

        openURL(url)
    }
}

struct SearchButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {

                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct SellOptionsView: View {
    let productName: String

    @Environment(\.openURL) private var openURL

    private let green = Color(
        red: 32 / 255,
        green: 177 / 255,
        blue: 90 / 255
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                Text("売却先を探す")
                    .font(.title2.bold())

                Text(
                    productName.isEmpty
                    ? "商品"
                    : productName
                )
                .font(.headline)
                .foregroundStyle(.secondary)

                SearchButton(
                    title: "メルカリで売る",
                    subtitle: "同じ商品の出品を確認",
                    icon: "shippingbox.fill",
                    color: green
                ) {
                    openProductSearch(
                        "https://jp.mercari.com/search?keyword="
                    )
                }

                SearchButton(
                    title: "Yahoo!オークションで調べる",
                    subtitle: "落札・出品候補を確認",
                    icon: "hammer.fill",
                    color: green
                ) {
                    openProductSearch(
                        "https://auctions.yahoo.co.jp/search/search?p="
                    )
                }

                SearchButton(
                    title: "近くの買取店を探す",
                    subtitle: "Appleマップで買取店を検索",
                    icon: "map.fill",
                    color: green
                ) {
                    let query = productName.isEmpty
                        ? "買取店"
                        : "\(productName) 買取店"

                    let encoded =
                        query.addingPercentEncoding(
                            withAllowedCharacters: .urlQueryAllowed
                        ) ?? ""

                    if let url =
                        URL(
                            string:
                            "http://maps.apple.com/?q=\(encoded)"
                        ) {
                        openURL(url)
                    }
                }

                Text("今後ここに、買取店ごとの査定額比較や現在地周辺の店舗一覧を追加していきます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .navigationTitle("売却先を比較")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openProductSearch(_ base: String) {
        let word =
            productName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !word.isEmpty,
              let encoded =
                word.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ),
              let url = URL(string: base + encoded) else {
            return
        }

        openURL(url)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(
        context: Context
    ) -> UIImagePickerController {

        let picker = UIImagePickerController()

        picker.sourceType =
            UIImagePickerController
                .isSourceTypeAvailable(.camera)
            ? .camera
            : .photoLibrary

        picker.delegate = context.coordinator

        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
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
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info:
                [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image =
                info[.originalImage] as? UIImage

            parent.onFinish()
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            parent.onFinish()
        }
    }
}

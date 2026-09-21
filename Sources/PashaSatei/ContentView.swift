import SwiftUI
import PhotosUI
import UIKit

struct ProductEstimate {
    let name: String
    let detail: String
    let newPrice: String
    let usedPrice: String
    let buyPrice: String
    let confidence: Int
}

private let sampleEstimate = ProductEstimate(
    name: "ワイヤレスヘッドホン ZX-500",
    detail: "ヘッドホン / サンプル商品",
    newPrice: "18,800円",
    usedPrice: "11,500円",
    buyPrice: "7,000〜9,000円",
    confidence: 92
)

enum AppRoute: Hashable {
    case result
    case sell
}

struct ContentView: View {
    @State private var path: [AppRoute] = []
    @State private var selectedImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                selectedImage: $selectedImage,
                selectedPhoto: $selectedPhoto,
                showCamera: $showCamera,
                onSample: {
                    selectedImage = nil
                    path.append(.result)
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .result:
                    ResultView(
                        image: selectedImage,
                        estimate: sampleEstimate,
                        onSell: { path.append(.sell) }
                    )
                case .sell:
                    SellOptionsView()
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $selectedImage) {
                showCamera = false
                if selectedImage != nil {
                    path.append(.result)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }

                await MainActor.run {
                    selectedImage = image
                    path.append(.result)
                }
            }
        }
    }
}

struct HomeView: View {
    @Binding var selectedImage: UIImage?
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var showCamera: Bool

    let onSample: () -> Void

    private let green = Color(red: 32/255, green: 177/255, blue: 90/255)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("パシャ査定")
                            .font(.system(size: 34, weight: .bold))

                        Text("撮るだけで、モノの価値がわかる")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "bell")
                        .font(.title2)
                        .padding(.top, 4)
                }

                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(green)

                    Text("商品の写真を1枚撮るだけ")
                        .font(.title3.bold())

                    Text("販売相場・推定買取価格・売却先候補を\nわかりやすく表示します")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
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

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
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
                    .padding(.vertical, 5)

                VStack(alignment: .leading, spacing: 8) {
                    Label("現在は試作版です", systemImage: "info.circle")
                        .font(.headline)

                    Text("第1版では画面と操作の確認を行います。商品認識・価格情報・店舗情報は次段階で実データに接続します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(Color.white)
        .navigationBarHidden(true)
    }
}

struct ResultView: View {
    let image: UIImage?
    let estimate: ProductEstimate
    let onSell: () -> Void

    @State private var condition = "良品"

    private let green = Color(red: 32/255, green: 177/255, blue: 90/255)

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

                            Image(systemName: "headphones")
                                .font(.system(size: 86))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(estimate.name)
                            .font(.title2.bold())

                        Text(estimate.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("認識精度")
                            .font(.caption)

                        Text("\(estimate.confidence)%")
                            .font(.title3.bold())
                            .foregroundStyle(green)
                    }
                    .frame(width: 82, height: 82)
                    .background(green.opacity(0.10))
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("商品の状態")
                        .font(.headline)

                    HStack(spacing: 8) {
                        ForEach(["美品", "良品", "使用感あり"], id: \.self) { item in
                            Button(item) {
                                condition = item
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(condition == item ? .white : .primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(condition == item ? green : Color.gray.opacity(0.28))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PriceRow(title: "新品販売価格", price: estimate.newPrice, icon: "cart")
                PriceRow(title: "中古販売価格", price: estimate.usedPrice, icon: "tag")
                PriceRow(title: "推定買取価格", price: estimate.buyPrice, icon: "yensign.circle")

                Button(action: onSell) {
                    Text("売る場所を比較する")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(green)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Text("※ 現在の価格は試作版のサンプル表示です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("査定結果")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PriceRow: View {
    let title: String
    let price: String
    let icon: String

    private let green = Color(red: 32/255, green: 177/255, blue: 90/255)

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 42, height: 42)
                .background(green.opacity(0.10))
                .foregroundStyle(green)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(price)
                    .font(.title2.bold())
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SellOptionsView: View {
    private let green = Color(red: 32/255, green: 177/255, blue: 90/255)

    private let shops = [
        ("リユース館 八王子店", "徒歩12分", "storefront"),
        ("買取センター 南大沢店", "車で8分", "car"),
        ("中古買取ショップ 立川店", "営業中", "checkmark.circle")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("販売する")
                    .font(.title2.bold())

                HStack(spacing: 8) {
                    SellCard(title: "フリマ", subtitle: "高く売れやすい", icon: "shippingbox")
                    SellCard(title: "オークション", subtitle: "入札で販売", icon: "hammer")
                    SellCard(title: "中古市場", subtitle: "手軽に出品", icon: "storefront")
                }

                Text("買い取ってくれるお店")
                    .font(.title2.bold())
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(green)

                    Text("周辺店舗マップ")
                        .font(.headline)

                    Text("実店舗検索は次段階で接続します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                ForEach(Array(shops.enumerated()), id: \.offset) { _, shop in
                    HStack(spacing: 14) {
                        Image(systemName: shop.2)
                            .frame(width: 42, height: 42)
                            .background(green.opacity(0.10))
                            .foregroundStyle(green)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(shop.0)
                                .font(.headline)

                            Text(shop.1)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(15)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text("※ 店舗名・距離はサンプル表示です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .navigationTitle("売る場所を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SellCard: View {
    let title: String
    let subtitle: String
    let icon: String

    private let green = Color(red: 32/255, green: 177/255, blue: 90/255)

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(green)

            Text(title)
                .font(.subheadline.bold())

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish()
        }
    }
}

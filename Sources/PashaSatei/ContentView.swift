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

struct ContentView: View {
    @State private var path: [AppRoute] = []
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                selectedImage: $selectedImage,
                selectedPhoto: $selectedPhoto,
                showCamera: $showCamera,
                onAnalyze: { path.append(.result) }
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .result:
                    ResultView(image: selectedImage, estimate: sampleEstimate) {
                        path.append(.sell)
                    }
                case .sell:
                    SellOptionsView()
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $selectedImage) {
                showCamera = false
                if selectedImage != nil { path.append(.result) }
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

enum AppRoute: Hashable { case result, sell }

struct HomeView: View {
    @Binding var selectedImage: UIImage?
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var showCamera: Bool
    let onAnalyze: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("パシャ査定")
                            .font(.system(size: 34, weight: .bold))
                        Text("撮るだけで、モノの価値がわかる")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "bell")
                        .font(.title2)
                }
                .padding(.top, 8)

                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.green)
                    Text("商品の写真を1枚撮るだけ")
                        .font(.title3.bold())
                    Text("販売相場・推定買取価格・売却先候補を\nわかりやすく表示します")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))

                Button {
                    showCamera = true
                } label: {
                    Label("カメラで撮影", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("写真を選ぶ", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .font(.headline)
                }
                .buttonStyle(.bordered)

                Button("サンプルで試す") {
                    selectedImage = nil
                    onAnalyze()
                }
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Label("現在は試作版です", systemImage: "info.circle")
                        .font(.headline)
                    Text("第1版では画面と操作の確認を行います。商品認識・価格情報・店舗情報は次段階で実データに接続します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .navigationBarHidden(true)
    }
}

struct ResultView: View {
    let image: UIImage?
    let estimate: ProductEstimate
    let onSell: () -> Void
    @State private var condition = "良品"

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground))
                            Image(systemName: "headphones")
                                .font(.system(size: 86))
                        }
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(estimate.name).font(.title2.bold())
                        Text(estimate.detail).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack {
                        Text("認識精度").font(.caption)
                        Text("\(estimate.confidence)%").font(.title3.bold()).foregroundStyle(.green)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.12), in: Circle())
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("商品の状態").font(.headline)
                    HStack {
                        ForEach(["美品", "良品", "使用感あり"], id: \.self) { item in
                            Button(item) { condition = item }
                                .buttonStyle(.borderedProminent)
                                .tint(condition == item ? .green : .gray.opacity(0.35))
                        }
                    }
                }

                PriceRow(title: "新品販売価格", price: estimate.newPrice, icon: "cart")
                PriceRow(title: "中古販売価格", price: estimate.usedPrice, icon: "tag")
                PriceRow(title: "推定買取価格", price: estimate.buyPrice, icon: "yensign.circle")

                Button(action: onSell) {
                    Text("売る場所を比較する")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Text("※ 現在の価格は試作版のサンプル表示です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("査定結果")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PriceRow: View {
    let title: String
    let price: String
    let icon: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 42, height: 42)
                .background(Color.green.opacity(0.12), in: Circle())
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(price).font(.title2.bold())
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SellOptionsView: View {
    let shops = [
        ("リユース館 八王子店", "徒歩12分", "storefront"),
        ("買取センター 南大沢店", "車で8分", "car"),
        ("中古買取ショップ 立川店", "営業中", "checkmark.circle")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("販売する").font(.title2.bold())
                HStack(spacing: 12) {
                    SellCard(title: "フリマ", subtitle: "高く売れやすい", icon: "shippingbox")
                    SellCard(title: "オークション", subtitle: "入札で販売", icon: "hammer")
                    SellCard(title: "中古市場", subtitle: "手軽に出品", icon: "storefront")
                }

                Text("買い取ってくれるお店").font(.title2.bold())
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.green.opacity(0.10))
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "map.fill").font(.system(size: 42)).foregroundStyle(.green)
                            Text("周辺店舗マップ")
                            Text("実店舗検索は次段階で接続します")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                ForEach(Array(shops.enumerated()), id: \.offset) { _, shop in
                    HStack(spacing: 14) {
                        Image(systemName: shop.2)
                            .frame(width: 42, height: 42)
                            .background(Color.green.opacity(0.12), in: Circle())
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shop.0).font(.headline)
                            Text(shop.1).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                }

                Text("※ 店舗名・距離はサンプル表示です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("売る場所を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SellCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.green)
            Text(title).font(.subheadline.bold())
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish()
        }
    }
}

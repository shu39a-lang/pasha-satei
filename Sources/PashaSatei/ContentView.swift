// パシャ査定：近い候補の選択・確認・最初の判定へ戻す修正
// 対象: Sources/PashaSatei/ContentView.swift

// 1) ResultView の @Binding 群の直後に追加
@State private var originalProductName = ""
@State private var originalDetectedBarcode = ""
@State private var originalRecognitionSource = ""
@State private var originalConfidence = 0
@State private var originalBrand = ""
@State private var originalCategory = ""
@State private var originalModelNumber = ""
@State private var originalEvidence: [String] = []
@State private var didCaptureOriginal = false

// 2) ResultView の一番外側 ZStack の末尾（navigationTitle の前）に追加
.onAppear {
    guard !didCaptureOriginal else { return }
    originalProductName = productName
    originalDetectedBarcode = detectedBarcode
    originalRecognitionSource = recognitionSource
    originalConfidence = confidence
    originalBrand = brand
    originalCategory = category
    originalModelNumber = modelNumber
    originalEvidence = evidence
    didCaptureOriginal = true
}

// 3) 現在の「if !candidates.isEmpty { ... }」ブロック全体を、以下で置き換える
if !candidates.isEmpty {
    VStack(
        alignment: .leading,
        spacing: 12
    ) {
        HStack {
            Text("近い候補から選ぶ")
                .font(.headline)

            Spacer()

            if didCaptureOriginal,
               productName != originalProductName {
                Button {
                    productName = originalProductName
                    detectedBarcode = originalDetectedBarcode
                    recognitionSource = originalRecognitionSource
                    confidence = originalConfidence
                    brand = originalBrand
                    category = originalCategory
                    modelNumber = originalModelNumber
                    evidence = originalEvidence
                } label: {
                    Label(
                        "最初の判定に戻す",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(green)
                }
                .buttonStyle(.plain)
            }
        }

        if didCaptureOriginal,
           !originalProductName.isEmpty {
            HStack(spacing: 10) {
                Button {
                    productName = originalProductName
                    detectedBarcode = originalDetectedBarcode
                    recognitionSource = originalRecognitionSource
                    confidence = originalConfidence
                    brand = originalBrand
                    category = originalCategory
                    modelNumber = originalModelNumber
                    evidence = originalEvidence
                } label: {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text("最初の判定")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Text(originalProductName)
                                .font(.subheadline.bold())
                                .multilineTextAlignment(.leading)

                            Text(
                                productName == originalProductName
                                ? "選択中"
                                : "この商品に戻す"
                            )
                            .font(.caption2.bold())
                        }

                        Spacer()

                        Image(
                            systemName:
                                productName == originalProductName
                                ? "checkmark.circle.fill"
                                : "arrow.right.circle.fill"
                        )
                        .font(.title3)
                    }
                    .foregroundStyle(
                        productName == originalProductName
                        ? Color.black
                        : green
                    )
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(
                        productName == originalProductName
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

                Button {
                    let encoded =
                        originalProductName.addingPercentEncoding(
                            withAllowedCharacters: .urlQueryAllowed
                        ) ?? originalProductName

                    if let url = URL(
                        string:
                            "https://www.google.com/search?q=\(encoded)"
                    ) {
                        openURL(url)
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(
                            systemName:
                                "arrow.up.right.square.fill"
                        )
                        .font(.title3)

                        Text("確認")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(green)
                    .frame(width: 58, height: 58)
                    .background(green.opacity(0.12))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }

        ForEach(
            candidates.prefix(3),
            id: \.self
        ) { candidate in
            HStack(spacing: 10) {
                Button {
                    productName = candidate

                    // 候補を正式選択したら、
                    // 元の商品由来の識別情報を残さない
                    detectedBarcode = ""
                    recognitionSource =
                        "近い候補から選択"
                    confidence = 0
                    brand = ""
                    category = ""
                    modelNumber = ""
                    evidence = []
                } label: {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(candidate)
                                .font(.subheadline.bold())
                                .multilineTextAlignment(.leading)

                            Text(
                                productName == candidate
                                ? "選択中"
                                : "この候補を選ぶ"
                            )
                            .font(.caption2.bold())
                        }

                        Spacer()

                        Image(
                            systemName:
                                productName == candidate
                                ? "checkmark.circle.fill"
                                : "arrow.right.circle.fill"
                        )
                        .font(.title3)
                    }
                    .foregroundStyle(
                        productName == candidate
                        ? Color.black
                        : green
                    )
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(
                        productName == candidate
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

                Button {
                    let encoded =
                        candidate.addingPercentEncoding(
                            withAllowedCharacters: .urlQueryAllowed
                        ) ?? candidate

                    if let url = URL(
                        string:
                            "https://www.google.com/search?q=\(encoded)"
                    ) {
                        openURL(url)
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(
                            systemName:
                                "arrow.up.right.square.fill"
                        )
                        .font(.title3)

                        Text("確認")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(green)
                    .frame(width: 58, height: 58)
                    .background(green.opacity(0.12))
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
}

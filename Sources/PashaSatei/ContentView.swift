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

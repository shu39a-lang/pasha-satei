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

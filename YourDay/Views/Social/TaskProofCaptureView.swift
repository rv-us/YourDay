import SwiftUI
import PhotosUI
import UIKit

struct TaskProofCaptureView: View {
    let context: TaskProofCaptureContext
    var onSkip: () -> Void
    var onPosted: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var firebaseManager: FirebaseManager

    @State private var selectedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Text("Add photo proof")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(dynamicTextColor)

                Text(context.taskTitle)
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Group {
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipped()
                            .cornerRadius(14)
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(dynamicSecondaryBackgroundColor)
                            .frame(height: 280)
                            .overlay {
                                VStack(spacing: 10) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 40))
                                        .foregroundColor(dynamicSecondaryTextColor)
                                    Text("No photo selected")
                                        .foregroundColor(dynamicSecondaryTextColor)
                                        .font(.subheadline)
                                }
                            }
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showingCamera = true
                        } else {
                            errorMessage = "Camera is unavailable on this device."
                        }
                    } label: {
                        Label("Camera", systemImage: "camera")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(dynamicTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(10)
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, preferredItemEncoding: .automatic) {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(dynamicTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                Button {
                    postProof()
                } label: {
                    HStack(spacing: 8) {
                        if isPosting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isPosting ? "Posting..." : "Post Proof")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background((selectedImage == nil || isPosting) ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                    .cornerRadius(12)
                }
                .disabled(selectedImage == nil || isPosting)
                .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .padding(.top, 16)
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                    .disabled(isPosting)
                    .foregroundColor(dynamicPrimaryColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onSkip()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .disabled(isPosting)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker(selectedImage: $selectedImage)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            selectedImage = image
                        }
                    }
                }
            }
            .alert("Couldn't Post Proof", isPresented: Binding(
                get: { errorMessage != nil },
                set: { shown in
                    if !shown { errorMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Something went wrong while uploading your proof photo.")
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(isPosting)
    }

    private func postProof() {
        guard let selectedImage = selectedImage,
              let imageData = selectedImage.jpegData(compressionQuality: 0.82) else {
            errorMessage = "Please choose a valid photo."
            return
        }

        isPosting = true

        firebaseManager.createTaskProofPost(
            taskTitle: context.taskTitle,
            sourceType: context.sourceType,
            scheduledEventId: context.scheduledEventId,
            localTaskId: context.localTaskId,
            sharedTaskId: context.sharedTaskId,
            completedAt: context.completedAt,
            imageData: imageData,
            groupTaskId: context.groupTaskId,
            groupId: context.groupId
        ) { error, postId in
            DispatchQueue.main.async {
                isPosting = false
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let postId = postId else {
                    errorMessage = "Could not create proof post."
                    return
                }
                onPosted(postId)
                dismiss()
            }
        }
    }
}

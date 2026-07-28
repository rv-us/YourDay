import SwiftUI

/// Reusable circular avatar that loads a profile photo from a URL,
/// falling back to a person icon when no URL is provided.
struct ProfilePhotoView: View {
    let photoURL: String?
    var size: CGFloat = 36
    var fallbackIcon: String = "person.crop.circle.fill"

    var body: some View {
        if let photoURL = photoURL, let url = URL(string: photoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallbackImage
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackImage
                .frame(width: size, height: size)
        }
    }

    private var fallbackImage: some View {
        Image(systemName: fallbackIcon)
            .resizable()
            .scaledToFit()
            .foregroundColor(dynamicPrimaryColor)
    }
}

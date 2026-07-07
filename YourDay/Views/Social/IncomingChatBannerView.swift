import SwiftUI

struct IncomingChatBannerView: View {
    let banner: IncomingChatBannerPayload
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(dynamicPrimaryColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.senderName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(dynamicTextColor)
                        .lineLimit(1)
                    Text(banner.preview)
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(dynamicSecondaryTextColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(dynamicSecondaryBackgroundColor)
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(dynamicPrimaryColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

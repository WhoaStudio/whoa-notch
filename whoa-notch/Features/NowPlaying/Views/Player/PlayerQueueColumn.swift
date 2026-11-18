import SwiftUI

/// Colonne « Playing Next » : filet, titre et jusqu'à trois morceaux à venir.
struct PlayerQueueColumn: View {
  let items: [QueueItem]

  var body: some View {
    HStack(spacing: 0) {
      Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1).padding(.vertical, 8)
      VStack(alignment: .leading, spacing: 6) {
        Text("Playing Next")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.5))
        ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
          PlayerQueueRow(item: item)
        }
        Spacer(minLength: 0)
      }
      .padding(.leading, 14)
      .padding(.trailing, PlayerStyle.bleed)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct PlayerQueueRow: View {
  let item: QueueItem
  @State private var image: NSImage?

  var body: some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(Color.white.opacity(0.12))
        .overlay {
          if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 0) {
        Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        Text(item.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
      }
      .lineLimit(1)
    }
    .task(id: item.artwork) { image = item.artwork.flatMap(NSImage.init(data:)) }
  }
}

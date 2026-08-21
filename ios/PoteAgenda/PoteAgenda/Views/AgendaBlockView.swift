import SwiftUI

struct AgendaEventBlockView: View {
    let block: AgendaBlock
    let hideLabels: Bool
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: expanded ? 4 : 2) {
            if hideLabels {
                Text(block.subtitle ?? block.title)
                    .font(.caption2.weight(.black))
                    .lineLimit(1)
                    .opacity(0)
            } else {
                Text(block.title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle = block.subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if expanded {
                    Text(block.timeLabel)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .foregroundStyle(block.style.foregroundStyle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(block.style.backgroundColor(for: block))
                .overlay {
                    if block.style == .friendBusy {
                        Stripes()
                            .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(block.style.borderColor(for: block), lineWidth: block.style == .friendBusy ? 1 : 0)
                }
        }
    }
}

struct FriendBusyOverlayBlock: View {
    let block: AgendaBlock
    /// true pour un créneau trop court pour deux lignes : une seule ligne,
    /// police plus petite et padding réduit, plutôt que de laisser le texte
    /// se faire tronquer/rétrécir jusqu'à devenir illisible.
    var compact: Bool = false

    private var isPending: Bool { block.style == .friendPending }
    private var borderAccentColor: Color { isPending ? Color(hex: "#f97316") : .secondary }

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(isPending ? Color.potePendingOther : Color.poteBusyOther)
            .overlay {
                // Les hachures signalent une vraie indisponibilité ; une
                // invitation en attente n'en est pas une, donc pas de
                // hachures, juste une bordure en pointillés.
                if !isPending {
                    Stripes()
                        .stroke(Color.secondary.opacity(0.7), lineWidth: 1.4)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(borderAccentColor.opacity(isPending ? 0.5 : 0.55), style: StrokeStyle(lineWidth: isPending ? 1.4 : 1, dash: isPending ? [4, 3] : []))
            }
            .overlay(alignment: .topLeading) {
                // Texte toujours en .secondary (jamais dans la teinte
                // orange) pour rester lisible quel que soit le fond pâle
                // en clair comme en sombre.
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(compact ? .system(size: 9, weight: .black) : .caption2.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if isPending && !compact {
                        Text("Sollicité(e)")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(compact ? 3 : 5)
            }
    }
}

private struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 8
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

struct OverlapCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(.white)
            .frame(minWidth: 14, minHeight: 14)
            .padding(2)
            .background(Circle().fill(Color.accentColor))
            .offset(x: 5, y: -5)
    }
}

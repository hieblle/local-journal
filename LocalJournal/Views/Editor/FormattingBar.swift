import SwiftUI

/// A compact Markdown formatting toolbar (bold / italic / underline / strike +
/// heading / lists / quote). Each control inserts real Markdown around the
/// current selection via the `MarkdownEditingController`, so what is written maps
/// straight to the mirrored `.md` file.
struct FormattingBar: View {
    let controller: MarkdownEditingController

    var body: some View {
        HStack(spacing: 10) {
            group {
                button("bold", help: "Fett  **…**") { controller.wrap("**") }
                button("italic", help: "Kursiv  *…*") { controller.wrap("*") }
                button("underline", help: "Unterstrichen  <u>…</u>") {
                    controller.wrap(prefix: "<u>", suffix: "</u>")
                }
                button("strikethrough", help: "Durchgestrichen  ~~…~~") { controller.wrap("~~") }
            }
            group {
                button("textformat.size", help: "Überschrift  ## …") { controller.heading() }
                button("list.bullet", help: "Aufzählung  - …") { controller.bulletList() }
                button("list.number", help: "Nummerierte Liste  1. …") { controller.numberedList() }
                button("text.quote", help: "Zitat  > …") { controller.blockquote() }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.12)))
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
            .padding(3)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

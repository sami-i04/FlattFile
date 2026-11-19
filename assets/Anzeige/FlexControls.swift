import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

struct FlexSegments: View {
    let options: [String]
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Button { onSelect(i) } label: {
                    Text(options[i])
                        .font(.system(size: 12, weight: selected == i ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected == i ? Color.white : Color.clear)
                            .shadow(color: .black.opacity(selected == i ? 0.12 : 0), radius: 1, y: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == i ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.06)))
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}

struct MenuEntry {
    var title: String
    var checked = false
    var enabled = true
    var separator = false
    var action: () -> Void = {}
    static let divider = MenuEntry(title: "", separator: true)
}

final class MenuAction: NSObject {
    let run: () -> Void
    init(_ r: @escaping () -> Void) { run = r }
    @objc func fire() { run() }
}

struct FlexDropdown: View {
    let title: String
    var icon: String? = nil
    let entries: () -> [MenuEntry]

    var body: some View {
        Button(action: show) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
                Text(title).lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.black.opacity(0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibilityLabel(title)
    }

    func show() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for e in entries() {
            if e.separator { menu.addItem(.separator()); continue }
            let a = MenuAction(e.action)
            let it = NSMenuItem(title: e.title, action: #selector(MenuAction.fire), keyEquivalent: "")
            it.target = a
            it.representedObject = a
            it.state = e.checked ? .on : .off
            it.isEnabled = e.enabled
            menu.addItem(it)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

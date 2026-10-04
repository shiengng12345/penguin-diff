import SwiftUI
import CompareShared

struct ResultColumns {
    let path: CGFloat, status: CGFloat, value: CGFloat
    init(width: CGFloat) {
        let usable = max(0, width - 90)
        status = min(128, usable * 0.22)
        path = (usable - status) * 0.40
        value = (usable - status - path) / 2
    }
}
struct DisplayResultLine: Identifiable {
    let id: ResultOutlineID
    let path: String
    let row: ResultRow?
    let depth: Int
    let children: Bool
    let count: Int
}

struct ResultTableView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var model: Workspace
    var showDetail: () -> Void = {}
    @State private var collapsed: Set<ResultOutlineID> = []
    @FocusState private var listFocused: Bool
    private func tr(_ key: String, _ arguments: String...) -> String { L10n.text(key, arguments: arguments, language: preferences.language) }
    private var lines: [DisplayResultLine] {
        if !model.treeMode { return model.rows.map { .init(id: .result($0.id), path: $0.path, row: $0, depth: 0, children: false, count: 1) } }
        var pending = ResultOutline.build(model.rows).reversed().map { ($0, 0) }
        var output: [DisplayResultLine] = []
        while let (node, depth) = pending.popLast() {
            output.append(.init(id: node.id, path: node.path, row: node.row, depth: depth, children: node.children != nil, count: node.resultCount))
            if !collapsed.contains(node.id), let children = node.children { pending.append(contentsOf: children.reversed().map { ($0, depth + 1) }) }
        }
        return output
    }
    var body: some View {
        GeometryReader { geometry in
            let columns = ResultColumns(width: geometry.size.width)
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Text(tr(model.tool == .env ? (model.treeMode ? "变量 · 当前页树" : "变量") : (model.treeMode ? "路径 · 当前页树" : "路径"))).frame(width: columns.path, alignment: .leading)
                    Text(tr("状态")).frame(width: columns.status, alignment: .leading)
                    Text("A").foregroundStyle(Color(hex: 0x655094)).frame(width: columns.value, alignment: .leading)
                    Text("B").foregroundStyle(Color(hex: 0x335E92)).frame(width: columns.value, alignment: .leading)
                    Image(systemName: "ellipsis").frame(width: 18)
                }.font(.system(size: 11, weight: .semibold)).foregroundStyle(AppPalette.secondary).padding(.horizontal, 12).frame(height: 30)
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(lines) { line in resultLine(line, columns: columns) }
                    }.padding(.bottom, 6)
                }.focusable().focused($listFocused).onMoveCommand { direction in
                    let visible = lines.compactMap(\.row)
                    guard !visible.isEmpty else { return }
                    let index = visible.firstIndex { $0.id == model.selected } ?? -1
                    switch direction {
                    case .down: model.selected = visible[min(index + 1, visible.count - 1)].id
                    case .up: model.selected = visible[max(index - 1, 0)].id
                    default: return
                    }
                }
                .onChange(of: model.selected) { _, selection in
                    if let selection { proxy.scrollTo(ResultOutlineID.result(selection)) }
                }
                }
            }
        }
    }
    private func resultLine(_ line: DisplayResultLine, columns: ResultColumns) -> some View {
        let selected = model.outlineSelection == line.id
        let tone = ResultTone(rawValue: line.row?.status ?? "")
        return HStack(spacing: 12) {
            HStack(spacing: 5) {
                if line.children {
                    Button {
                        if collapsed.contains(line.id) { collapsed.remove(line.id) } else { collapsed.insert(line.id) }
                    } label: { Image(systemName: collapsed.contains(line.id) ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold)).frame(width: 14, height: 24) }
                        .buttonStyle(.plain).accessibilityLabel(model.resultName(line.path))
                }
                Text(model.resultName(line.path)).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1).truncationMode(.middle).help(model.resultName(line.path))
            }.padding(.leading, CGFloat(min(line.depth, 5)) * 10).frame(width: columns.path, alignment: .leading)
            Group {
                if let row = line.row { StatusPill(status: row.status, title: tr(statusNames[row.status] ?? row.status)) }
                else { Text(tr("分组 · 本页 {0} 项", String(line.count))).font(.system(size: 11)).foregroundStyle(AppPalette.secondary).lineLimit(1) }
            }.frame(width: columns.status, alignment: .leading)
            Group { if let row = line.row { cell(row.a) } else { Color.clear } }.frame(width: columns.value, alignment: .leading)
            Group { if let row = line.row { cell(row.b) } else { Color.clear } }.frame(width: columns.value, alignment: .leading)
            if line.row != nil {
                Button {
                    model.selectOutline(line.id); showDetail()
                } label: { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).frame(width: 18, height: 32) }
                    .buttonStyle(.plain).foregroundStyle(AppPalette.secondary).accessibilityLabel(tr("详情") + " " + model.resultName(line.path))
            } else { Color.clear.frame(width: 18, height: 32) }
        }.padding(.horizontal, 12).frame(height: line.row == nil ? 40 : 62)
            .foregroundStyle(AppPalette.ink)
            .background(selected ? AppPalette.selection : (tone?.background.opacity(0.40) ?? AppPalette.code), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? AppPalette.pink : AppPalette.line.opacity(0.75), lineWidth: selected ? 1.5 : 1))
            .modifier(AppRowHover()).contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { listFocused = true; model.selectOutline(line.id); if line.row != nil { showDetail() } }
            .accessibilityElement(children: .contain).accessibilityAddTraits(selected ? .isSelected : [])
            .contextMenu {
                Button(tr(model.tool == .env ? "复制变量" : "复制路径")) { model.copy(model.resultName(line.path)) }

            }
    }
    private func cell(_ side: Side) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.valuePreview(type: side.type, display: side.display, language: preferences.language) + (side.truncated == true ? "…" : ""))
                .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.tail)
            Text(L10n.typeName(side.type, language: preferences.language)).font(.system(size: 10)).foregroundStyle(AppPalette.secondary)
        }
    }
}

struct ValueOutlineView: View {
    @EnvironmentObject private var preferences: AppPreferences
    private func tr(_ key: String, _ arguments: String...) -> String { L10n.text(key, arguments: arguments, language: preferences.language) }
    let side: Side
    var variableNames = false
    var body: some View {
        let nodes = ValueOutline.children(of: side)
        if !nodes.isEmpty {
            DisclosureGroup(tr("结构 · 只读内容，不增加差异计数")) {
                List(nodes, children: \.children) { node in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variableNames ? OutlinePath.variableDisplay(node.path, rootName: "") : node.path).font(.system(.caption, design: .monospaced)).lineLimit(1).help(variableNames ? OutlinePath.variableDisplay(node.path, rootName: "") : node.path)
                        Text(L10n.typeName(node.value.type, language: preferences.language) + " · " + L10n.valuePreview(type: node.value.type, display: node.preview, language: preferences.language)).font(.system(.caption, design: .monospaced)).lineLimit(2)
                        if node.value.complete == false { Text(tr("对象范围不完整")).font(.caption2).foregroundStyle(Color(hex: 0x8C5323)) }
                    }.accessibilityElement(children: .combine)
                }.listStyle(.plain).frame(height: 240)
            }.font(.caption)
        }
    }
}

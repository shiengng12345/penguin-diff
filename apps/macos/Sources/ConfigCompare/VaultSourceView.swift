import SwiftUI
import CompareShared

struct VaultObservationView: View {
    let source: VaultSourceSnapshot
    let observation: VaultObservation
    @ObservedObject var preferences: AppPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.side + " · " + source.origin + " · " + source.mount).bold()
            Text(preferences.text("namespace：{0} · secret：{1}", observation.namespace.isEmpty ? "root" : observation.namespace, observation.path))
            Text(preferences.text("KV v{0} · secret 版本：{1}", String(observation.metadata.kvVersion), observation.metadata.version ?? preferences.text("未知")))
            Text(preferences.text("创建时间：{0}", observation.metadata.createdTime ?? preferences.text("未知")))
            Text(preferences.text("删除／计划删除时间：{0}", observation.metadata.deletionTime.map { $0.isEmpty ? preferences.text("未删除") : $0 } ?? preferences.text("未知")))
            Text(preferences.text("销毁：{0}", observation.metadata.destroyed.map { preferences.text($0 ? "是" : "否") } ?? preferences.text("未知")))
            Text(preferences.text("本机读取：{0} → {1}", observation.started, observation.finished))
        }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VaultSourcesView: View {
    let sources: [VaultSourceSnapshot]
    @ObservedObject var preferences: AppPreferences
    private var readings: [(source: VaultSourceSnapshot, observation: VaultObservation)] {
        Array(sources.flatMap { source in source.observations.map { (source, $0) } }.prefix(200))
    }
    var body: some View {
        DisclosureGroup(preferences.text("Vault 读取来源 · {0} 条", String(sources.reduce(0) { $0 + $1.observations.count }))) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text(preferences.text("各条读取不是原子快照；版本不同不会计为业务配置差异。"))
                    ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                        VaultObservationView(source: reading.source, observation: reading.observation, preferences: preferences)
                        Divider()
                    }
                    if sources.reduce(0, { $0 + $1.observations.count }) > 200 {
                        Text(preferences.text("此处显示前 200 条来源；完整记录可在 JSON 报告查看。"))
                    }
                }
            }.frame(maxHeight: 150)
        }.font(.caption)
    }
}

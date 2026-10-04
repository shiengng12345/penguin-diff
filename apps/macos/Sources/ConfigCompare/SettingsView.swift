import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, profile, appearance
    var id: String { rawValue }
    var title: String { switch self { case .general: "通用"; case .profile: "本机个性化"; case .appearance: "外观" } }
    var icon: String { switch self { case .general: "slider.horizontal.3"; case .profile: "person.crop.circle"; case .appearance: "paintpalette" } }
}

struct ProfileBadge: View {
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        HStack(spacing: 12) {
            ProfileIconView(icon: preferences.avatar.systemImage, size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text(preferences.username.isEmpty ? preferences.text("未设置显示名称") : preferences.username).font(.headline)
                Text(preferences.text("仅在本机显示，无需账号。最多 40 个字符。")).font(.caption).foregroundStyle(AppPalette.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @State private var section: SettingsSection = .general
    @State private var usernameDraft = ""
    let close: () -> Void
    init(section: SettingsSection = .general, close: @escaping () -> Void) {
        _section = State(initialValue: section)
        self.close = close
    }
    private func tr(_ key: String) -> String { preferences.text(key) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: close) { Label(tr("返回工具"), systemImage: "chevron.left") }
                    .keyboardShortcut(.cancelAction).padding(.bottom, 24)
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppPalette.rose).frame(width: 38, height: 38)
                        .background(AppPalette.selection, in: RoundedRectangle(cornerRadius: 12))
                    Text(tr("设置")).font(.system(size: 23, weight: .bold))
                }.padding(.bottom, 20)
                ForEach(SettingsSection.allCases) { item in
                    Button { section = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).frame(width: 22)
                            Text(tr(item.title)); Spacer()
                        }.padding(.horizontal, 12).frame(height: 44)
                            .foregroundStyle(section == item ? AppPalette.rose : AppPalette.secondary)
                            .background(section == item ? AppPalette.selection : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(section == item ? AppPalette.pink.opacity(0.45) : .clear))
                    }.buttonStyle(AppNavigationStyle()).accessibilityAddTraits(section == item ? .isSelected : [])
                }
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.system(size: 42, weight: .light))
                    .foregroundStyle(AppPalette.pink.opacity(0.65)).frame(width: 130, height: 100).frame(maxWidth: .infinity)
            }.padding(16).frame(width: 224).background(AppPalette.sidebar)
            Rectangle().fill(AppPalette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 24) {
                Text(tr(section.title)).font(.system(size: 25, weight: .bold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch section {
                        case .general:
                            setting("界面语言") {
                                Picker(tr("界面语言"), selection: $preferences.language) {
                                    ForEach(AppLanguage.allCases) { language in Text(language.nativeName).tag(language) }
                                }.labelsHidden().frame(width: 260)
                                Text(tr("立即生效，重启后保留。")).font(.caption).foregroundStyle(AppPalette.secondary)
                            }
                        case .profile:
                            ProfileBadge().appCard()
                            setting("显示名称") {
                                TextField(tr("未设置显示名称"), text: $usernameDraft)
                                    .accessibilityLabel(tr("显示名称")).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
                                    .onAppear { usernameDraft = preferences.username }
                                    .onChange(of: usernameDraft) { _, value in
                                        let bounded = AppPreferences.boundedNameDraft(value)
                                        if usernameDraft != bounded { usernameDraft = bounded }
                                        preferences.username = bounded
                                    }
                                Text(tr("仅在本机显示，无需账号。最多 40 个字符。")).font(.caption).foregroundStyle(AppPalette.secondary)
                            }
                            setting("头像") {
                                HStack(spacing: 12) {
                                    ForEach(AppAvatar.allCases) { avatar in
                                        Button { preferences.avatar = avatar } label: {
                                            VStack(spacing: 8) {
                                                ProfileIconView(icon: avatar.systemImage, size: 76)
                                                Text(tr(avatar.title)).font(.caption)
                                            }.frame(width: 104).padding(.vertical, 12)
                                                .background(preferences.avatar == avatar ? AppPalette.selection : AppPalette.code, in: RoundedRectangle(cornerRadius: 12))
                                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(preferences.avatar == avatar ? AppPalette.pink : AppPalette.line, lineWidth: preferences.avatar == avatar ? 2 : 1))
                                        }.buttonStyle(.plain).accessibilityLabel(tr(avatar.title))
                                            .accessibilityAddTraits(preferences.avatar == avatar ? .isSelected : [])
                                    }
                                }
                            }
                        case .appearance:
                            setting("主题") {
                                HStack(spacing: 14) {
                                    Image(systemName: "sun.max.fill").font(.system(size: 28, weight: .medium)).foregroundStyle(AppPalette.rose)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tr("奶油白")).font(.headline)
                                        Text(tr("奶油白与柔粉，安静清晰。")).font(.caption).foregroundStyle(AppPalette.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppPalette.rose)
                                }.padding(14).background(AppPalette.selection.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                            }
                            setting("强调色") {
                                HStack(spacing: 12) {
                                    ForEach(AppAccent.allCases) { accent in
                                        Button { preferences.accent = accent } label: {
                                            Image(systemName: preferences.accent == accent ? "checkmark.circle.fill" : "circle.fill")
                                                .font(.system(size: 26)).foregroundStyle(accent.color).padding(4)
                                        }.buttonStyle(.plain).help(tr(accent.title)).accessibilityLabel(tr(accent.title))
                                            .accessibilityAddTraits(preferences.accent == accent ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }.frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).padding(1)
                }
                Spacer(minLength: 0)
                HStack {
                    Text(tr("显示偏好仅保存在本机。")).font(.caption).foregroundStyle(AppPalette.secondary)
                    Spacer()
                    Button(tr("恢复默认设置")) { preferences.reset(); usernameDraft = "" }
                        .help(tr("只重置语言、显示名称、头像和外观。"))
                }
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.background(AppPalette.background).foregroundStyle(AppPalette.ink).font(.system(size: 13)).buttonStyle(AppButtonStyle())
    }
    private func setting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(tr(title)).font(.headline); content() }
            .frame(maxWidth: .infinity, alignment: .leading).appCard(padding: 20)
    }
}

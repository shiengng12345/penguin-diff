import Foundation
import Testing
import CoreBridge
@testable import CompareUI

@Suite(.serialized)
struct SettingsTests {
    // Catches preferences leaking to the real app domain or being lost on reopen.
    @Test @MainActor func preferencesPersistOnlyPresentationFields() throws {
        let suite = "config-compare-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppPreferences(defaults: defaults, preferredLanguages: ["zh-Hans-MY"])
        first.language = .english
        first.theme = .dark
        first.accent = .purple
        first.avatar = .compare
        first.username = "值班 SRE"
        let reopened = AppPreferences(defaults: defaults, preferredLanguages: ["zh-Hans"])
        #expect(reopened.language == .english && reopened.theme == .light)
        #expect(reopened.accent == .purple && reopened.avatar == .compare)
        #expect(reopened.displayName == "值班 SRE")
        let persisted = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(Set(persisted.keys) == Set(["appearance.language", "appearance.theme", "appearance.accent", "appearance.avatar", "appearance.username", "appearance.placeholderMigrated"]))
        #expect(!persisted.description.contains("Token"))
    }

    // Catches invalid saved enums taking precedence over supported system languages.
    @Test @MainActor func corruptPreferencesFallBackAndSupportedLocaleIsResolved() throws {
        let suite = "config-compare-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "appearance.language")
        defaults.set("broken", forKey: "appearance.theme")
        defaults.set("unknown", forKey: "appearance.avatar")
        defaults.set("unknown", forKey: "appearance.accent")
        let chinese = AppPreferences(defaults: defaults, preferredLanguages: ["fr-FR", "zh-Hant-TW", "en-US"])
        #expect(chinese.language == .simplifiedChinese)
        #expect(chinese.theme == .light && chinese.avatar == .person && chinese.accent == .pink)
        let english = AppPreferences(defaults: nil, preferredLanguages: ["de-DE", "en-MY", "zh-Hans"])
        #expect(english.language == .english)
        #expect(AppPreferences(defaults: nil, preferredLanguages: ["ja-JP"]).language == .english)
    }

    // Catches splitting emoji graphemes, preserving controls, and unbounded names.
    @Test @MainActor func usernameIsBoundedWithoutBreakingUnicodeAndEmptyUsesLocalizedDefault() {
        let preferences = AppPreferences(defaults: nil, preferredLanguages: ["zh-Hans"])
        preferences.username = " \n值班\t👩🏽‍💻\u{0} "
        #expect(preferences.username == "值班👩🏽‍💻")
        preferences.username = String(repeating: "👩🏽‍💻", count: 45)
        #expect(preferences.username.count == 40)
        #expect(preferences.username == String(repeating: "👩🏽‍💻", count: 40))
        preferences.username = "   "
        #expect(preferences.displayName == "SRE 用户")
        preferences.language = .english
        #expect(preferences.displayName == "SRE user")
    }

    // Catches recursive substitution corrupting literal config/file text.
    @Test func localizedMessagesKeepArgumentsLiteralAndReRenderWithoutLosingData() {
        let message = LocalizedMessage.text("已导出到新文件：{0}", ["中文-{1}-💾.yaml"])
        #expect(message.render(in: .english) == "Exported to a new file: 中文-{1}-💾.yaml")
        #expect(message.render(in: .simplifiedChinese) == "已导出到新文件：中文-{1}-💾.yaml")
        let unknown = LocalizedMessage.literal("{0} user config 相同")
        #expect(unknown.render(in: .english) == "{0} user config 相同")
    }

    // Catches trimming the editor's trailing space, which prevents typing a multiword name.
    @Test @MainActor func nameDraftPreservesTypingSpacesButBoundsControlsAndGraphemes() {
        #expect(AppPreferences.boundedNameDraft("John ") == "John ")
        #expect(AppPreferences.boundedNameDraft("John Doe") == "John Doe")
        #expect(AppPreferences.boundedNameDraft("值班\u{0} SRE\n") == "值班 SRE")
        #expect(AppPreferences.boundedNameDraft(String(repeating: "👩🏽‍💻", count: 45)) == String(repeating: "👩🏽‍💻", count: 40))
    }

    // Catches translating actual string values as if they were generated placeholders.
    @Test func valuePresentationUsesTypesRatherThanReplacingUserStrings() {
        #expect(L10n.valuePreview(type: "Missing", display: "<不存在>", language: .english) == "<Missing>")
        #expect(L10n.valuePreview(type: "Hole", display: "<空槽>", language: .english) == "<Hole>")
        #expect(L10n.valuePreview(type: "String", display: "\"<不存在>\"", language: .english) == "\"<不存在>\"")
        #expect(L10n.valuePreview(type: "Object", display: "{ 3 个键 }", language: .english) == "{ 3 keys }")
        #expect(L10n.valuePreview(type: "Array", display: "[ 2 项 ]", language: .english) == "[ 2 items ]")
        #expect(L10n.valuePreview(type: "Number", display: "9007199254740993", language: .english) == "9007199254740993")
        #expect(L10n.typeName("Number", language: .simplifiedChinese) == "数字")
        #expect(L10n.typeName("Number", language: .english) == "Number")
    }

    // Catches preferences clearing a session, invalidating a Vault scope, or calling the network.
    @Test @MainActor func settingsNavigationAndPresentationChangesPreserveActualResults() async throws {
        let preferences = AppPreferences(defaults: nil, preferredLanguages: ["zh-Hans"])
        let model = Workspace(clientFactory: { DirectCoreWorker() }, preferences: preferences)
        model.a = "var env={name:'中文',port:1};"
        model.b = "var env={name:'中文',port:2};"
        model.vaultA.token = "synthetic-not-persisted"
        model.run()
        let deadline = ContinuousClock.now + .seconds(5)
        while (model.busy || model.matched != 1), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(model.summary?.total == 2 && model.matched == 1)
        let rows = model.rows.map(\.path)
        model.showSettings()
        preferences.language = .english; preferences.theme = .dark
        preferences.avatar = .terminal; preferences.username = "Alice"
        #expect(model.showingSettings)
        #expect(model.noticeLocalized == "Comparison complete.")
        #expect(model.a == "var env={name:'中文',port:1};")
        #expect(model.summary?.total == 2 && model.rows.map(\.path) == rows && !model.stale)
        #expect(model.vaultA.token == "synthetic-not-persisted")
        model.closeSettings()
        #expect(!model.showingSettings)
        model.selected = model.rows.first?.id; model.inspectSelection()
        let detailDeadline = ContinuousClock.now + .seconds(5)
        while model.detail == nil, ContinuousClock.now < detailDeadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(model.detail?.b.literal == "2")
        preferences.language = .simplifiedChinese
        #expect(model.noticeLocalized == "比较完成。")
        model.cancel()
    }

    // Catches a locale switch losing the controlled diagnostic code or byte location.
    @Test @MainActor func errorsSwitchLanguageWithoutRunningAgain() async throws {
        let preferences = AppPreferences(defaults: nil, preferredLanguages: ["zh-Hans"])
        let model = Workspace(clientFactory: { DirectCoreWorker() }, preferences: preferences)
        model.a = "var env={"; model.b = "var env={x:1};"; model.run()
        let deadline = ContinuousClock.now + .seconds(5)
        while !model.error, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        try #require(model.error)
        #expect(model.noticeLocalized.contains("JavaScript 语法错误"))
        preferences.language = .english
        #expect(model.noticeLocalized.contains("JS_PARSE_ERROR"))
        #expect(model.noticeLocalized.contains("JavaScript syntax error"))
        #expect(model.a == "var env={")
        // OXC syntax diagnostics currently have no source location; JSON supplies one.
        model.tool = .vault; model.vaultLive = false
        model.a = "{\n\"x\": }"; model.b = "{}"; model.run()
        let jsonDeadline = ContinuousClock.now + .seconds(5)
        while (model.busy || !model.noticeLocalized.contains("JSON_PARSE_ERROR")), ContinuousClock.now < jsonDeadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(model.noticeLocalized.contains("JSON input could not be parsed reliably"))
        #expect(model.noticeLocalized.contains("UTF-8 byte column"))
        #expect(model.noticeLocalized.contains("line 2"))
        preferences.language = .simplifiedChinese
        #expect(model.noticeLocalized.contains("第 2 行"))
        model.cancel()
    }

    // Catches reset affecting content, credentials, or unrelated user preferences.
    @Test @MainActor func resetTouchesOnlyOwnedSettings() throws {
        let suite = "config-compare-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unrelated-value", forKey: "unrelated")
        let preferences = AppPreferences(defaults: defaults, preferredLanguages: ["zh-Hans"])
        let model = Workspace(clientFactory: { DirectCoreWorker() }, preferences: preferences)
        model.a = "yaml: original\n"; model.vaultA.token = "synthetic-token"
        preferences.language = .english; preferences.theme = .dark
        preferences.username = "Alice"; preferences.avatar = .compare; preferences.accent = .purple
        preferences.reset()
        #expect(preferences.language == .simplifiedChinese && preferences.theme == .light)
        #expect(preferences.username.isEmpty && preferences.avatar == .person && preferences.accent == .pink)
        #expect(model.a == "yaml: original\n" && model.vaultA.token == "synthetic-token")
        #expect(defaults.string(forKey: "unrelated") == "unrelated-value")
    }

    // Catches replacing actionable file errors with only an opaque numeric code.
    @Test @MainActor func actualFileReadFailuresRemainActionableInBothLanguages() async throws {
        let preferences = AppPreferences(defaults: nil, preferredLanguages: ["en"])
        let model = Workspace(clientFactory: { DirectCoreWorker() }, preferences: preferences)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        model.a = "original"
        model.importFile(file, side: true)
        let deadline = ContinuousClock.now + .seconds(5)
        while !model.error, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(model.noticeLocalized == "The local file does not exist.")
        preferences.language = .simplifiedChinese
        #expect(model.noticeLocalized == "本地文件不存在。")
        try Data([0xff, 0xfe, 0xff]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        model.error = false; model.importFile(file, side: true)
        let encodingDeadline = ContinuousClock.now + .seconds(5)
        while !model.error, ContinuousClock.now < encodingDeadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(model.noticeLocalized == "文件不是有效的 UTF-8。")
        #expect(model.a == "original")
        preferences.language = .english
        #expect(model.noticeLocalized == "The file is not valid UTF-8.")
    }
}

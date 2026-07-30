import XCTest
@testable import RealityLink

final class LocalizationTests: XCTestCase {
    func testAllSupportedLanguagesHaveCoreConnectionLabels() {
        XCTAssertEqual(L10n.t("connect", .english), "Connect")
        XCTAssertEqual(L10n.t("connect", .chinese), "连接")
        XCTAssertEqual(L10n.t("connect", .russian), "Подключить")
    }

    func testLanguageNativeNamesAreUnambiguous() {
        XCTAssertEqual(AppLanguage.allCases.map(\.nativeName), ["English", "中文", "Русский"])
    }
}

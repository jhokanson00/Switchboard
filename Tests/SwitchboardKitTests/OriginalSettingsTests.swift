import Foundation
import Testing
@testable import SwitchboardKit

@Test func remembersOnlyTheFirstOriginal() {
    var o = OriginalSettings()
    o.willChange("dock", from: false)
    o.didChange("dock", to: true)
    o.willChange("dock", from: true)
    #expect(o.values == ["dock": false])
}

@Test func dropsASettingOnceItsBackToOriginal() {
    var o = OriginalSettings()
    o.willChange("dock", from: false)
    o.didChange("dock", to: true)
    o.willChange("dock", from: true)
    o.didChange("dock", to: false)
    #expect(o.isEmpty)
}

@Test func readsBoolPreferencesInEveryCommonForm() {
    #expect(PreferenceValue.bool(NSNumber(value: true)) == true)
    #expect(PreferenceValue.bool(NSNumber(value: 0)) == false)
    #expect(PreferenceValue.bool("YES") == true)
    #expect(PreferenceValue.bool("false") == false)
    #expect(PreferenceValue.bool("maybe") == nil)
    #expect(PreferenceValue.bool(nil) == nil)
}

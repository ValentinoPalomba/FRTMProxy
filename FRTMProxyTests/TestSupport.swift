import Foundation
@testable import FRTMProxy

/// Helper per costruire un `MitmFlow` nei test.
///
/// `MitmFlow` espone solo `init(from:)` (niente memberwise init), quindi lo si
/// costruisce dal JSON — esattamente come arriva dallo stdout del bridge.
enum FlowFixture {
    /// Decodifica un `MitmFlow` da una stringa JSON. Fallisce il test se il JSON non è valido.
    static func make(_ json: String) -> MitmFlow {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(MitmFlow.self, from: Data(json.utf8))
    }
}

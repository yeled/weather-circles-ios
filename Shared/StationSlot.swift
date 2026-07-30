import Foundation

/// One tappable piece of the station plot. The identity lives here (next
/// to the renderer that hit-tests it); the human explanation of each one
/// lives in the app's `StationGuide`, since the widgets never explain
/// themselves.
enum StationSlot: String, Identifiable, CaseIterable {
    case cloud            // N — the circle's fill
    case wind             // dd ff — the barb
    case presentWeather   // ww
    case temperature      // TT
    case dewPoint         // TdTd
    case pressure         // PPP
    case tendency         // a + pp
    case pastWeather      // W₁
    case visibility       // VV
    case cloudGenus       // C_L

    var id: String { rawValue }
}

import Testing
@testable import VozCore

struct PasteboardMarkersTests {
    @Test func pureInsertIsTransientAndConcealed() {
        #expect(PasteboardMarkers.types(copyToClipboard: false) == [PasteboardMarkers.transient, PasteboardMarkers.concealed])
    }

    @Test func keptClipboardCarriesNoMarker() {
        #expect(PasteboardMarkers.types(copyToClipboard: true).isEmpty)
    }
}

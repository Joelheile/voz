import SwiftUI
import VozCore

struct SpeechModelPage: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: ModelStatus
    @ObservedObject var catalog: ExtensionCatalog
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageBar(title: "Speech model", back: back)
            SpeechModelPicker(selection: $settings.speechModel, extensions: ModelOption.extensions(catalog.speechModels), status: status, showsTitle: false)
            if let model = SpeechModel(rawValue: settings.speechModel), model != .appleSpeech {
                ModelStatusLabel(status: status, model: model)
                    .font(.meta)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

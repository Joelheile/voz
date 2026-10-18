public struct DictationMetrics: Equatable, Sendable {
    public var audioSeconds: Double
    public var wordCount: Int
    public var sttMs: Int
    public var cleanupMs: Int
    public var insertMs: Int
    public var totalMs: Int
    public var model: SpeechModel
    public var selectedModel: SpeechModel
    public var cleanupUsed: Bool
    public var cleanupTimedOut: Bool
    public var trigger: DictationTrigger
    public var output: DeliveryOutput

    public init(
        audioSeconds: Double,
        wordCount: Int,
        sttMs: Int,
        cleanupMs: Int,
        insertMs: Int,
        totalMs: Int,
        model: SpeechModel,
        selectedModel: SpeechModel,
        cleanupUsed: Bool,
        cleanupTimedOut: Bool,
        trigger: DictationTrigger,
        output: DeliveryOutput
    ) {
        self.audioSeconds = audioSeconds
        self.wordCount = wordCount
        self.sttMs = sttMs
        self.cleanupMs = cleanupMs
        self.insertMs = insertMs
        self.totalMs = totalMs
        self.model = model
        self.selectedModel = selectedModel
        self.cleanupUsed = cleanupUsed
        self.cleanupTimedOut = cleanupTimedOut
        self.trigger = trigger
        self.output = output
    }
}

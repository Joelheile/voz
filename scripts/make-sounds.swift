import Foundation

let sampleRate = 44100.0

struct Cue {
    let name: String
    let frequency: Double
    let sweep: Double
    let seconds: Double
}

func samples(for cue: Cue) -> [Int16] {
    let count = Int(cue.seconds * sampleRate)
    var phase = 0.0
    return (0..<count).map { index in
        let time = Double(index) / sampleRate
        let frequency = cue.frequency + cue.sweep * (time / cue.seconds)
        phase += 2 * .pi * frequency / sampleRate
        let attack = min(1, time / 0.002)
        let decay = exp(-time * 70)
        let tone = sin(phase) + 0.25 * sin(phase * 2)
        return Int16(max(-1, min(1, tone * attack * decay * 0.3)) * Double(Int16.max))
    }
}

func wav(from pcm: [Int16]) -> Data {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let byteCount = UInt32(pcm.count * 2)
    data.append(contentsOf: Array("RIFF".utf8))
    append(36 + byteCount)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(sampleRate))
    append(UInt32(sampleRate) * 2)
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    append(byteCount)
    pcm.forEach { append($0) }
    return data
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-sounds.swift <output directory>\n".utf8))
    exit(64)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let cues = [
    Cue(name: "start", frequency: 1100, sweep: 250, seconds: 0.09),
    Cue(name: "stop", frequency: 820, sweep: -220, seconds: 0.09),
]
for cue in cues {
    try wav(from: samples(for: cue)).write(to: directory.appendingPathComponent("\(cue.name).wav"))
}

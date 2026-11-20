//
//  SpeechReader.swift
//  ReaderApp
//
//  朗读（TTS）：系统 AVSpeech，按段排队，能暂停 / 继续 / 停止
//

import AVFoundation
import Combine

final class SpeechReader: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechReader()

    @Published private(set) var speaking = false
    @Published private(set) var paused = false

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [String] = []
    private var cursor = 0

    /// 语速，0.35–0.65 之间可调，默认 0.5
    var rate: Float {
        get {
            let stored = UserDefaults.standard.double(forKey: "ttsRate")
            return Float(stored > 0 ? stored : 0.5)
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: "ttsRate")
        }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
    }

    func speak(_ text: String, key: String) {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plain.isEmpty == false else { return }

        stop()

        queue = Self.chunks(plain)
        cursor = 0
        speaking = true
        paused = false

        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        enqueueNext()
    }

    /// 一点就切换：没在读 → 从头读；在读 → 停
    func toggle(_ text: String, key: String) {
        if speaking {
            if paused {
                resume()
            } else {
                stop()
            }
        } else {
            speak(text, key: key)
        }
    }

    func pause() {
        guard speaking, synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
        paused = true
    }

    func resume() {
        guard speaking, paused else { return }
        synthesizer.continueSpeaking()
        paused = false
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        queue = []
        cursor = 0
        speaking = false
        paused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func enqueueNext() {
        guard cursor < queue.count else {
            speaking = false
            paused = false
            return
        }
        let chunk = queue[cursor]
        cursor += 1

        let utterance = AVSpeechUtterance(string: chunk)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.06
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.speaking else { return }
            self.enqueueNext()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.speaking = false
            self?.paused = false
        }
    }

    // MARK: - 切段

    /// 按句号切段，一段最多 700 字。整章几千字一次性交给引擎会很久才开口。
    private static func chunks(_ text: String) -> [String] {
        var result: [String] = []
        var buffer = ""

        for character in text {
            buffer.append(character)
            if buffer.count >= 240, "。！？…\n".contains(character) {
                append(buffer, to: &result)
                buffer = ""
            } else if buffer.count >= 700 {
                append(buffer, to: &result)
                buffer = ""
            }
        }
        append(buffer, to: &result)
        return result
    }

    private static func append(_ piece: String, to result: inout [String]) {
        let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        result.append(trimmed)
    }
}

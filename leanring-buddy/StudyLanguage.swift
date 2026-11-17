//
//  StudyLanguage.swift
//  leanring-buddy
//
//  The language Thambi answers in. Many students think in Tamil, Hindi or another Indian language
//  and study from English textbooks, so by default Thambi answers in whatever language the
//  question was asked in, keeping technical terms in English (that is how exams are written).
//
//  A question typed in Tamil or Devanagari script can't be matched against English notes word by
//  word, so it is first turned into English search words (one tiny AI call, well under ₹0.01).
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

nonisolated enum StudyLanguage: String, CaseIterable, Codable, Sendable {
    case sameAsQuestion
    case english
    case tamil
    case hindi
    case telugu
    case kannada
    case malayalam
    case bengali
    case marathi
    case tanglish
    case hinglish

    var title: String {
        switch self {
        case .sameAsQuestion: return "Same as my question"
        case .english: return "English"
        case .tamil: return "Tamil (தமிழ்)"
        case .hindi: return "Hindi (हिन्दी)"
        case .telugu: return "Telugu (తెలుగు)"
        case .kannada: return "Kannada (ಕನ್ನಡ)"
        case .malayalam: return "Malayalam (മലയാളം)"
        case .bengali: return "Bengali (বাংলা)"
        case .marathi: return "Marathi (मराठी)"
        case .tanglish: return "Tamil and English mixed"
        case .hinglish: return "Hindi and English mixed"
        }
    }

    private var promptName: String {
        switch self {
        case .sameAsQuestion, .english: return "english"
        case .tamil: return "tamil, in tamil script"
        case .hindi: return "hindi, in devanagari script"
        case .telugu: return "telugu, in telugu script"
        case .kannada: return "kannada, in kannada script"
        case .malayalam: return "malayalam, in malayalam script"
        case .bengali: return "bengali, in bengali script"
        case .marathi: return "marathi, in devanagari script"
        case .tanglish: return "tanglish: everyday tamil written in english letters, mixed with english the way chennai college students talk"
        case .hinglish: return "hinglish: everyday hindi written in english letters, mixed with english the way college students talk"
        }
    }

    /// Added to a system prompt. `answeringStudent` is false for material Thambi makes on its own
    /// (quiz questions, cards), where there is no question whose language could be followed.
    func instruction(answeringStudent: Bool) -> String {
        switch self {
        case .sameAsQuestion:
            return answeringStudent
                ? "\n- reply in the language and script the student wrote in (tamil, hindi, tanglish, english or any other). keep technical terms in english, the way exams write them."
                : ""
        case .english:
            return "\n- reply in english."
        default:
            return "\n- write in \(promptName). keep technical terms, formulas and code in english, with the english term in brackets the first time if you translate it."
        }
    }

    private static let key = "studyAnswerLanguage"

    static var current: StudyLanguage {
        get { UserDefaults.standard.string(forKey: key).flatMap(StudyLanguage.init(rawValue:)) ?? .sameAsQuestion }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// True when the text is mostly written in an Indian script (Devanagari through Malayalam,
    /// U+0900 to U+0D7F), which English notes can't be searched with directly.
    static func isMostlyIndianScript(_ text: String) -> Bool {
        var indian = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x0900...0x0D7F).contains(scalar.value) { indian += 1 }
            else if (65...90).contains(scalar.value) || (97...122).contains(scalar.value) { latin += 1 }
        }
        return indian >= 3 && indian > latin
    }

    static let searchTranslationPrompt = """
    turn the student's question into english search words for their english study notes: the subject terms only, 3 to 10 words, no sentence, nothing else.
    """
}

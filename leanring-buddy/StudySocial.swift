//
//  StudySocial.swift
//  leanring-buddy
//
//  Studying with friends: who your friends are, what they are studying right now, messages,
//  and the things you can send each other to teach with (a note, a drawing or 3D model,
//  a set of flashcards).
//
//  • Everything here is plain data. How it travels is a separate piece (StudySocialTransport):
//    today that is the local network, friend to friend, with no server; a backend can replace it
//    later without touching these types.
//  • Nothing is shared until the student turns "Study with friends" on, and then only with
//    friends they accepted. A status says what subject and for how long, never what is on screen.
//  • A shared drawing travels as its text description and is drawn again on the other Mac by the
//    same renderer; it is never run as code.
//
//  Pure Foundation, no UI, so it can be unit-tested on its own.
//

import Foundation

// MARK: - People

nonisolated struct StudyProfile: Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
}

nonisolated struct StudyStatus: Codable, Equatable, Sendable {
    enum Activity: String, Codable, Sendable { case focusing, practising, asking, onBreak, online }

    var activity: Activity = .online
    var subject: String?
    /// When this activity began, so the other side can count the minutes up.
    var startedAt = Date()
    /// For a focus session: when it ends.
    var endsAt: Date?
    var minutesToday = 0
    var streakDays = 0
    var sentAt = Date()

    /// "Focusing on DBMS, 12 min left", "Practising Physics for 8 min", "Online".
    func line(at now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(startedAt) / 60))
        let about = subject.map { " \($0)" } ?? ""
        switch activity {
        case .focusing:
            if let endsAt, endsAt > now {
                return "Focusing\(subject.map { " on \($0)" } ?? ""), \(max(1, Int((endsAt.timeIntervalSince(now) / 60).rounded(.up)))) min left"
            }
            return "Focusing\(subject.map { " on \($0)" } ?? "")"
        case .practising: return minutes >= 1 ? "Practising\(about) for \(minutes) min" : "Practising\(about)"
        case .asking: return "Studying\(about)"
        case .onBreak: return "On a break"
        case .online: return "Online"
        }
    }

    var isStudying: Bool { activity == .focusing || activity == .practising || activity == .asking }
}

nonisolated struct StudyFriend: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var addedAt = Date()
    /// Agreed when the friendship was made; a peer must show it again to be treated as this friend.
    var token: String
    var lastSeen: Date?
    var status: StudyStatus?

    /// A status older than this means the friend has gone quiet.
    static let statusLifetime: TimeInterval = 150

    func isOnline(at now: Date = Date(), connected: Bool) -> Bool {
        guard connected, let status else { return false }
        return now.timeIntervalSince(status.sentAt) < Self.statusLifetime
    }
}

// MARK: - Things to share

nonisolated enum StudySharedItem: Codable, Equatable, Sendable {
    case note(title: String, markdown: String)
    /// A drawing as its text description (flow, plot, 3D scene or ready-made model).
    case drawing(title: String, source: String)
    case cards(subject: String, cards: [SharedCard])

    struct SharedCard: Codable, Equatable, Sendable {
        var front: String
        var back: String
    }

    var kindTitle: String {
        switch self {
        case .note: return "Note"
        case .drawing(_, let source):
            let lowered = source.lowercased()
            return lowered.contains("type: model") || lowered.contains("type: scene3d") ? "3D model" : "Drawing"
        case .cards(_, let cards): return "\(cards.count) \(cards.count == 1 ? "flashcard" : "flashcards")"
        }
    }

    var title: String {
        switch self {
        case .note(let title, _): return title
        case .drawing(let title, _): return title
        case .cards(let subject, _): return subject
        }
    }
}

nonisolated struct StudyMessage: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var sentAt = Date()
    var text: String
    var attachment: StudySharedItem?
    /// Set on the sender's copy once the friend's Mac confirmed it arrived.
    var isDelivered = false
    /// Set on the receiver's copy once the conversation was opened.
    var isRead = false
}

// MARK: - What travels between two Macs

nonisolated enum StudyWire: Codable, Equatable, Sendable {
    /// First thing said on a connection: who I am and our shared token (empty with a new request).
    case hello(profile: StudyProfile, token: String)
    case status(StudyStatus)
    case message(StudyMessage)
    case delivered(messageID: UUID)
    /// "Study this with me": start the same focus session.
    case studyTogether(subject: String?, minutes: Int)
    case unfriend

    static let maximumBytes = 600_000

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(self), data.count <= Self.maximumBytes else { return nil }
        return data
    }

    /// Nil for anything too large or not understood, so a bad packet is simply dropped.
    static func decoded(_ data: Data) -> StudyWire? {
        guard data.count <= maximumBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(StudyWire.self, from: data)
    }
}

// MARK: - Rules

nonisolated enum StudySocial {
    static let maximumMessageCharacters = 4_000
    static let maximumNameCharacters = 40
    static let maximumSharedNoteCharacters = 120_000
    static let maximumSharedCards = 200
    static let maximumStoredMessages = 3_000

    /// A name as shown to friends: trimmed, one line, not empty.
    static func cleanedName(_ raw: String) -> String {
        let oneLine = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return String(oneLine.prefix(maximumNameCharacters))
    }

    static func cleanedMessageText(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumMessageCharacters))
    }

    /// What arrives from another Mac is cut to the same limits before it is kept or shown.
    static func sanitized(_ message: StudyMessage) -> StudyMessage {
        var clean = message
        clean.text = cleanedMessageText(message.text)
        switch message.attachment {
        case .note(let title, let markdown):
            clean.attachment = .note(title: String(cleanedName(title).prefix(80)), markdown: String(markdown.prefix(maximumSharedNoteCharacters)))
        case .drawing(let title, let source):
            clean.attachment = .drawing(title: String(cleanedName(title).prefix(80)), source: String(source.prefix(20_000)))
        case .cards(let subject, let cards):
            let kept = cards.prefix(maximumSharedCards).map {
                StudySharedItem.SharedCard(front: String($0.front.prefix(600)), back: String($0.back.prefix(1_500)))
            }
            clean.attachment = .cards(subject: cleanedName(subject), cards: Array(kept))
        case nil:
            break
        }
        clean.isDelivered = false
        clean.isRead = false
        return clean
    }

    /// A random token two friends agree on when the friendship is made.
    static func newToken() -> String {
        UUID().uuidString + UUID().uuidString
    }

    static func conversation(with friendID: UUID, in messages: [StudyMessage]) -> [StudyMessage] {
        messages.filter { $0.from == friendID || $0.to == friendID }.sorted { $0.sentAt < $1.sentAt }
    }

    static func unreadCount(from friendID: UUID, in messages: [StudyMessage]) -> Int {
        messages.filter { $0.from == friendID && !$0.isRead }.count
    }

    /// Friends in the order worth looking at: studying now first, then online, then by name.
    static func sorted(_ friends: [StudyFriend], connected: Set<UUID>, at now: Date = Date()) -> [StudyFriend] {
        func rank(_ friend: StudyFriend) -> Int {
            guard friend.isOnline(at: now, connected: connected.contains(friend.id)) else { return 2 }
            return friend.status?.isStudying == true ? 0 : 1
        }
        return friends.sorted { lhs, rhs in
            let (l, r) = (rank(lhs), rank(rhs))
            return l != r ? l < r : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// The description of one of the ready-made 3D models, as a shareable drawing.
    static func modelDrawingSource(_ modelID: String) -> String {
        "type: model\nmodel: \(modelID)"
    }

    static let sharedModels: [(id: String, title: String)] = [
        ("heart", "Human heart"), ("cell", "Animal cell"), ("engine", "Four-stroke engine"),
        ("dna", "DNA double helix"), ("atom", "Atom"), ("solar-system", "Solar system"),
    ]

    /// "just now", "5 min ago", "2 h ago", "3 d ago".
    static func agoLabel(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) h ago" }
        return "\(Int(seconds / 86_400)) d ago"
    }
}

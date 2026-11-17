//
//  StudySocialStore.swift
//  leanring-buddy
//
//  Friends, their live study status, and the conversations with them. Kept in JSON files on this
//  Mac; sent friend to friend through a StudySocialTransport (today the local network).
//
//  Off until the student turns it on. While on, the Mac is visible by name to others nearby who
//  also turned it on; status and messages go only to accepted friends who showed the shared token.
//

import AppKit
import Combine
import Foundation

@MainActor
final class StudySocialStore: ObservableObject {

    static let shared = StudySocialStore()
    static let showDrawingNotification = Notification.Name("ThambiShowSharedDrawing")

    struct NearbyPerson: Identifiable, Equatable {
        let id: UUID
        var name: String
    }

    struct FriendRequest: Identifiable, Equatable {
        let id: UUID
        var name: String
        var token: String
    }

    @Published private(set) var profile: StudyProfile
    @Published private(set) var isEnabled: Bool
    @Published private(set) var friends: [StudyFriend] = []
    @Published private(set) var messages: [StudyMessage] = []
    @Published private(set) var connected: Set<UUID> = []
    @Published private(set) var nearby: [NearbyPerson] = []
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var sentRequests: Set<UUID> = []
    /// "Asha invites you to focus on DBMS for 25 min".
    @Published var studyInvitation: (from: StudyFriend, subject: String?, minutes: Int)?
    /// The last drawing Thambi made on this Mac, so it can be shared.
    @Published var lastDrawing: (title: String, source: String)?

    private let transport: StudySocialTransport
    /// Friends who have shown the shared token on this connection.
    private var verified: Set<UUID> = []
    private var outgoingTokens: [UUID: String] = [:]
    private var statusTimer: Timer?
    /// When each friend's recent messages arrived, to stop a flood.
    private var recentArrivals: [UUID: [Date]] = [:]
    private static let maximumPendingRequests = 10
    private static let maximumMessagesPerMinute = 40
    private var observers: [NSObjectProtocol] = []

    private static let enabledKey = "studyFriendsEnabled"

    init(transport: StudySocialTransport? = nil) {
        self.transport = transport ?? NearbyTransport()
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if let data = try? Data(contentsOf: Self.file("profile.json")), let saved = try? JSONDecoder().decode(StudyProfile.self, from: data) {
            profile = saved
        } else {
            profile = StudyProfile(name: StudySocial.cleanedName(NSFullUserName().components(separatedBy: " ").first ?? ""))
        }
        if let data = try? Data(contentsOf: Self.file("friends.json")), let saved = try? JSONDecoder().decode([StudyFriend].self, from: data) { friends = saved }
        if let data = try? Data(contentsOf: Self.file("messages.json")), let saved = try? JSONDecoder().decode([StudyMessage].self, from: data) { messages = saved }
        self.transport.onEvent = { [weak self] event in self?.handle(event) }
        observers.append(NotificationCenter.default.addObserver(forName: StudyFocusTimer.changedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.broadcastStatus() }
        })
        if isEnabled { startTransport() }
    }

    // MARK: Storage

    nonisolated private static func file(_ name: String) -> URL {
        StudyLibraryStore.baseDirectory.appendingPathComponent("Friends", isDirectory: true).appendingPathComponent(name)
    }

    private func save<T: Encodable & Sendable>(_ value: T, to name: String) {
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: Self.file(name).deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(value) { try? data.write(to: Self.file(name), options: .atomic) }
        }
    }

    private func saveFriends() { save(friends, to: "friends.json") }
    private func saveMessages() {
        if messages.count > StudySocial.maximumStoredMessages { messages.removeFirst(messages.count - StudySocial.maximumStoredMessages) }
        save(messages, to: "messages.json")
    }

    // MARK: Turning it on

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled { startTransport() } else { stopTransport() }
    }

    func setName(_ rawName: String) {
        let name = StudySocial.cleanedName(rawName)
        guard !name.isEmpty, name != profile.name else { return }
        profile.name = name
        save(profile, to: "profile.json")
        if isEnabled { startTransport() }
    }

    private func startTransport() {
        save(profile, to: "profile.json")
        connected.removeAll()
        verified.removeAll()
        nearby.removeAll()
        transport.start(profile: profile)
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.broadcastStatus() }
        }
    }

    private func stopTransport() {
        statusTimer?.invalidate()
        statusTimer = nil
        transport.stop()
        connected.removeAll()
        verified.removeAll()
        nearby.removeAll()
        incomingRequests.removeAll()
        sentRequests.removeAll()
    }

    // MARK: My status

    /// What friends see: the subject and how long, never the content.
    var myStatus: StudyStatus {
        let timer = StudyFocusTimer.shared
        let progress = StudyProgressStore.shared
        var status = StudyStatus(minutesToday: progress.minutesToday, streakDays: progress.streak.current)
        if timer.isRunning {
            status.activity = .focusing
            status.subject = timer.subject
            status.startedAt = timer.startedAt ?? Date()
            status.endsAt = timer.endsAt
        } else if StudyPracticeStore.shared.quiz != nil {
            status.activity = .practising
            status.subject = StudyPracticeStore.shared.quiz?.title
        }
        return status
    }

    func broadcastStatus() {
        guard isEnabled, let data = StudyWire.status(myStatus).encoded() else { return }
        for id in verified { transport.send(data, to: id) }
    }

    // MARK: Friends

    func friend(_ id: UUID) -> StudyFriend? { friends.first { $0.id == id } }

    var sortedFriends: [StudyFriend] { StudySocial.sorted(friends, connected: connected) }

    func isOnline(_ friend: StudyFriend) -> Bool { friend.isOnline(connected: verified.contains(friend.id)) }

    /// People nearby who are not friends yet.
    var nearbyStrangers: [NearbyPerson] {
        nearby.filter { person in !friends.contains { $0.id == person.id } }
    }

    func sendFriendRequest(to person: NearbyPerson) {
        let token = StudySocial.newToken()
        outgoingTokens[person.id] = token
        sentRequests.insert(person.id)
        transport.invite(person.id, hello: StudyWire.hello(profile: profile, token: token).encoded())
    }

    func answer(_ request: FriendRequest, accept: Bool) {
        incomingRequests.removeAll { $0.id == request.id }
        if accept {
            friends.removeAll { $0.id == request.id }
            friends.append(StudyFriend(id: request.id, name: request.name, token: request.token))
            saveFriends()
        }
        transport.answerInvitation(from: request.id, accept: accept)
    }

    func remove(_ friend: StudyFriend) {
        if let data = StudyWire.unfriend.encoded() { transport.send(data, to: friend.id) }
        transport.disconnect(friend.id)
        friends.removeAll { $0.id == friend.id }
        messages.removeAll { $0.from == friend.id || $0.to == friend.id }
        verified.remove(friend.id)
        connected.remove(friend.id)
        saveFriends()
        saveMessages()
    }

    // MARK: Messages

    func conversation(with friendID: UUID) -> [StudyMessage] { StudySocial.conversation(with: friendID, in: messages) }
    func unreadCount(from friendID: UUID) -> Int { StudySocial.unreadCount(from: friendID, in: messages) }
    var totalUnread: Int { messages.filter { $0.from != profile.id && !$0.isRead }.count }

    func markRead(_ friendID: UUID) {
        var changed = false
        for index in messages.indices where messages[index].from == friendID && !messages[index].isRead {
            messages[index].isRead = true
            changed = true
        }
        if changed { saveMessages() }
    }

    /// Sends now if the friend is connected; otherwise it waits and goes when they next connect.
    func send(_ rawText: String, attachment: StudySharedItem? = nil, to friendID: UUID) {
        let text = StudySocial.cleanedMessageText(rawText)
        guard !text.isEmpty || attachment != nil else { return }
        let message = StudyMessage(from: profile.id, to: friendID, text: text, attachment: attachment)
        messages.append(message)
        saveMessages()
        deliver(message)
    }

    private func deliver(_ message: StudyMessage) {
        guard verified.contains(message.to), let data = StudyWire.message(message).encoded() else { return }
        transport.send(data, to: message.to)
    }

    private func deliverWaitingMessages(to friendID: UUID) {
        for message in messages where message.to == friendID && message.from == profile.id && !message.isDelivered {
            deliver(message)
        }
    }

    func inviteToStudy(_ friendID: UUID, subject: String?, minutes: Int) {
        if let data = StudyWire.studyTogether(subject: subject, minutes: minutes).encoded() { transport.send(data, to: friendID) }
        StudyFocusTimer.shared.start(minutes: minutes, subject: subject)
        send("Let's focus\(subject.map { " on \($0)" } ?? "") for \(minutes) min. I've started.", to: friendID)
    }

    func acceptStudyInvitation() {
        guard let invitation = studyInvitation else { return }
        StudyFocusTimer.shared.start(minutes: invitation.minutes, subject: invitation.subject)
        send("I'm in. Starting now.", to: invitation.from.id)
        studyInvitation = nil
    }

    // MARK: Using what a friend shared

    func saveSharedNote(title: String, markdown: String) {
        _ = StudyLibraryStore.shared.saveNote(title: title, markdown: markdown.hasPrefix("# ") ? markdown : "# \(title)\n\n\(markdown)")
    }

    func addSharedCards(subject: String, cards: [StudySharedItem.SharedCard]) -> Int {
        let practice = StudyPracticeStore.shared
        practice.loadIfNeeded()
        let before = practice.cards.count
        for card in cards {
            practice.addCard(StudyCard(front: card.front, back: card.back, subject: subject, origin: .typed))
        }
        return practice.cards.count - before
    }

    func openSharedDrawing(source: String) {
        NotificationCenter.default.post(name: Self.showDrawingNotification, object: nil, userInfo: ["source": source])
    }

    // MARK: What arrives

    private func handle(_ event: StudyTransportEvent) {
        switch event {
        case .found(let id, let rawName):
            let name = StudySocial.cleanedName(rawName)
            nearby.removeAll { $0.id == id }
            nearby.append(NearbyPerson(id: id, name: name.isEmpty ? "Someone" : name))
            // Between friends the one with the smaller id calls, so they don't both call at once.
            if let friend = friend(id), !connected.contains(id), profile.id.uuidString < id.uuidString {
                transport.invite(id, hello: StudyWire.hello(profile: profile, token: friend.token).encoded())
            }
        case .lost(let id):
            nearby.removeAll { $0.id == id }
        case .invited(let id, let helloData):
            guard let helloData, case .hello(let theirProfile, let token)? = StudyWire.decoded(helloData), theirProfile.id == id else {
                transport.answerInvitation(from: id, accept: false)
                return
            }
            if let friend = friend(id) {
                transport.answerInvitation(from: id, accept: friend.token == token)
            } else if token.count >= 36, token.count <= 200, incomingRequests.count < Self.maximumPendingRequests || incomingRequests.contains(where: { $0.id == id }) {
                incomingRequests.removeAll { $0.id == id }
                incomingRequests.append(FriendRequest(id: id, name: StudySocial.cleanedName(theirProfile.name), token: token))
            } else {
                transport.answerInvitation(from: id, accept: false)
            }
        case .connected(let id):
            connected.insert(id)
            // My request was accepted: the friendship starts with the token I proposed.
            if friend(id) == nil, let token = outgoingTokens.removeValue(forKey: id) {
                let name = nearby.first { $0.id == id }?.name ?? "Friend"
                friends.append(StudyFriend(id: id, name: name, token: token))
                sentRequests.remove(id)
                saveFriends()
            }
            if let friend = friend(id), let data = StudyWire.hello(profile: profile, token: friend.token).encoded() {
                transport.send(data, to: id)
            }
        case .disconnected(let id):
            connected.remove(id)
            verified.remove(id)
            sentRequests.remove(id)
            outgoingTokens[id] = nil
        case .received(let data, let id):
            guard let wire = StudyWire.decoded(data) else { return }
            receive(wire, from: id)
        }
    }

    private func receive(_ wire: StudyWire, from id: UUID) {
        guard let index = friends.firstIndex(where: { $0.id == id }) else { return }
        if case .hello(let theirProfile, let token) = wire {
            guard theirProfile.id == id, token == friends[index].token else { return }
            verified.insert(id)
            let name = StudySocial.cleanedName(theirProfile.name)
            if !name.isEmpty, name != friends[index].name { friends[index].name = name }
            friends[index].lastSeen = Date()
            saveFriends()
            if let data = StudyWire.status(myStatus).encoded() { transport.send(data, to: id) }
            deliverWaitingMessages(to: id)
            return
        }
        // Everything else counts only from a friend who has shown the token.
        guard verified.contains(id) else { return }
        switch wire {
        case .hello:
            break
        case .status(var status):
            status.sentAt = Date()
            status.subject = status.subject.map { String(StudySocial.cleanedName($0).prefix(60)) }
            friends[index].status = status
            friends[index].lastSeen = Date()
        case .message(let incoming):
            guard incoming.from == id, incoming.to == profile.id, !messages.contains(where: { $0.id == incoming.id }) else {
                if let data = StudyWire.delivered(messageID: incoming.id).encoded() { transport.send(data, to: id) }
                return
            }
            // A friend's Mac that sends far too fast is ignored until it slows down.
            let now = Date()
            let arrivals = (recentArrivals[id] ?? []).filter { now.timeIntervalSince($0) < 60 }
            guard arrivals.count < Self.maximumMessagesPerMinute else { return }
            recentArrivals[id] = arrivals + [now]
            messages.append(StudySocial.sanitized(incoming))
            saveMessages()
            if let data = StudyWire.delivered(messageID: incoming.id).encoded() { transport.send(data, to: id) }
            if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        case .delivered(let messageID):
            if let messageIndex = messages.firstIndex(where: { $0.id == messageID && $0.to == id }) {
                messages[messageIndex].isDelivered = true
                saveMessages()
            }
        case .studyTogether(let subject, let minutes):
            guard (5...180).contains(minutes) else { return }
            studyInvitation = (friends[index], subject.map { String(StudySocial.cleanedName($0).prefix(60)) }, minutes)
        case .unfriend:
            let friend = friends[index]
            friends.remove(at: index)
            verified.remove(friend.id)
            transport.disconnect(friend.id)
            saveFriends()
        }
    }
}

//
//  FriendsPage.swift
//  leanring-buddy
//
//  Study with friends: who is studying right now, a conversation with each friend, and sharing
//  notes, flashcards, drawings and 3D models so you can teach each other.
//

import SwiftUI

struct FriendsPage: View {
    @ObservedObject var social: StudySocialStore
    @ObservedObject var library: StudyLibraryStore
    @ObservedObject var practice: StudyPracticeStore

    @State private var selectedFriendID: UUID?
    @State private var draftName = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Friends", subtitle: subtitle) {
                if social.isEnabled {
                    Toggle("Study with friends", isOn: Binding(get: { social.isEnabled }, set: { social.setEnabled($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(DS.Colors.cool)
                        .help("Turn off to stop being visible and stop sharing your status")
                }
            }
            if social.isEnabled {
                HStack(spacing: 0) {
                    peopleColumn.frame(width: 290)
                    Rectangle().fill(DS.Colors.borderSubtle).frame(width: 1)
                    if let friend = social.friend(selectedFriendID ?? UUID()) {
                        ConversationView(friend: friend, social: social, library: library, practice: practice)
                            .id(friend.id)
                    } else {
                        noConversation
                    }
                }
                .overlay(Rectangle().strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous))
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            } else {
                welcome
            }
        }
        .onAppear {
            draftName = social.profile.name
            if selectedFriendID == nil { selectedFriendID = social.sortedFriends.first?.id }
        }
        .onChange(of: social.friends.count) { _, _ in
            if social.friend(selectedFriendID ?? UUID()) == nil { selectedFriendID = social.sortedFriends.first?.id }
        }
    }

    private var subtitle: String {
        guard social.isEnabled else { return "Off. Nothing about you is visible or shared." }
        let studying = social.friends.filter { social.isOnline($0) && $0.status?.isStudying == true }.count
        if studying > 0 { return "\(studying) \(studying == 1 ? "friend is" : "friends are") studying right now" }
        return "Visible as \(social.profile.name) to people nearby who also turned this on"
    }

    // MARK: Off

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(DS.Colors.cool)
            Text("Study with friends")
                .font(DS.font(22, .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            Text("See when friends are studying, message them, start a focus session together, and send notes, flashcards and 3D models to explain things to each other.")
                .font(DS.font(14))
                .foregroundColor(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 8) {
                TextField("Your name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(DS.font(14))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(width: 200, height: 32)
                    .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(DS.Colors.well))
                    .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).strokeBorder(DS.Colors.borderStrong, lineWidth: 1))
                    .onSubmit(turnOn)
                    .accessibilityLabel("Your name, as friends will see it")
                WindowButton(title: "Turn on", prominence: .primary, isEnabled: !StudySocial.cleanedName(draftName).isEmpty, action: turnOn)
            }
            .padding(.top, 6)
            Text("Works between Macs on the same Wi-Fi, directly and encrypted, with no account and no server. Friends see your name, the subject you are studying and for how long. Never your screen, notes or questions.")
                .font(DS.font(12))
                .foregroundColor(DS.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private func turnOn() {
        guard !StudySocial.cleanedName(draftName).isEmpty else { return }
        social.setName(draftName)
        social.setEnabled(true)
    }

    // MARK: People

    private var peopleColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if !social.incomingRequests.isEmpty {
                    sectionTitle("Requests")
                    ForEach(social.incomingRequests) { request in
                        HStack(spacing: 10) {
                            FriendAvatar(name: request.name, id: request.id, isOnline: true)
                            Text("\(request.name) wants to study with you")
                                .font(DS.font(13))
                                .foregroundColor(DS.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 10)
                        HStack(spacing: 8) {
                            WindowButton(title: "Accept", prominence: .primary) {
                                social.answer(request, accept: true)
                                selectedFriendID = request.id
                            }
                            WindowButton(title: "Decline") { social.answer(request, accept: false) }
                        }
                        .padding(.leading, 56)
                        .padding(.bottom, 8)
                    }
                }

                sectionTitle("Friends")
                if social.friends.isEmpty {
                    Text("No friends yet. Ask a friend on the same Wi-Fi to open Friends in Thambi; they will appear under Nearby.")
                        .font(DS.font(12))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
                ForEach(social.sortedFriends) { friend in
                    FriendRow(friend: friend, isOnline: social.isOnline(friend), unread: social.unreadCount(from: friend.id), isSelected: selectedFriendID == friend.id) {
                        selectedFriendID = friend.id
                    }
                    .contextMenu {
                        Button("Remove friend", role: .destructive) { social.remove(friend) }
                    }
                }

                sectionTitle("Nearby")
                if social.nearbyStrangers.isEmpty {
                    Text("Looking for people on this Wi-Fi who have Friends turned on.")
                        .font(DS.font(12))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }
                ForEach(social.nearbyStrangers) { person in
                    HStack(spacing: 10) {
                        FriendAvatar(name: person.name, id: person.id, isOnline: true)
                        Text(person.name)
                            .font(DS.font(13))
                            .foregroundColor(DS.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if social.sentRequests.contains(person.id) {
                            Text("Asked")
                                .font(DS.font(12))
                                .foregroundColor(DS.Colors.textTertiary)
                        } else {
                            WindowButton(title: "Add") { social.sendFriendRequest(to: person) }
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                }
            }
            .padding(8)
        }
        .background(DS.Colors.surface1)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DS.font(12, .medium))
            .foregroundColor(DS.Colors.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var noConversation: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(DS.Colors.textTertiary)
            Text(social.friends.isEmpty ? "Add a friend to start" : "Choose a friend")
                .font(DS.font(16, .semibold))
                .foregroundColor(DS.Colors.textPrimary)
            Text("Messages and what you share go straight to your friend's Mac.")
                .font(DS.font(13))
                .foregroundColor(DS.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.background)
    }
}

// MARK: - Rows

struct FriendAvatar: View {
    let name: String
    let id: UUID
    let isOnline: Bool
    var size: CGFloat = 34

    private var color: Color {
        let palette = [DS.Colors.cool, DS.Colors.accent, DS.Colors.success, DS.Colors.coolDeep, DS.Colors.warning]
        return palette[Int(id.uuid.0) % palette.count]
    }

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(DS.font(size * 0.42, .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(isOnline ? DS.Colors.success : DS.Colors.textTertiary)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().strokeBorder(DS.Colors.surface1, lineWidth: 2))
                    .accessibilityLabel(isOnline ? "Online" : "Offline")
            }
    }
}

private struct FriendRow: View {
    let friend: StudyFriend
    let isOnline: Bool
    let unread: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var statusLine: String {
        if isOnline, let status = friend.status { return status.line() }
        if let lastSeen = friend.lastSeen { return "Seen \(StudySocial.agoLabel(lastSeen))" }
        return "Not connected"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FriendAvatar(name: friend.name, id: friend.id, isOnline: isOnline)
                VStack(alignment: .leading, spacing: 1) {
                    Text(friend.name)
                        .font(DS.font(13, isSelected || unread > 0 ? .semibold : .medium))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(DS.font(12))
                        .foregroundColor(isOnline && friend.status?.isStudying == true ? DS.Colors.cool : DS.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.Colors.textOnAccent)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(DS.Colors.accent))
                        .accessibilityLabel("\(unread) unread")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: DS.CornerRadius.small, style: .continuous).fill(isSelected ? DS.Colors.surface3 : (isHovered ? DS.Colors.surface2 : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

// MARK: - Conversation

private struct ConversationView: View {
    let friend: StudyFriend
    @ObservedObject var social: StudySocialStore
    @ObservedObject var library: StudyLibraryStore
    @ObservedObject var practice: StudyPracticeStore

    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    private var isOnline: Bool { social.isOnline(friend) }
    private var messages: [StudyMessage] { social.conversation(with: friend.id) }
    private var cardSubjects: [String] { Array(Set(practice.cards.map(\.subject))).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DS.Colors.borderSubtle).frame(height: 1)
            if let invitation = social.studyInvitation, invitation.from.id == friend.id {
                HStack(spacing: 10) {
                    Image(systemName: "timer").foregroundColor(DS.Colors.cool)
                    Text("\(friend.name) invites you to focus\(invitation.subject.map { " on \($0)" } ?? "") for \(invitation.minutes) min")
                        .font(DS.font(13, .medium))
                        .foregroundColor(DS.Colors.textPrimary)
                    Spacer()
                    WindowButton(title: "Join", prominence: .primary) { social.acceptStudyInvitation() }
                    WindowButton(title: "Not now") { social.studyInvitation = nil }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DS.Colors.coolSubtle)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            Text("Say hello, or share a note or a 3D model to explain something.")
                                .font(DS.font(13))
                                .foregroundColor(DS.Colors.textTertiary)
                                .padding(.top, 40)
                        }
                        ForEach(messages) { message in
                            MessageBubble(message: message, isMine: message.from == social.profile.id, social: social)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    social.markRead(friend.id)
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: messages.count) { _, _ in
                    social.markRead(friend.id)
                    if let last = messages.last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            composer
        }
        .background(DS.Colors.background)
        .onAppear { isComposerFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            FriendAvatar(name: friend.name, id: friend.id, isOnline: isOnline)
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.name)
                    .font(DS.font(15, .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(isOnline ? (friend.status?.line() ?? "Online") : "Not connected. Messages are sent when you are both on the same Wi-Fi.")
                    .font(DS.font(12))
                    .foregroundColor(isOnline && friend.status?.isStudying == true ? DS.Colors.cool : DS.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if isOnline, let status = friend.status, status.minutesToday > 0 || status.streakDays > 0 {
                Text("\(StudyTimerRules.durationLabel(minutes: status.minutesToday)) today, \(status.streakDays) day streak")
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            Menu {
                ForEach(StudyTimerRules.focusChoices, id: \.self) { minutes in
                    Button("Focus together for \(minutes) min") {
                        social.inviteToStudy(friend.id, subject: StudyFocusTimer.shared.subject, minutes: minutes)
                    }
                }
            } label: {
                Label("Study together", systemImage: "timer")
                    .font(DS.font(13, .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!isOnline)
            .help(isOnline ? "Start the same focus session on both Macs" : "Your friend is not connected")
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Menu("Share a note") {
                    if library.notes.isEmpty { Text("No notes yet") }
                    ForEach(library.notes.prefix(30)) { note in
                        Button(note.title) {
                            social.send("", attachment: .note(title: note.title, markdown: library.noteText(for: note)), to: friend.id)
                        }
                    }
                }
                Menu("Share flashcards") {
                    if cardSubjects.isEmpty { Text("No flashcards yet") }
                    ForEach(cardSubjects, id: \.self) { subject in
                        let cards = practice.cards(subject: subject).prefix(StudySocial.maximumSharedCards)
                        Button("\(subject) (\(cards.count))") {
                            social.send("", attachment: .cards(subject: subject, cards: cards.map { .init(front: $0.front, back: $0.back) }), to: friend.id)
                        }
                    }
                }
                Menu("Share a 3D model") {
                    ForEach(StudySocial.sharedModels, id: \.id) { model in
                        Button(model.title) {
                            social.send("", attachment: .drawing(title: model.title, source: StudySocial.modelDrawingSource(model.id)), to: friend.id)
                        }
                    }
                }
                if let drawing = social.lastDrawing {
                    Button("Share Thambi's last drawing (\(drawing.title))") {
                        social.send("", attachment: .drawing(title: drawing.title, source: drawing.source), to: friend.id)
                    }
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 17))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30, height: 34)
            .help("Share a note, flashcards, a drawing or a 3D model")
            .accessibilityLabel("Share")

            TextField("Message \(friend.name)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.font(14))
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).fill(DS.Colors.well))
                .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous).strokeBorder(isComposerFocused ? DS.Colors.cool : DS.Colors.borderStrong, lineWidth: 1))
            WindowButton(title: "Send", prominence: .primary, isEnabled: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: send)
        }
        .padding(12)
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        social.send(draft, to: friend.id)
        draft = ""
    }
}

private struct MessageBubble: View {
    let message: StudyMessage
    let isMine: Bool
    @ObservedObject var social: StudySocialStore

    @State private var resultLine: String?

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 70) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if let attachment = message.attachment { attachmentCard(attachment) }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(DS.font(14))
                        .foregroundColor(isMine ? .white : DS.Colors.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous).fill(isMine ? DS.Colors.coolDeep : DS.Colors.surface2))
                }
                Text(footer)
                    .font(DS.font(11))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            if !isMine { Spacer(minLength: 70) }
        }
    }

    private var footer: String {
        let time = message.sentAt.formatted(.dateTime.hour().minute())
        guard isMine else { return time }
        return message.isDelivered ? "\(time), delivered" : "\(time), waiting to send"
    }

    private func attachmentCard(_ item: StudySharedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon(item))
                    .font(.system(size: 14))
                    .foregroundColor(DS.Colors.cool)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(DS.font(13, .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(1)
                    Text(item.kindTitle)
                        .font(DS.font(12))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }
            if case .note(_, let markdown) = item {
                Text(NotesMarkdown.plainText(from: markdown).prefix(160))
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .lineLimit(3)
            }
            if case .cards(_, let cards) = item, let first = cards.first {
                Text(first.front)
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .lineLimit(2)
            }
            if let resultLine {
                Text(resultLine)
                    .font(DS.font(12))
                    .foregroundColor(DS.Colors.success)
            } else {
                switch item {
                case .note(let title, let markdown):
                    if !isMine {
                        WindowButton(title: "Save to my notes", systemImage: "square.and.arrow.down") {
                            social.saveSharedNote(title: title, markdown: markdown)
                            resultLine = "Saved to My notes"
                        }
                    }
                case .drawing(_, let source):
                    WindowButton(title: "Open", systemImage: "cube") { social.openSharedDrawing(source: source) }
                case .cards(let subject, let cards):
                    if !isMine {
                        WindowButton(title: "Add to my flashcards", systemImage: "plus") {
                            let added = social.addSharedCards(subject: subject, cards: cards)
                            resultLine = added == 0 ? "You already have these" : "Added \(added) \(added == 1 ? "card" : "cards")"
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous).fill(DS.Colors.surface1))
        .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous).strokeBorder(DS.Colors.borderSubtle, lineWidth: 1))
    }

    private func icon(_ item: StudySharedItem) -> String {
        switch item {
        case .note: return "note.text"
        case .drawing: return "cube"
        case .cards: return "rectangle.on.rectangle"
        }
    }
}

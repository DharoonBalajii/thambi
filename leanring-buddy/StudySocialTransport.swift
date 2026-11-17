//
//  StudySocialTransport.swift
//  leanring-buddy
//
//  How friends' Macs reach each other. `StudySocialTransport` is the seam: the app only knows
//  "people nearby", "connected" and "data arrived". `NearbyTransport` fills it in with Apple's
//  MultipeerConnectivity, which links Macs on the same Wi-Fi (a hostel, a classroom, a library)
//  directly and encrypted, with no server and no account. A backend can be added later as
//  another transport without changing the rest.
//

import Foundation
import MultipeerConnectivity

enum StudyTransportEvent {
    case found(id: UUID, name: String)
    case lost(id: UUID)
    /// Someone asks to connect; `hello` is what they sent along.
    case invited(id: UUID, hello: Data?)
    case connected(id: UUID)
    case disconnected(id: UUID)
    case received(Data, from: UUID)
}

@MainActor
protocol StudySocialTransport: AnyObject {
    var onEvent: ((StudyTransportEvent) -> Void)? { get set }
    func start(profile: StudyProfile)
    func stop()
    func invite(_ id: UUID, hello: Data?)
    func answerInvitation(from id: UUID, accept: Bool)
    @discardableResult func send(_ data: Data, to id: UUID) -> Bool
    func disconnect(_ id: UUID)
}

@MainActor
final class NearbyTransport: NSObject, StudySocialTransport {
    static let serviceType = "thambi-study"

    var onEvent: ((StudyTransportEvent) -> Void)?

    private var myPeer: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peers: [UUID: MCPeerID] = [:]
    private var invitationHandlers: [UUID: (Bool, MCSession?) -> Void] = [:]

    func start(profile: StudyProfile) {
        stop()
        // The peer name is the profile's id; the readable name travels in the discovery info.
        let peer = MCPeerID(displayName: profile.id.uuidString)
        let newSession = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        newSession.delegate = self
        let newAdvertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["name": profile.name], serviceType: Self.serviceType)
        newAdvertiser.delegate = self
        let newBrowser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        newBrowser.delegate = self
        myPeer = peer
        session = newSession
        advertiser = newAdvertiser
        browser = newBrowser
        newAdvertiser.startAdvertisingPeer()
        newBrowser.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        myPeer = nil
        peers.removeAll()
        for handler in invitationHandlers.values { handler(false, nil) }
        invitationHandlers.removeAll()
    }

    func invite(_ id: UUID, hello: Data?) {
        guard let peer = peers[id], let session, !session.connectedPeers.contains(peer) else { return }
        browser?.invitePeer(peer, to: session, withContext: hello, timeout: 60)
    }

    func answerInvitation(from id: UUID, accept: Bool) {
        guard let handler = invitationHandlers.removeValue(forKey: id) else { return }
        handler(accept, accept ? session : nil)
    }

    @discardableResult
    func send(_ data: Data, to id: UUID) -> Bool {
        guard let peer = peers[id], let session, session.connectedPeers.contains(peer) else { return false }
        return (try? session.send(data, toPeers: [peer], with: .reliable)) != nil
    }

    func disconnect(_ id: UUID) {
        guard let peer = peers[id] else { return }
        session?.cancelConnectPeer(peer)
    }

    /// Delegate calls arrive on other threads; everything is handled on the main one.
    nonisolated private func onMain(_ peerID: MCPeerID, _ work: @escaping @MainActor (NearbyTransport, UUID, MCPeerID) -> Void) {
        guard let id = UUID(uuidString: peerID.displayName) else { return }
        nonisolated(unsafe) let peer = peerID
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                work(self, id, peer)
            }
        }
    }
}

extension NearbyTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let name = info?["name"] ?? "Someone"
        onMain(peerID) { transport, id, peer in
            guard peer != transport.myPeer else { return }
            transport.peers[id] = peer
            transport.onEvent?(.found(id: id, name: name))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        onMain(peerID) { transport, id, _ in transport.onEvent?(.lost(id: id)) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("👥 Friends: could not look for people nearby (\((error as NSError).code))")
    }
}

extension NearbyTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let handler = invitationHandler
        onMain(peerID) { transport, id, peer in
            transport.peers[id] = peer
            transport.invitationHandlers[id]?(false, nil)
            transport.invitationHandlers[id] = handler
            transport.onEvent?(.invited(id: id, hello: context))
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("👥 Friends: could not become visible nearby (\((error as NSError).code))")
    }
}

extension NearbyTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard state != .connecting else { return }
        let isConnected = state == .connected
        onMain(peerID) { transport, id, peer in
            transport.peers[id] = peer
            transport.onEvent?(isConnected ? .connected(id: id) : .disconnected(id: id))
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onMain(peerID) { transport, id, _ in transport.onEvent?(.received(data, from: id)) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

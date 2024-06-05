//
//  SignalClient.swift
//  WebRTC
//
//  Created by Stasel on 20/05/2018.
//  Copyright © 2018 Stasel. All rights reserved.
//

import Foundation
import WebRTC

protocol SignalClientDelegate: AnyObject {
    func signalClientDidConnect(_ signalClient: SignalingClient)
    func signalClientDidDisconnect(_ signalClient: SignalingClient)
    func signalClient(_ signalClient: SignalingClient, didReceiveRemoteSdp sdp: RTCSessionDescription)
    func signalClient(_ signalClient: SignalingClient, didReceiveCandidate candidate: RTCIceCandidate)
}

final class SignalingClient {
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let webSocket: WebSocketProvider
    weak var delegate: SignalClientDelegate?
    
    init(url: URL) {
        
        if #available(iOS 13.0, *) {
            self.webSocket = NativeWebSocket(url: url)
        } else {
            self.webSocket = StarscreamWebSocket(url: url)
        }
        if #available(iOS 13.0, *) {
            let x = self.getAddress(url: url)
            print("addy is ", x)
        } else {
            // Fallback on earlier versions
        }
    }
    
    @available(iOS 13.0, *)
    func getAddress(url: URL) -> String {
        
            //var uniqueID = ""
            let options = PeerJSOption(host: "videochat-signaling-app.ue.r.appspot.com",
                                       port: 443,
                                       path: "/",
                                       key: "your_key_here",
                                       secure: true)
            
        let api = API(options: options, url: url)
        print(api.self)
        Task {
            await api.getAddress(url:url) { newUrl, error in
                if let error = error {
                                print("Error retrieving address: \(error)")
                                // Handle the error in your API (e.g., return an error response)
                            } else if let newUrl = newUrl {
                                // Use the new URL in your API logic
                                print("Received new URL from getAddress: \(newUrl)")
                                guard let url = URL(string: newUrl) else { return }
                                let socket = NativeWebSocket(url: url)

                                socket.connect()
                                

                            }
            }
        }
            
            //print("Unique ID OUTSIDE OF CODE IS ", uniqueID)
        return ""
    }
    
    
    func connect() {
        self.webSocket.delegate = self
        self.webSocket.connect()
    }
    
    func send(sdp rtcSdp: RTCSessionDescription) {
        let message = Message.sdp(SessionDescription(from: rtcSdp))
        do {
            let dataMessage = try self.encoder.encode(message)
            
            self.webSocket.send(data: dataMessage)
        }
        catch {
            debugPrint("Warning: Could not encode sdp: \(error)")
        }
    }
    
    func send(candidate rtcIceCandidate: RTCIceCandidate) {
        let message = Message.candidate(IceCandidate(from: rtcIceCandidate))
        do {
            let dataMessage = try self.encoder.encode(message)
            self.webSocket.send(data: dataMessage)
        }
        catch {
            debugPrint("Warning: Could not encode candidate: \(error)")
        }
    }
}


extension SignalingClient: WebSocketProviderDelegate {
    func webSocketDidConnect(_ webSocket: WebSocketProvider) {
        self.delegate?.signalClientDidConnect(self)
    }
    
    func webSocketDidDisconnect(_ webSocket: WebSocketProvider) {
        self.delegate?.signalClientDidDisconnect(self)
        
        // try to reconnect every two seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            debugPrint("Trying to reconnect to signaling server...")
            self.webSocket.connect()
        }
    }
    
    func webSocket(_ webSocket: WebSocketProvider, didReceiveData data: Data) {
        let message: Message
        do {
            message = try self.decoder.decode(Message.self, from: data)
        }
        catch {
            debugPrint("Warning: Could not decode incoming message: \(error)")
            return
        }
        
        switch message {
        case .candidate(let iceCandidate):
            self.delegate?.signalClient(self, didReceiveCandidate: iceCandidate.rtcIceCandidate)
        case .sdp(let sessionDescription):
            self.delegate?.signalClient(self, didReceiveRemoteSdp: sessionDescription.rtcSessionDescription)
        }

    }
}

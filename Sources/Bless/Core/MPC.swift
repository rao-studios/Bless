//
//  MPC.swift
//  Bless
//
//  Created by Ritesh Pakala Rao on 10/13/26.
//

import Foundation


/**********************************************
 
 
  --------------
 |              |
 |   Client 1   |
 |              |
  --------------
         |
         |
         | Exchange
         |
         |
  --------------
 |              |
 |   Client 2   |
 |              |
  --------------
 
 1) Can Client 1 exchange information with Client 2?
 2) When Client 2 receives information can it decode and understand it?
 
 ---
 
 - Which client holds a whitelist of whom can communicate with them and whom it can communicate to?
 - Is the decoder a standard or client based?
 
 
 public key
 private key systems
 
 A sent payload is hashed with Client 1's public key and Client 2's public key.
 - Client 2 receives the raw bytes uses its private key to decode step 1.
 -- Then sends the malformed back to Client 1, Client 1 accepts to decode with its private key, to send back the raw payload?
 --- This still means a man-in-the-middle can exist...
 
 
 high level:
 - We just want a payload that can only be read and decoded by a receiver, but the receiver should know who the sender is and when the sender will send it. While the sender is able to encode the payload 1-way for the receiver.
 -- Any form of interception is impossible to decode. In some form interception is baited for resilience.
 
 *********************************************/


/*
 Standard responses from both clients on decode objectives, client health,
 and payload metadata?
 */
struct Response {
    
}

/*
 Payloads need to be Data objects, encrypted bytes.
 - The Data object holds Machine Learning responses from chat bots initially.
 - Normal chat message patterns like a OpenAI-compatible response object.
 */
struct Payload {
    
}

protocol MPC {
    // func receive(_ payload: Payload) -> Response
    func send(_ payload: Payload) -> Response
}

struct AESKey {
    
}

protocol Handshake {
    func ask() -> AESKey
    func available(_ key: AESKey) -> Bool
}






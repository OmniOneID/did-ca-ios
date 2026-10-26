//
/*
 * Copyright 2026 OmniOne.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


import Foundation
import DIDWalletSDK

// MARK: - Holder DID document update flow (UpdateUser)
//
// After onboarding, with the holder DID document already published, this flow adds/removes the
// `#bio` verification method on the published document when BIO is turned on/off in settings.
//
// Core: `updateHolderDIDDocument` adds #bio to the in-memory document (if the key exists) or removes it
// (if not), and `createSignedDIDDoc(passcode:)` signs that updated document with the #pin key and submits it.
// The server accepts the update after verifying the owner of the published document signed with the PIN key.
//
// Flow (equivalent to campus-did-ca-ios UpdateUserProtocol):
//   [1] updateHolderDIDDocument   #bio addVerificationMethod on the in-memory document (remove if absent)
//   [2] propose-update-diddoc     receive txId / authNonce
//   [3] ECDH (.device)            derive sharedSecret
//   [4] request-server-token      hServerToken
//   [5] getSignedDidAuth(PIN)     sign authNonce with the #pin key
//   [6] createSignedDIDDoc(PIN)   sign the updated document with the #pin key
//   [7] request-update-diddoc     submit the signed document
//   [8] confirm-update-diddoc     confirm the update
//   [9] saveHolderDIDDocument     save the document locally
//
// On failure, roll back (deleteKeyPair) the bio key created in [1] so local/server state doesn't diverge.
nonisolated enum UpdateUserProtocol {

    /// Create the bio key + reflect #bio in the DID document. Entry point for Settings > Add Biometrics.
    /// generateBio throws biometric prompt failures as BiometricError(BIO-E) — the caller branches on it.
    static func addBioKey(passcode: String) async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .UPDATE_DID)
        try WalletKeys.generateBio(hWalletToken: hWalletToken)
        // After creating the key, get a fresh token for the document update (same as campusID — a new token per stage).
        let updateToken = try await TokenGenerator.requestWalletToken(purpose: .UPDATE_DID)
        try await update(hWalletToken: updateToken, passcode: passcode)
    }

    /// Delete the bio key + remove #bio from the DID document. (For turning BIO off in settings — UI wiring later.)
    static func deleteBioKey(passcode: String) async throws {
        let hWalletToken = try await TokenGenerator.requestWalletToken(purpose: .UPDATE_DID)
        try WalletAPI.shared.deleteKeyPair(hWalletToken: hWalletToken, keyId: KeyIdName.bio)
        try await update(hWalletToken: hWalletToken, passcode: passcode)
    }

    // MARK: - Shared update flow
    //
    // updateHolderDIDDocument internally branches add/remove via isKeySaved(bio),
    // so add/delete share the same flow.
    private static func update(hWalletToken: String, passcode: String) async throws {
        do {
            let didDoc = try WalletAPI.shared.getDidDocument(type: .HolderDidDocumnet)

            let propose = try await TASConnection.proposeUpdateDidDoc(did: didDoc.id)

            let sharedSecret = try await TokenGenerator.getSharedSecret(type: .device, txId: propose.txId)
            let hServerToken = try await TokenGenerator.requestServerToken(
                purpose: .UPDATE_DID,
                txId: propose.txId,
                sharedSecret: sharedSecret
            )

            let didAuth = try WalletAPI.shared.getSignedDidAuth(
                authNonce: propose.authNonce,
                passcode: passcode
            )
            
            let _ = try WalletAPI.shared.updateHolderDIDDocument(hWalletToken: hWalletToken)
            
            let signedDIDDoc = try WalletAPI.shared.createSignedDIDDoc(passcode: passcode)

            
            let response = try await WalletAPI.shared.requestUpdateUser(
                tasURL: URLs.TAS_URL + "/tas/api/v1/request-update-diddoc",
                txId: propose.txId,
                hWalletToken: hWalletToken,
                serverToken: hServerToken,
                didAuth: didAuth,
                signedDIDDoc: signedDIDDoc
            )

            try await TASConnection.confirmUpdateDidDoc(txId: response.txId, serverToken: hServerToken)
            try WalletAPI.shared.saveHolderDIDDocument()
        } catch {
            // On update failure, revert the bio key just created to avoid a local (key) / server (document) mismatch.
            // (Same as campus-did-ca-ios — based on the add path. Rolling back the delete path needs a key-restore API later.)
            if Biometrics.hasBioKey {
                try? WalletAPI.shared.deleteKeyPair(hWalletToken: hWalletToken, keyId: KeyIdName.bio)
            }
            throw error
        }
    }
}

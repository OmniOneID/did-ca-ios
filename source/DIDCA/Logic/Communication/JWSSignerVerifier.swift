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

enum JWSSignerError: Error {
    /// `kid` is not of the form `did:...?versionId=N#fragment` — the document version to verify against can't be determined.
    case invalidKeyIdentifier
    /// The DID Document has no verificationMethod for that fragment, or its public key can't be read.
    case unknownSigningKey
    /// The signature doesn't belong to that key.
    case signatureVerificationFailed
}

/// Verifies a JWS with **the public key in the signer's DID Document**.
///
/// SDK `JWS.verify()` (no arguments) verifies with the `jwk` in the header. That only guarantees "not tampered after signing"
/// and **does not guarantee who signed it** — because the requester puts the key in themselves.
/// The same holds even if a `kid` is in the header too: nobody checks whether that `jwk` is the key of the subject the `kid`
/// points to, so copying just the `kid` string and signing with one's own key passes as-is.
///
/// So here the `jwk` is **ignored**; we fetch the DID Document the `kid` points to and verify with the public key in it.
/// Identity only holds when the basis of trust lies outside the request (the DID registry).
/// The signature verification itself is done by SDK `JWS.verify(publicKey:)` — the entry point where the SDK leaves key
/// resolution and trust decisions to the caller.
nonisolated enum JWSSignerVerifier {

    /// Verify the signature via `kid` → DID Document → public key. Throws if it doesn't pass.
    ///
    /// - parameter jws: the JWS to verify.
    /// - parameter kid: the header's `kid`. Must be of the form `did:omn:issuer?versionId=1#assert`.
    static func verify(jws: JWS, kid: String) async throws {
        guard let identifier = parseKeyIdentifier(kid) else {
            throw JWSSignerError.invalidKeyIdentifier
        }

        // Always fetch the version the kid specifies — the latest may be a different key even with the same fragment.
        // A version-pinned document is immutable, so the resolver caches it indefinitely.
        let didDocument = try await DIDDocumentResolver.shared.resolve(did: identifier.did,
                                                                      versionId: identifier.versionId)
        guard let method = didDocument.verificationMethod.first(where: { $0.id == identifier.keyId }),
              let publicKey = try? MultibaseUtils.decode(encoded: method.publicKeyMultibase)
        else {
            throw JWSSignerError.unknownSigningKey
        }

        guard (try? jws.verify(publicKey: publicKey)) == true else {
            throw JWSSignerError.signatureVerificationFailed
        }
    }

    /// Identifier pointing to the signing key — the three pieces of `did:omn:issuer?versionId=1#assert`.
    /// A DID Document's verificationMethod.id holds only the fragment (`assert`).
    private struct KeyIdentifier {
        let did: String
        let versionId: String
        let keyId: String
    }

    /// kid parsing. **versionId is required** — without it the document version to verify can't be determined, so nil is returned
    /// and the caller fails instead of falling back to the latest. Same convention as SDK `DIDUtility.parseDIDKeyIdentifier`,
    /// but that one is internal, so the same parsing lives here.
    private static func parseKeyIdentifier(_ kid: String) -> KeyIdentifier? {
        let fragmentParts = kid.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard fragmentParts.count == 2 else { return nil }

        let versionParts = fragmentParts[0].components(separatedBy: "?versionId=")
        guard versionParts.count == 2 else { return nil }

        let identifier = KeyIdentifier(did: versionParts[0],
                                       versionId: versionParts[1],
                                       keyId: String(fragmentParts[1]))
        guard !identifier.did.isEmpty, !identifier.versionId.isEmpty, !identifier.keyId.isEmpty else {
            return nil
        }
        return identifier
    }
}

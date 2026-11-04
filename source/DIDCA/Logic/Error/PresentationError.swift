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

/// No credential available for presentation — shown as the "No available certificates" notice.
///
/// **The two cases are not distinguished** — not holding the requested credential at all, and holding it but
/// with 0 ACTIVE (all Inactive/Expired), are treated the same. The action the user should take differs by situation,
/// so we avoid asserting a cause.
///
/// Regular VP (`VerifyVcProtocol`) and OID4VP (`OID4VPPresenter`) throw the same thing, and the screen entry point
/// (`QRRouter`) turns it into a notice dialog in one place.
nonisolated struct NoSubmittableCredentialError: Error {
    static let title = "No available certificates"
    static let message = "You don't have a certificate that can be submitted for this request."
}

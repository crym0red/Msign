//
// SideSignIntegration.swift
// mSign / DELvEK
//
// SideSign is consumed as a pinned GPL-3.0 Swift Package.
// This file contains mSign-specific integration only; upstream SideSign
// source remains an external dependency.
//
// Upstream: https://github.com/SideStore/SideSign
// Pinned revision: 6b68651697f99791ef85404b7aea1891a26a285d
//

import Foundation
import SideSign

nonisolated struct SideSignCSR: Sendable {
    let csr: Data
    let privateKey: Data
}

/// mSign's narrow boundary around SideSign's certificate/PKCS#12 facilities.
/// Apple Developer Portal orchestration can be added here without coupling the
/// rest of the app to SideSign's internal types.
enum SideSignIntegration {
    static let upstreamURL = "https://github.com/SideStore/SideSign"
    static let pinnedRevision = "6b68651697f99791ef85404b7aea1891a26a285d"

    /// Creates a local private key and CSR. The private key never leaves this
    /// process unless the caller explicitly exports it.
    static func makeDevelopmentCSR(machineName: String = "mSign") throws -> SideSignCSR {
        let request = try CertificateRequest(machineName: machineName)
        return SideSignCSR(csr: request.csrData, privateKey: request.privateKey)
    }

    /// Parses a PKCS#12 archive and returns the certificate/private-key DER
    /// material only after the supplied password succeeds.
    static func extractPKCS12(_ data: Data, password: String) throws -> (certificateDER: Data, privateKeyDER: Data) {
        try PKCS12Parser.extract(data, password: password)
    }

    /// Reads certificate metadata using SideSign's X.509 parser.
    static func parseCertificate(_ certificateDER: Data) -> SideSignCertificateSummary? {
        guard let info = CertificateParser.parseCertificate(certificateDER) else { return nil }
        return SideSignCertificateSummary(
            name: info.name,
            serial: info.serial,
            expiryDate: info.expiryDate
        )
    }
}

nonisolated struct SideSignCertificateSummary: Sendable {
    let name: String
    let serial: String
    let expiryDate: Date?
}

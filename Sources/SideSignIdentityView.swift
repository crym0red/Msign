//
// SideSignIdentityView.swift
// mSign / DELvEK
//

import SwiftUI
import UniformTypeIdentifiers

struct SideSignIdentityView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var machineName = "mSign"
    @State private var csr: SideSignCSR?
    @State private var certificateSummary: SideSignCertificateSummary?
    @State private var status: String?
    @State private var showImporter = false
    @State private var p12Password = ""
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Development Identity") {
                    Text("SideSign supplies the local CSR and PKCS#12 tooling. mSign keeps generated private material local unless you explicitly export it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("Machine / identity name", text: $machineName)
                        .textInputAutocorrectionDisabled()

                    Button {
                        do {
                            csr = try SideSignIntegration.makeDevelopmentCSR(
                                machineName: machineName.isEmpty ? "mSign" : machineName
                            )
                            status = "CSR generated locally. The private key remains in memory until you explicitly persist/export it."
                        } catch {
                            status = error.localizedDescription
                        }
                    } label: {
                        Label("Generate Development CSR", systemImage: "key.fill")
                    }
                }

                if let csr {
                    Section("Generated CSR") {
                        LabeledContent("CSR", value: "\(csr.csr.count) bytes")
                        LabeledContent("Private key", value: "\(csr.privateKey.count) bytes")
                        ShareLink(item: csr.csr.base64EncodedString()) {
                            Label("Export CSR", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("Import / Validate .p12") {
                    SecureField("PKCS#12 password", text: $p12Password)
                    Button {
                        showImporter = true
                    } label: {
                        Label("Select .p12", systemImage: "doc.badge.plus")
                    }
                }

                if let info = certificateSummary {
                    Section("Certificate") {
                        LabeledContent("Name", value: info.name)
                        LabeledContent("Serial", value: info.serial)
                        if let date = info.expiryDate {
                            LabeledContent("Expires", value: date.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                if let status {
                    Section {
                        Text(status).font(.footnote)
                    }
                }
            }
            .navigationTitle("Development Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                do {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    let pair = try SideSignIntegration.extractPKCS12(data, password: p12Password)
                    guard let summary = SideSignIntegration.parseCertificate(pair.certificateDER) else {
                        throw NSError(domain: "mSign.SideSign", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "The certificate could not be parsed."])
                    }
                    certificateSummary = summary
                    status = "PKCS#12 parsed successfully. Certificate and private-key material were extracted as a matching pair."
                } catch {
                    certificateSummary = nil
                    status = "PKCS#12 validation failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

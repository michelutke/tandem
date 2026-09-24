import Foundation

setbuf(stdout, nil)

func tryKeygen(label: String, secureEnclave: Bool, dataProtectionKeychain: Bool) {
    let tag = "backing=\(secureEnclave ? "se" : "sw") dpk=\(dataProtectionKeychain)"
    do {
        let identity = try generateIdentity(label: label, secureEnclave: secureEnclave, persistent: true, dataProtectionKeychain: dataProtectionKeychain)
        print("HOST-RESULT \(tag) label=\(label) OK spki_sha256=\(hex(identity.spkiSha256))")
        cleanupIdentity(label: label)
    } catch {
        print("HOST-RESULT \(tag) label=\(label) FAILED error=\(error)")
        cleanupIdentity(label: label)
    }
}

// SE keys can only ever be created in the data-protection keychain (the main spike's
// `keygen --backing se --legacy-keychain` run gets OSStatus -50, "inconsistent private key
// parameters", when targeting a temporary/legacy keychain file instead) -- so the only
// configuration worth testing from a properly signed+provisioned app is the data-protection
// keychain path for both key backings.
print("HOST: se-identity-spike XcodeHost starting, pid=\(ProcessInfo.processInfo.processIdentifier)")
tryKeygen(label: "xcodehost-se-dpk", secureEnclave: true, dataProtectionKeychain: true)
tryKeygen(label: "xcodehost-sw-dpk", secureEnclave: false, dataProtectionKeychain: true)
print("HOST: done")

import Airgap

// Verify core API compiles and is callable.
Airgap.activate()
assert(Airgap.isActive)

Airgap.mode = .warn
Airgap.allowedHosts = ["localhost"]
Airgap.errorCode = -1009
Airgap.responseDelay = 0

Airgap.withConfiguration(mode: .fail, allowedHosts: ["example.com"]) {
    assert(Airgap.mode == .fail)
}

Airgap.deactivate()
assert(!Airgap.isActive)

print("Swift 6 consumer: all API checks passed")

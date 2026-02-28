import Airgap
import Foundation
import Testing

@Suite(.serialized)
struct TraitConfigurationTests {
    @Test(.airgapped(mode: .warn))
    func warnModeIsSet() {
        #expect(Airgap.mode == .warn)
    }

    @Test(.airgapped(allowedHosts: ["localhost"]))
    func allowedHostsAreSet() {
        #expect(Airgap.allowedHosts.contains("localhost"))
    }

    @Test(.airgapped(mode: .warn, allowedHosts: ["localhost", "127.0.0.1"]))
    func modeAndAllowedHostsTogether() {
        #expect(Airgap.mode == .warn)
        #expect(Airgap.allowedHosts.contains("localhost"))
        #expect(Airgap.allowedHosts.contains("127.0.0.1"))
    }
}

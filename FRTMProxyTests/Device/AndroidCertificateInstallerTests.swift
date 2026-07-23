import Testing
@testable import FRTMProxy

@Suite("AndroidCertificateInstaller.parseDevices")
struct AndroidCertificateInstallerTests {

    @Test("Riconosce un emulatore online")
    func singleEmulator() {
        let output = "List of devices attached\nemulator-5554\tdevice\n"
        let devices = AndroidCertificateInstaller.parseDevices(output)
        #expect(devices == [.init(serial: "emulator-5554", isEmulator: true)])
    }

    @Test("Distingue device fisici da emulatori")
    func physicalVsEmulator() {
        let output = """
        List of devices attached
        emulator-5554\tdevice
        R58M1234ABC\tdevice
        """
        let devices = AndroidCertificateInstaller.parseDevices(output)
        #expect(devices.count == 2)
        #expect(devices.first(where: { $0.serial == "emulator-5554" })?.isEmulator == true)
        #expect(devices.first(where: { $0.serial == "R58M1234ABC" })?.isEmulator == false)
    }

    @Test("Ignora device non pronti (offline/unauthorized) e header")
    func skipsNonReady() {
        let output = """
        List of devices attached
        emulator-5554\toffline
        emulator-5556\tunauthorized
        emulator-5558\tdevice
        """
        let devices = AndroidCertificateInstaller.parseDevices(output)
        #expect(devices == [.init(serial: "emulator-5558", isEmulator: true)])
    }

    @Test("Output vuoto → nessun device")
    func emptyOutput() {
        #expect(AndroidCertificateInstaller.parseDevices("List of devices attached\n\n").isEmpty)
        #expect(AndroidCertificateInstaller.parseDevices("").isEmpty)
    }
}

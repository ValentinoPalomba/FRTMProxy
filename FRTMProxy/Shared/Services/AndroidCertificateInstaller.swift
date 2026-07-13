import Foundation

struct AndroidCertificateInstaller {
    struct AndroidDevice: Sendable, Equatable {
        var serial: String
        var isEmulator: Bool
    }

    enum InstallerError: LocalizedError {
        case adbNotFound
        case noEmulators
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .adbNotFound:
                return """
                adb not found. Install Android platform-tools (Android Studio or `brew install android-platform-tools`), \
                or set ANDROID_HOME.
                """
            case .noEmulators:
                return "No running Android emulator found. Start an emulator (AOSP or Google APIs image) and try again."
            case .commandFailed(let reason):
                return "adb command failed: \(reason)"
            }
        }
    }

    func installOnEmulators() throws -> String {
        guard let adb = adbPath() else { throw InstallerError.adbNotFound }

        let emulators = try listDevices(adb: adb).filter(\.isEmulator)
        guard !emulators.isEmpty else { throw InstallerError.noEmulators }

        let loader = MitmproxyCertificateLoader()
        let pem = try loader.pemURL()
        let hash = try loader.subjectHashOld()

        let fileManager = FileManager.default
        let hashedURL = fileManager.temporaryDirectory.appendingPathComponent("\(hash).0")
        try? fileManager.removeItem(at: hashedURL)
        try fileManager.copyItem(at: pem, to: hashedURL)
        defer { try? fileManager.removeItem(at: hashedURL) }

        let remotePath = "/system/etc/security/cacerts/\(hash).0"
        var report: [String] = []

        for device in emulators {
            _ = ShellCommand.run(adb, ["-s", device.serial, "root"])
            let remount = ShellCommand.run(adb, ["-s", device.serial, "remount"])
            let push = ShellCommand.run(adb, ["-s", device.serial, "push", hashedURL.path, remotePath])

            if push.succeeded {
                _ = ShellCommand.run(adb, ["-s", device.serial, "shell", "chmod", "644", remotePath])
                report.append("\(device.serial): installed — reboot the emulator to apply.")
            } else {
                let hint = remount.succeeded
                    ? "Try `adb -s \(device.serial) shell avbctl disable-verification` then reboot (Android 10+)."
                    : "adb root/remount blocked — use an AOSP or Google APIs image (not Google Play), or install via Magisk."
                report.append("\(device.serial): failed — \(push.error.isEmpty ? remount.error : push.error). \(hint)")
            }
        }

        return report.joined(separator: "\n")
    }

    func adbPath() -> String? {
        var candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Android/sdk/platform-tools/adb").path,
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
        let environment = ProcessInfo.processInfo.environment
        if let home = environment["ANDROID_HOME"] {
            candidates.append(home + "/platform-tools/adb")
        }
        if let root = environment["ANDROID_SDK_ROOT"] {
            candidates.append(root + "/platform-tools/adb")
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func listDevices(adb: String) throws -> [AndroidDevice] {
        let result = ShellCommand.run(adb, ["devices"])
        guard result.succeeded else {
            throw InstallerError.commandFailed(result.error.isEmpty ? result.output : result.error)
        }
        return Self.parseDevices(result.output)
    }

    static func parseDevices(_ output: String) -> [AndroidDevice] {
        var devices: [AndroidDevice] = []
        for line in output.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard fields.count >= 2, fields[1] == "device" else { continue }
            let serial = fields[0]
            devices.append(AndroidDevice(serial: serial, isEmulator: serial.hasPrefix("emulator-")))
        }
        return devices
    }
}

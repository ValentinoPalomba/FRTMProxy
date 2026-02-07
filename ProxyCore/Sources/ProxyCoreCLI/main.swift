import Foundation
import Dispatch
import ProxyCore

@main
struct ProxyCoreCLI {
    static func main() async {
        do {
            let options = try CLIOptions.parse(CommandLine.arguments)
            switch options.command {
            case .start:
                try await runProxy(options: options)
            }
        } catch {
            fputs("ProxyCoreCLI error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runProxy(options: CLIOptions) async throws {
        let config = ProxyConfiguration(
            listenHost: options.host,
            listenPort: options.port,
            enableMITM: options.enableMITM,
            enableHTTP2: options.enableHTTP2
        )

        let engine = try ProxyEngine(configuration: config)

        let printer = Task {
            for await event in engine.events {
                switch event {
                case .log(let line):
                    print(line, terminator: "")

                case .request(let req):
                    print("[REQ] \(req.httpVersion.rawValue) \(req.method) \(req.url)")

                case .response(let res):
                    print("[RES] \(res.httpVersion.rawValue) \(res.statusCode) id=\(res.requestID)")

                case .webSocketMessage(let msg):
                    print("[WS] id=\(msg.requestID) dir=\(msg.direction) bytes=\(msg.data.count)")

                case .sseEvent(let e):
                    print("[SSE] id=\(e.requestID) event=\(e.event ?? "") data=\(e.data)")

                case .error(let err):
                    print("[ERR] id=\(err.requestID ?? "-") \(err.message)")
                }
            }
        }

        try await engine.start()

        for await _ in SignalStream.make([SIGINT, SIGTERM]) {
            break
        }

        await engine.stop()
        printer.cancel()
    }
}

private struct CLIOptions {
    enum Command {
        case start
    }

    var command: Command
    var host: String
    var port: Int
    var enableMITM: Bool
    var enableHTTP2: Bool

    static func parse(_ argv: [String]) throws -> CLIOptions {
        var args = Array(argv.dropFirst())
        let cmd = args.first ?? "start"
        if !args.isEmpty { args.removeFirst() }

        let command: Command
        switch cmd {
        case "start":
            command = .start
        case "help", "-h", "--help":
            throw CLIError.usage
        default:
            throw CLIError.unknownCommand(cmd)
        }

        var host = "0.0.0.0"
        var port = 9099
        var mitm = false
        var http2 = false

        while let arg = args.first {
            args.removeFirst()
            switch arg {
            case "--host":
                guard let v = args.first else { throw CLIError.missingValue("--host") }
                args.removeFirst()
                host = v

            case "--port":
                guard let v = args.first, let p = Int(v) else { throw CLIError.missingValue("--port") }
                args.removeFirst()
                port = p

            case "--mitm":
                mitm = true

            case "--http2":
                http2 = true

            default:
                throw CLIError.unknownFlag(arg)
            }
        }

        return CLIOptions(command: command, host: host, port: port, enableMITM: mitm, enableHTTP2: http2)
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage
    case unknownCommand(String)
    case unknownFlag(String)
    case missingValue(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: ProxyCoreCLI start [--host HOST] [--port PORT] [--mitm] [--http2]"
        case .unknownCommand(let cmd):
            return "Unknown command: \(cmd)"
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag)"
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        }
    }
}

private enum SignalStream {
    static func make(_ signals: [Int32]) -> AsyncStream<Int32> {
        AsyncStream { continuation in
            var mutableSources: [DispatchSourceSignal] = []
            mutableSources.reserveCapacity(signals.count)

            for sig in signals {
                signal(sig, SIG_IGN)
                let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
                src.setEventHandler {
                    continuation.yield(sig)
                }
                src.resume()
                mutableSources.append(src)
            }

            let sources = mutableSources
            continuation.onTermination = { _ in
                for src in sources {
                    src.cancel()
                }
            }
        }
    }
}

import SwiftUI
import AppKit

struct FlowContextMenuContent: View {
    let flow: MitmFlow
    let isHostPinned: Bool
    let isAppPinned: Bool
    let shareAnchorView: NSView?

    let onEditRetry: () -> Void
    let onMapLocal: () -> Void
    let onPinHost: () -> Void
    let onUnpinHost: () -> Void
    let onPinApp: () -> Void
    let onUnpinApp: () -> Void
    let onFilterApp: () -> Void
    let onFilterDevice: () -> Void

    var body: some View {
        Menu {
            Button(action: onEditRetry) {
                Label("Edit & Retry", systemImage: "arrow.triangle.2.circlepath")
            }

            Button(action: onMapLocal) {
                Label("Map Local", systemImage: "pencil.and.outline")
            }
        } label: {
            Label("Actions", systemImage: "bolt")
        }

        Menu {
            Button {
                ClipboardHelper.copy(flow.request?.url)
            } label: {
                Label("URL", systemImage: "link")
            }
            .disabled(flow.request?.url == nil)

            Button {
                ClipboardHelper.copy(flow.curlString)
            } label: {
                Label("cURL", systemImage: "terminal")
            }
            .disabled(flow.curlString == nil)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Menu {
            Button {
                openTeamsWithCopiedDetails()
            } label: {
                Label("Open Teams (copied)", systemImage: "message")
            }
            .disabled(flow.teamsShareText == nil)

            if flow.xRequestID != nil {
                Button {
                    presentRequestIDShare()
                } label: {
                    Label("X-Request-ID…", systemImage: "number")
                }
                .disabled(shareAnchorView == nil)
            }

            Button {
                presentDetailsShare()
            } label: {
                Label("Details…", systemImage: "square.and.arrow.up")
            }
            .disabled(flow.teamsShareText == nil || shareAnchorView == nil)

            Button {
                presentURLShare()
            } label: {
                Label("URL…", systemImage: "link")
            }
            .disabled(flow.request?.url == nil || shareAnchorView == nil)

            Button {
                presentCurlShare()
            } label: {
                Label("cURL…", systemImage: "terminal")
            }
            .disabled(flow.curlString == nil || shareAnchorView == nil)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        if shouldShowFilters || shouldShowPins {
            Divider()
        }

        if shouldShowFilters {
            Menu {
                if flow.clientApp != nil {
                    Button(action: onFilterApp) {
                        Label("App", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                if !flow.clientIP.isEmpty {
                    Button(action: onFilterDevice) {
                        Label("Device", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }

        if shouldShowPins {
            Menu {
                if flow.clientApp != nil {
                    if isAppPinned {
                        Button(action: onUnpinApp) {
                            Label("Unpin App", systemImage: "pin.slash")
                        }
                    } else {
                        Button(action: onPinApp) {
                            Label("Pin App", systemImage: "pin")
                        }
                    }
                }

                if !flow.host.isEmpty {
                    if isHostPinned {
                        Button(action: onUnpinHost) {
                            Label("Unpin Host", systemImage: "pin.slash")
                        }
                    } else {
                        Button(action: onPinHost) {
                            Label("Pin Host", systemImage: "pin")
                        }
                    }
                }
            } label: {
                Label("Pin", systemImage: "pin")
            }
        }

        Divider()

        Menu {
            Button {
                let titles = SharePresenter.availableServiceTitles(for: [flow.request?.url ?? "", flow.teamsShareText ?? ""])
                ClipboardHelper.copy(titles.joined(separator: "\n"))
            } label: {
                Label("Copy share targets", systemImage: "list.bullet")
            }
        } label: {
            Label("Debug", systemImage: "ladybug")
        }
    }

    private var shouldShowFilters: Bool {
        flow.clientApp != nil || !flow.clientIP.isEmpty
    }

    private var shouldShowPins: Bool {
        flow.clientApp != nil || !flow.host.isEmpty
    }

    private func presentDetailsShare() {
        guard let shareText = flow.teamsShareText else { return }
        guard let shareAnchorView else { return }
        SharePresenter.present(items: [shareText], from: shareAnchorView)
    }

    private func presentRequestIDShare() {
        guard let requestID = flow.xRequestID else { return }
        guard let shareAnchorView else { return }
        SharePresenter.present(items: [requestID], from: shareAnchorView)
    }

    private func presentURLShare() {
        guard let urlString = flow.request?.url else { return }
        guard let url = URL(string: urlString) else { return }
        guard let shareAnchorView else { return }
        SharePresenter.present(items: [url], from: shareAnchorView)
    }

    private func presentCurlShare() {
        guard let curl = flow.curlString else { return }
        guard let shareAnchorView else { return }
        SharePresenter.present(items: [curl], from: shareAnchorView)
    }

    private func openTeamsWithCopiedDetails() {
        guard let shareText = flow.teamsShareText else { return }
        ClipboardHelper.copy(shareText)
        openTeams()
    }

    private func openTeams() {
        let candidates = [
            "msteams://teams.microsoft.com",
            "https://teams.microsoft.com/"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

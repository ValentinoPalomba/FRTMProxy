import SwiftUI
import Foundation

class OnboardingManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentStep: OnboardingStep = .trustCertificate
    
    private let userDefaults = UserDefaults.standard
    private let hasCompletedOnboardingKey = "onboarding.completed.v2"
    
    var shouldShowOnboarding: Bool {
        !userDefaults.bool(forKey: hasCompletedOnboardingKey)
    }
    
    func startOnboarding() {
        guard shouldShowOnboarding else { return }
        isActive = true
        currentStep = .trustCertificate
    }
    
    func nextStep() {
        switch currentStep {
        case .trustCertificate:
            currentStep = .startProxy
        case .startProxy:
            currentStep = .configureWiFiProxy
        case .configureWiFiProxy:
            currentStep = .viewTraffic
        case .viewTraffic:
            currentStep = .filterResults
        case .filterResults:
            currentStep = .inspectFlow
        case .inspectFlow:
            currentStep = .mapResponse
        case .mapResponse:
            completeOnboarding()
        }
    }
    
    func previousStep() {
        switch currentStep {
        case .trustCertificate:
            break
        case .startProxy:
            currentStep = .trustCertificate
        case .configureWiFiProxy:
            currentStep = .startProxy
        case .viewTraffic:
            currentStep = .configureWiFiProxy
        case .filterResults:
            currentStep = .viewTraffic
        case .inspectFlow:
            currentStep = .filterResults
        case .mapResponse:
            currentStep = .inspectFlow
        }
    }
    
    func skipOnboarding() {
        completeOnboarding()
    }
    
    func completeOnboarding() {
        isActive = false
        userDefaults.set(true, forKey: hasCompletedOnboardingKey)
    }
    
    func resetOnboarding() {
        userDefaults.removeObject(forKey: hasCompletedOnboardingKey)
        currentStep = .trustCertificate
    }
}

enum OnboardingTarget: Hashable {
    case manageMenu
    case startProxy
    case configureWiFiProxy
    case viewTraffic
    case filterResults
    case inspectFlow
    case mapResponse
}

enum OnboardingStep: CaseIterable, Hashable {
    case trustCertificate
    case startProxy
    case configureWiFiProxy
    case viewTraffic
    case filterResults
    case inspectFlow
    case mapResponse
    
    var target: OnboardingTarget {
        switch self {
        case .trustCertificate:
            return .manageMenu
        case .startProxy:
            return .startProxy
        case .configureWiFiProxy:
            return .configureWiFiProxy
        case .viewTraffic:
            return .viewTraffic
        case .filterResults:
            return .filterResults
        case .inspectFlow:
            return .inspectFlow
        case .mapResponse:
            return .mapResponse
        }
    }

    var fallbackTarget: OnboardingTarget? {
        switch self {
        case .inspectFlow, .mapResponse:
            return .viewTraffic
        default:
            return nil
        }
    }

    var highlightPadding: CGFloat {
        switch self {
        case .trustCertificate, .startProxy, .mapResponse, .configureWiFiProxy:
            return 6
        case .filterResults:
            return 10
        case .viewTraffic, .inspectFlow:
            return 14
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .inspectFlow:
            return 18
        case .viewTraffic:
            return 14
        default:
            return 12
        }
    }

    var tooltipOffset: CGPoint {
        .zero
    }

    var title: String {
        switch self {
        case .trustCertificate:
            return "Trust the proxy certificate"
        case .startProxy:
            return "Start the proxy"
        case .configureWiFiProxy:
            return "Set the proxy in Wi‑Fi settings"
        case .viewTraffic:
            return "Monitor traffic"
        case .filterResults:
            return "Quick filters"
        case .inspectFlow:
            return "Request inspector"
        case .mapResponse:
            return "Map Local"
        }
    }
    
    var description: String {
        switch self {
        case .trustCertificate:
            return "To intercept HTTPS, install and trust the ProxyCore Root CA. macOS will ask for confirmation."
        case .startProxy:
            return "Press Start to run ProxyCore and begin capturing traffic."
        case .configureWiFiProxy:
            return "To capture traffic, configure the HTTP and HTTPS proxy in your Wi‑Fi settings."
        case .viewTraffic:
            return "The traffic table fills here with all HTTP/HTTPS requests in real time."
        case .filterResults:
            return "Use the search bar and filters to quickly narrow results."
        case .inspectFlow:
            return "Select a request in the table to open the Inspector with headers and body."
        case .mapResponse:
            return "After selecting a request, use Map Local to simulate local responses without touching the server."
        }
    }
    
    var position: OnboardingPosition {
        switch self {
        case .trustCertificate:
            return OnboardingPosition(
                anchor: .topTrailing,
                offset: CGPoint(x: -190, y: 80),
                highlightSize: CGSize(width: 130, height: 40)
            )
        case .startProxy:
            return OnboardingPosition(
                anchor: .topTrailing,
                offset: CGPoint(x: -20, y: 80),
                highlightSize: CGSize(width: 80, height: 40)
            )
        case .configureWiFiProxy:
            return OnboardingPosition(
                anchor: .topTrailing,
                offset: CGPoint(x: -190, y: 80),
                highlightSize: CGSize(width: 130, height: 40)
            )
        case .viewTraffic:
            return OnboardingPosition(
                anchor: .center,
                offset: CGPoint(x: 0, y: -50),
                highlightSize: CGSize(width: 400, height: 200)
            )
        case .filterResults:
            return OnboardingPosition(
                anchor: .topLeading,
                offset: CGPoint(x: 20, y: 100),
                highlightSize: CGSize(width: 300, height: 40)
            )
        case .inspectFlow:
            return OnboardingPosition(
                anchor: .bottom,
                offset: CGPoint(x: 0, y: -20),
                highlightSize: CGSize(width: 600, height: 120)
            )
        case .mapResponse:
            return OnboardingPosition(
                anchor: .bottomTrailing,
                offset: CGPoint(x: -10, y: -10),
                highlightSize: CGSize(width: 100, height: 40)
            )
        }
    }
}

struct OnboardingPosition {
    let anchor: Alignment
    let offset: CGPoint
    let highlightSize: CGSize
}

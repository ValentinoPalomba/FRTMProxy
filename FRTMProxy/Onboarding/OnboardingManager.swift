import SwiftUI
import Foundation

class OnboardingManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentStep: OnboardingStep = .startProxy
    
    private let userDefaults = UserDefaults.standard
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    
    var shouldShowOnboarding: Bool {
        !userDefaults.bool(forKey: hasCompletedOnboardingKey)
    }
    
    func startOnboarding() {
        guard shouldShowOnboarding else { return }
        isActive = true
        currentStep = .startProxy
    }
    
    func nextStep() {
        switch currentStep {
        case .startProxy:
            currentStep = .macOSProxyOverride
        case .macOSProxyOverride:
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
        case .startProxy:
            break
        case .macOSProxyOverride:
            currentStep = .startProxy
        case .viewTraffic:
            currentStep = .macOSProxyOverride
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
        currentStep = .startProxy
    }
}

enum OnboardingTarget: Hashable {
    case startProxy
    case macOSProxyOverride
    case viewTraffic
    case filterResults
    case inspectFlow
    case mapResponse
}

enum OnboardingStep: CaseIterable, Hashable {
    case startProxy
    case macOSProxyOverride
    case viewTraffic
    case filterResults
    case inspectFlow
    case mapResponse
    
    var target: OnboardingTarget {
        switch self {
        case .startProxy:
            return .startProxy
        case .macOSProxyOverride:
            return .macOSProxyOverride
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
        case .startProxy, .mapResponse:
            return 6
        case .macOSProxyOverride:
            return 8
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
        case .macOSProxyOverride:
            return 12
        default:
            return 12
        }
    }

    var tooltipOffset: CGPoint {
        .zero
    }

    var title: String {
        switch self {
        case .startProxy:
            return "Avvia il proxy"
        case .macOSProxyOverride:
            return "Override proxy macOS"
        case .viewTraffic:
            return "Monitora il traffico"
        case .filterResults:
            return "Filtri rapidi"
        case .inspectFlow:
            return "Inspector richiesta"
        case .mapResponse:
            return "Map Local"
        }
    }
    
    var description: String {
        switch self {
        case .startProxy:
            return "Premi Start per avviare il proxy e iniziare a intercettare il traffico dal tuo dispositivo."
        case .macOSProxyOverride:
            return "In Impostazioni > Proxy Behavior abilita \"Override macOS proxy\" per instradare il traffico del Mac su localhost e la porta del proxy."
        case .viewTraffic:
            return "La tabella del traffico si popola qui con tutte le richieste HTTP/HTTPS in tempo reale."
        case .filterResults:
            return "Usa la barra di ricerca e i filtri per restringere rapidamente i risultati."
        case .inspectFlow:
            return "Seleziona una richiesta nella tabella per aprire l'Inspector con header e body."
        case .mapResponse:
            return "Dopo aver selezionato una richiesta, usa Map Local per simulare risposte locali senza toccare il server."
        }
    }
    
    var position: OnboardingPosition {
        switch self {
        case .startProxy:
            return OnboardingPosition(
                anchor: .topTrailing,
                offset: CGPoint(x: -20, y: 80),
                highlightSize: CGSize(width: 80, height: 40)
            )
        case .macOSProxyOverride:
            return OnboardingPosition(
                anchor: .topTrailing,
                offset: CGPoint(x: -180, y: 90),
                highlightSize: CGSize(width: 220, height: 48)
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

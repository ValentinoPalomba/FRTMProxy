import Foundation

struct CaptureProfileCreationRequest: Identifiable {
    let id = UUID()
    let member: CaptureProfileMember?
}

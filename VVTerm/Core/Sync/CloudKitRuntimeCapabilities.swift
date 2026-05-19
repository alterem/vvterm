import Foundation
#if os(macOS)
import Security
#endif

enum CloudKitRuntimeCapabilities {
    private static let cloudKitServicesEntitlement = "com.apple.developer.icloud-services"
    private static let apsEnvironmentEntitlement = "aps-environment"
    private static let developerAPSEnvironmentEntitlement = "com.apple.developer.aps-environment"

    static var hasCloudKitEntitlement: Bool {
        #if os(macOS)
        guard let services: [String] = entitlementValue(for: cloudKitServicesEntitlement) else {
            return false
        }
        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
        #else
        return true
        #endif
    }

    static var hasPushNotificationsEntitlement: Bool {
        #if os(macOS)
        let apsEnvironment: String? = entitlementValue(for: apsEnvironmentEntitlement)
        let developerAPSEnvironment: String? = entitlementValue(for: developerAPSEnvironmentEntitlement)
        return apsEnvironment?.isEmpty == false || developerAPSEnvironment?.isEmpty == false
        #else
        return true
        #endif
    }

    #if os(macOS)
    private static func entitlementValue<T>(for key: String) -> T? {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else {
            return nil
        }
        return value as? T
    }
    #endif
}

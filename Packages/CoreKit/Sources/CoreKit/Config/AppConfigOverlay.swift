#if DEBUG
public extension AppConfig {
    /// Applies the explicit hermetic UI-test service overlay.
    ///
    /// Only the five required API/Cognito values come from `requiredServices`.
    /// Existing StoreKit product identifiers remain authoritative, while Sentry
    /// is disabled so a hermetic launch cannot emit remote crash reports.
    func applyingHermeticServiceOverlay(_ requiredServices: AppConfig) -> AppConfig {
        AppConfig(
            apiBaseURL: requiredServices.apiBaseURL,
            cognitoRegion: requiredServices.cognitoRegion,
            cognitoUserPoolID: requiredServices.cognitoUserPoolID,
            cognitoClientID: requiredServices.cognitoClientID,
            cognitoDomain: requiredServices.cognitoDomain,
            sentryDSN: "",
            storeKitMonthlyProductID: storeKitMonthlyProductID,
            storeKitAnnualProductID: storeKitAnnualProductID,
            storeKitAnnualUpfrontProductID: storeKitAnnualUpfrontProductID
        )
    }
}
#endif

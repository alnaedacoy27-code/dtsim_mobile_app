namespace DarwinTradingMobileAPI.Services;

/// <summary>
/// Who may use the phone app. The desktop's Permission Maintenance has a "Mobile App" switch
/// (module key "mobile_app") that moves together with Products and Delivery Management.
/// </summary>
public static class MobileAccess
{
    public const string AppKey = "mobile_app";

    /// <summary>The modules the phone app is built on (same list as the desktop).</summary>
    public static readonly string[] LinkedModules = { "products", "delivery" };

    public static bool IsSuperadmin(string role) =>
        role.Trim().Equals("superadmin", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// True when the person may sign in to the app and use it:
    ///   1. the Superadmin always may;
    ///   2. the Mobile App permission must be on (a missing row follows the factory setting:
    ///      Admin yes, Cashier no, exactly like the desktop);
    ///   3. and they must still have Products or Delivery Management, so nobody gets an app with no functions.
    /// </summary>
    public static bool CanUseApp(Dictionary<string, bool> permissions, string role)
    {
        if (IsSuperadmin(role)) return true;

        bool appAllowed = permissions.TryGetValue(AppKey, out var allowed)
            ? allowed
            : role.Trim().Equals("admin", StringComparison.OrdinalIgnoreCase);

        if (!appAllowed) return false;

        return LinkedModules.Any(m => permissions.TryGetValue(m, out var ok) && ok);
    }
}
using MySqlConnector;

namespace DarwinTradingMobileAPI.Services;

public enum SessionState { Active, Ended, Unknown }

/// <summary>
/// Records mobile logins in the same user_sessions table the desktop system
/// uses, so the desktop's User Monitoring shows who is on the phone app and
/// which module they are in, and an administrator can end their session.
/// </summary>
public class SessionService
{
    private readonly string _connectionString;

    // The text the desktop shows under "Current module".
    // Change a label here if you want it to match the desktop wording.
    public static readonly Dictionary<string, string> ModuleLabels = new(StringComparer.OrdinalIgnoreCase)
    {
        ["dashboard"] = "Dashboard",
        ["delivery"] = "Deliveries",
        ["products"] = "Products",
        ["settings"] = "Settings"
    };

    public SessionService(IConfiguration configuration)
    {
        _connectionString =
            configuration.GetConnectionString("Dtsims2")
            ?? throw new InvalidOperationException("Database connection string is missing.");
    }

    private MySqlConnection Open()
    {
        var c = new MySqlConnection(_connectionString);
        c.Open();
        return c;
    }

    // ---------------------------------------------------------------
    // Start: called right after a successful login. Returns the session id
    // (put in the token), or null if it could not be recorded.
    // ---------------------------------------------------------------
    public string? StartSession(int userId, string username, string? deviceName, string? ip)
    {
        try
        {
            string sid = "mobile-" + Guid.NewGuid().ToString("N");

            using var c = Open();
            using var cmd = new MySqlCommand("""
                INSERT INTO user_sessions
                    (session_id, user_id, username, device_name, ip_address)
                VALUES (@s, @u, @n, @d, @ip)
                """, c);
            cmd.Parameters.AddWithValue("@s", sid);
            cmd.Parameters.AddWithValue("@u", userId);
            cmd.Parameters.AddWithValue("@n", username);
            cmd.Parameters.AddWithValue("@d", Trim(deviceName, 100) ?? "Mobile App");
            cmd.Parameters.AddWithValue("@ip", (object?)Trim(ip, 45) ?? DBNull.Value);
            cmd.ExecuteNonQuery();
            return sid;
        }
        catch
        {
            return null; // monitoring must never block a login
        }
    }

    // ---------------------------------------------------------------
    // Called on every request: keeps "last seen" fresh and tells us if an
    // administrator ended this session on the desktop.
    // ---------------------------------------------------------------
    public SessionState Touch(string sessionId)
    {
        try
        {
            using var c = Open();

            if (Run(c, "UPDATE user_sessions SET last_seen = NOW() WHERE session_id = @s AND is_active = 1",
                    ("@s", sessionId)) > 0)
                return SessionState.Active;

            // Ended only because the phone went quiet (screen locked, no signal)?
            // Then it simply came back: reopen it.
            if (Run(c, """
                    UPDATE user_sessions
                    SET is_active = 1, logout_at = NULL, end_reason = NULL, last_seen = NOW()
                    WHERE session_id = @s AND is_active = 0 AND end_reason = 'Connection lost'
                    """, ("@s", sessionId)) > 0)
                return SessionState.Active;

            using var cmd = new MySqlCommand(
                "SELECT is_active FROM user_sessions WHERE session_id = @s", c);
            cmd.Parameters.AddWithValue("@s", sessionId);
            var v = cmd.ExecuteScalar();
            return v == null ? SessionState.Unknown : SessionState.Ended;
        }
        catch
        {
            return SessionState.Unknown;
        }
    }

    // Which module / maintenance the user is in now.
    public void SetModule(string sessionId, string moduleLabel)
    {
        try
        {
            using var c = Open();
            Run(c, """
                UPDATE user_sessions
                SET current_module = @m, module_since = NOW(), last_seen = NOW()
                WHERE session_id = @s AND is_active = 1
                  AND (current_module IS NULL OR current_module <> @m)
                """, ("@m", moduleLabel), ("@s", sessionId));
        }
        catch { }
    }

    public void EndSession(string sessionId, string reason)
    {
        try
        {
            using var c = Open();
            Run(c, """
                UPDATE user_sessions
                SET is_active = 0, logout_at = NOW(), end_reason = @r
                WHERE session_id = @s AND is_active = 1
                """, ("@r", reason), ("@s", sessionId));
        }
        catch { }
    }

    // Phones that closed the app or lost signal never say goodbye, so close
    // their sessions after a few quiet minutes.
    public int ExpireStale(int minutes)
    {
        try
        {
            using var c = Open();
            return Run(c, """
                UPDATE user_sessions
                SET is_active = 0, logout_at = last_seen, end_reason = 'Connection lost'
                WHERE is_active = 1
                  AND session_id LIKE 'mobile-%'
                  AND last_seen < DATE_SUB(NOW(), INTERVAL @m MINUTE)
                """, ("@m", minutes));
        }
        catch { return 0; }
    }

    // Same audit_trail the desktop reads.
    public void Audit(int userId, string username, string action, string description)
    {
        try
        {
            using var c = Open();
            using var cmd = new MySqlCommand("""
                INSERT INTO audit_trail
                    (user_id, username, action, module, description, device_name)
                VALUES (@u, @n, @a, 'Login', @d, 'Mobile API')
                """, c);
            cmd.Parameters.AddWithValue("@u", userId > 0 ? (object)userId : DBNull.Value);
            cmd.Parameters.AddWithValue("@n", username);
            cmd.Parameters.AddWithValue("@a", action);
            cmd.Parameters.AddWithValue("@d", description);
            cmd.ExecuteNonQuery();
        }
        catch { }
    }

    private static int Run(MySqlConnection c, string sql, params (string, object)[] p)
    {
        using var cmd = new MySqlCommand(sql, c);
        foreach (var (n, v) in p) cmd.Parameters.AddWithValue(n, v);
        return cmd.ExecuteNonQuery();
    }

    private static string? Trim(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        s = s.Trim();
        return s.Length <= max ? s : s[..max];
    }
}
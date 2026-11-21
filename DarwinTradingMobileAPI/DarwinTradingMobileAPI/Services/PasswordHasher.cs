
using System.Security.Cryptography;

namespace DarwinTradingMobileAPI.Services;

public static class PasswordHasher
{
    private const int HashSize = 32;
    private const string Prefix = "PBKDF2-SHA256";

    public static bool Verify(string password, string stored)
    {
        try
        {
            if (string.IsNullOrEmpty(password) ||
                string.IsNullOrEmpty(stored))
                return false;

            string[] parts = stored.Split('$');

            if (parts.Length != 4 || parts[0] != Prefix)
                return false;

            if (!int.TryParse(parts[1], out int iterations) ||
                iterations < 1 || iterations > 1000000)
                return false;

            byte[] salt = Convert.FromBase64String(parts[2]);
            byte[] expected = Convert.FromBase64String(parts[3]);

            if (salt.Length != 16 || expected.Length != HashSize)
                return false;

            byte[] actual = Rfc2898DeriveBytes.Pbkdf2(
                password,
                salt,
                iterations,
                HashAlgorithmName.SHA256,
                HashSize);

            return CryptographicOperations.FixedTimeEquals(
                actual, expected);
        }
        catch
        {
            return false;
        }
    }
}

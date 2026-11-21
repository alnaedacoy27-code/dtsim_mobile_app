using System.Text.RegularExpressions;
using MySqlConnector;

namespace DarwinTradingMobileAPI.Services;

public enum ProductResult
{
    Ok,
    NotFound,
    Invalid,
    DuplicateBarcode,
    DuplicateProduct,
    DuplicateCategory,
    BadCategory,
    Failed
}

public record ProductOutcome(ProductResult Result, int Id = 0, string Message = "");

public record CategoryOutcome(ProductResult Result, int Id = 0, string Name = "", string Message = "");

/// <summary>
/// Creates and edits products in the same dtsims2_db database the desktop
/// system uses, so a product made on the phone shows up on the desktop and
/// the other way round.
/// </summary>
public class ProductService
{
    private readonly string _connectionString;

    private static readonly Regex BarcodeRx = new("^[A-Za-z0-9-]{1,30}$");
    private static readonly Regex SpacesRx = new(@"\s+");

    public ProductService(IConfiguration configuration)
    {
        _connectionString =
            configuration.GetConnectionString("Dtsims2")
            ?? throw new InvalidOperationException(
                "Database connection string is missing.");
    }

    // ---------------------------------------------------------------
    // Create
    // ---------------------------------------------------------------
    public ProductOutcome CreateProduct(
        string? name, int categoryId, string? measurement,
        string? barcode, int lowStockThreshold, int userId)
    {
        var problem = Check(name, measurement, barcode, lowStockThreshold,
            out var n, out var m, out var b);
        if (problem != null) return new ProductOutcome(ProductResult.Invalid, 0, problem);

        using var c = new MySqlConnection(_connectionString);
        c.Open();

        if (!Exists(c, "SELECT 1 FROM categories WHERE id = @c LIMIT 1", ("@c", categoryId)))
            return new ProductOutcome(ProductResult.BadCategory, 0, "Choose a category.");

        if (Exists(c,
                "SELECT 1 FROM products WHERE category_id = @c AND name = @n AND measurement = @m LIMIT 1",
                ("@c", categoryId), ("@n", n), ("@m", m)))
            return new ProductOutcome(ProductResult.DuplicateProduct, 0,
                "This product with the same category and measurement already exists.");

        if (b != null && Exists(c, "SELECT 1 FROM products WHERE barcode = @b LIMIT 1", ("@b", b)))
            return new ProductOutcome(ProductResult.DuplicateBarcode, 0,
                "Another product already uses this barcode.");

        for (int attempt = 1; attempt <= 8; attempt++)
        {
            string code = b ?? NewBarcode(c);

            try
            {
                using var cmd = new MySqlCommand("""
                    INSERT INTO products
                        (category_id, name, measurement, barcode, low_stock_threshold)
                    VALUES (@c, @n, @m, @b, @t)
                    """, c);
                cmd.Parameters.AddWithValue("@c", categoryId);
                cmd.Parameters.AddWithValue("@n", n);
                cmd.Parameters.AddWithValue("@m", m);
                cmd.Parameters.AddWithValue("@b", code);
                cmd.Parameters.AddWithValue("@t", lowStockThreshold);
                cmd.ExecuteNonQuery();
                int id = Convert.ToInt32(cmd.LastInsertedId);

                Audit(userId, "ADD",
                    "Added product " + Label(n, m) + " (barcode " + code + ", id " + id + ") from the mobile app");
                return new ProductOutcome(ProductResult.Ok, id);
            }
            catch (MySqlException ex) when (ex.Number == 1062)
            {
                if (ex.Message.Contains("uq_products_barcode", StringComparison.OrdinalIgnoreCase))
                {
                    if (b != null)
                        return new ProductOutcome(ProductResult.DuplicateBarcode, 0,
                            "Another product already uses this barcode.");
                    continue; // generated barcode collided: try another one
                }
                return new ProductOutcome(ProductResult.DuplicateProduct, 0,
                    "This product with the same category and measurement already exists.");
            }
            catch (MySqlException ex) when (ex.Number == 1452)
            {
                return new ProductOutcome(ProductResult.BadCategory, 0, "Choose a category.");
            }
        }

        return new ProductOutcome(ProductResult.Failed);
    }

    // ---------------------------------------------------------------
    // Edit (name, category, measurement, barcode, low-stock threshold)
    // ---------------------------------------------------------------
    public ProductOutcome UpdateProduct(
        int id, string? name, int categoryId, string? measurement,
        string? barcode, int lowStockThreshold, int userId)
    {
        var problem = Check(name, measurement, barcode, lowStockThreshold,
            out var n, out var m, out var b);
        if (problem != null) return new ProductOutcome(ProductResult.Invalid, 0, problem);

        using var c = new MySqlConnection(_connectionString);
        c.Open();

        string oldName, oldMeasurement, oldBarcode;
        using (var cmd = new MySqlCommand(
            "SELECT name, measurement, barcode FROM products WHERE id = @id", c))
        {
            cmd.Parameters.AddWithValue("@id", id);
            using var r = cmd.ExecuteReader();
            if (!r.Read()) return new ProductOutcome(ProductResult.NotFound, 0, "Product not found.");
            oldName = r["name"].ToString()!;
            oldMeasurement = r["measurement"].ToString()!;
            oldBarcode = r["barcode"].ToString()!;
        }

        // no barcode sent = keep the one it has
        string code = b ?? oldBarcode;

        if (!Exists(c, "SELECT 1 FROM categories WHERE id = @c LIMIT 1", ("@c", categoryId)))
            return new ProductOutcome(ProductResult.BadCategory, 0, "Choose a category.");

        if (Exists(c,
                "SELECT 1 FROM products WHERE category_id = @c AND name = @n AND measurement = @m AND id <> @id LIMIT 1",
                ("@c", categoryId), ("@n", n), ("@m", m), ("@id", id)))
            return new ProductOutcome(ProductResult.DuplicateProduct, 0,
                "Another product with the same category and measurement already exists.");

        if (Exists(c, "SELECT 1 FROM products WHERE barcode = @b AND id <> @id LIMIT 1",
                ("@b", code), ("@id", id)))
            return new ProductOutcome(ProductResult.DuplicateBarcode, 0,
                "Another product already uses this barcode.");

        try
        {
            using var cmd = new MySqlCommand("""
                UPDATE products
                SET category_id = @c, name = @n, measurement = @m,
                    barcode = @b, low_stock_threshold = @t
                WHERE id = @id
                """, c);
            cmd.Parameters.AddWithValue("@c", categoryId);
            cmd.Parameters.AddWithValue("@n", n);
            cmd.Parameters.AddWithValue("@m", m);
            cmd.Parameters.AddWithValue("@b", code);
            cmd.Parameters.AddWithValue("@t", lowStockThreshold);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.ExecuteNonQuery();
        }
        catch (MySqlException ex) when (ex.Number == 1062)
        {
            return ex.Message.Contains("uq_products_barcode", StringComparison.OrdinalIgnoreCase)
                ? new ProductOutcome(ProductResult.DuplicateBarcode, 0, "Another product already uses this barcode.")
                : new ProductOutcome(ProductResult.DuplicateProduct, 0,
                    "Another product with the same category and measurement already exists.");
        }
        catch (MySqlException ex) when (ex.Number == 1452)
        {
            return new ProductOutcome(ProductResult.BadCategory, 0, "Choose a category.");
        }

        Audit(userId, "EDIT",
            "Edited product " + Label(oldName, oldMeasurement) + " (id " + id + ")" +
            (Label(oldName, oldMeasurement) != Label(n, m) ? " → " + Label(n, m) : "") +
            (oldBarcode != code ? ", barcode " + oldBarcode + " → " + code : "") +
            " from the mobile app");

        return new ProductOutcome(ProductResult.Ok, id);
    }


    // ---------------------------------------------------------------
    // Create a category (shared with the desktop system)
    // ---------------------------------------------------------------
    public CategoryOutcome CreateCategory(string? name, string? description, int userId)
    {
        var n = SpacesRx.Replace((name ?? "").Trim(), " ");
        var d = SpacesRx.Replace((description ?? "").Trim(), " ");

        if (n.Length == 0)
            return new CategoryOutcome(ProductResult.Invalid, 0, "", "Enter the category name.");

        using var c = new MySqlConnection(_connectionString);
        c.Open();

        // Look at the real table so this keeps working whatever columns the
        // desktop schema has (a description column, length limits, ...).
        var cols = new Dictionary<string, (bool Nullable, bool HasDefault, bool Auto, long? MaxLen)>(
            StringComparer.OrdinalIgnoreCase);

        using (var cmd = new MySqlCommand("""
            SELECT column_name, is_nullable, column_default, extra, character_maximum_length
            FROM information_schema.columns
            WHERE table_schema = DATABASE() AND table_name = 'categories'
            """, c))
        using (var r = cmd.ExecuteReader())
        {
            while (r.Read())
            {
                cols[r.GetString(0)] = (
                    r.GetString(1) == "YES",
                    !r.IsDBNull(2),
                    r.GetString(3).Contains("auto_increment", StringComparison.OrdinalIgnoreCase),
                    r.IsDBNull(4) ? null : Convert.ToInt64(r.GetValue(4)));
            }
        }

        if (!cols.ContainsKey("name"))
            return new CategoryOutcome(ProductResult.Failed, 0, "", "The categories table has no name column.");

        long nameMax = cols["name"].MaxLen ?? 100;
        if (n.Length > nameMax)
            return new CategoryOutcome(ProductResult.Invalid, 0, "",
                "The category name is too long (" + nameMax + " characters at most).");

        bool hasDesc = cols.TryGetValue("description", out var descCol);
        if (hasDesc && d.Length > (descCol.MaxLen ?? 255))
            return new CategoryOutcome(ProductResult.Invalid, 0, "",
                "The description is too long (" + (descCol.MaxLen ?? 255) + " characters at most).");

        foreach (var (col, info) in cols)
        {
            if (col.Equals("name", StringComparison.OrdinalIgnoreCase) ||
                col.Equals("description", StringComparison.OrdinalIgnoreCase)) continue;
            if (!info.Nullable && !info.HasDefault && !info.Auto)
                return new CategoryOutcome(ProductResult.Failed, 0, "",
                    "The categories table has a required column (" + col + ") this app does not fill in.");
        }

        if (Exists(c, "SELECT 1 FROM categories WHERE name = @n LIMIT 1", ("@n", n)))
            return new CategoryOutcome(ProductResult.DuplicateCategory, 0, "",
                "A category with this name already exists.");

        try
        {
            using var cmd = new MySqlCommand(
                hasDesc
                    ? "INSERT INTO categories (name, description) VALUES (@n, @d)"
                    : "INSERT INTO categories (name) VALUES (@n)", c);
            cmd.Parameters.AddWithValue("@n", n);
            if (hasDesc)
                cmd.Parameters.AddWithValue("@d",
                    d.Length == 0 && descCol.Nullable ? DBNull.Value : d);
            cmd.ExecuteNonQuery();
            int id = Convert.ToInt32(cmd.LastInsertedId);

            Audit(userId, "ADD", "Added category " + n + " (id " + id + ") from the mobile app", "Categories");
            return new CategoryOutcome(ProductResult.Ok, id, n);
        }
        catch (MySqlException ex) when (ex.Number == 1062)
        {
            return new CategoryOutcome(ProductResult.DuplicateCategory, 0, "",
                "A category with this name already exists.");
        }
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------
    private static string Label(string name, string measurement) =>
        measurement.Length == 0 ? name : name + " " + measurement;

    private static string? Check(
        string? name, string? measurement, string? barcode, int threshold,
        out string n, out string m, out string? b)
    {
        n = SpacesRx.Replace((name ?? "").Trim(), " ");
        m = SpacesRx.Replace((measurement ?? "").Trim(), " ");
        b = string.IsNullOrWhiteSpace(barcode) ? null : barcode.Trim();

        if (n.Length == 0) return "Enter the product name.";
        if (n.Length > 150) return "The product name is too long (150 characters at most).";
        if (m.Length > 100) return "The measurement is too long (100 characters at most).";
        if (b != null && !BarcodeRx.IsMatch(b))
            return "The barcode may only contain letters, numbers and dashes (30 characters at most).";
        if (threshold < 0 || threshold > 1_000_000)
            return "The low-stock alert must be between 0 and 1,000,000.";
        return null;
    }

    // Same numbering as the desktop system: "2" + an 11-digit running number
    // + the EAN-13 check digit (2000000000015, 2000000000022, ...). The next
    // number is the highest existing in-store barcode + 1. Barcodes scanned
    // from manufacturers' labels are ignored when counting.
    private static string NewBarcode(MySqlConnection c)
    {
        long last = 0;
        using (var cmd = new MySqlCommand("""
            SELECT MAX(CAST(SUBSTRING(barcode, 2, 11) AS UNSIGNED))
            FROM products
            WHERE barcode REGEXP '^2000[0-9]{9}$'
            """, c))
        {
            var v = cmd.ExecuteScalar();
            if (v != null && v != DBNull.Value) last = Convert.ToInt64(v);
        }

        while (true)
        {
            last++;
            string body = "2" + last.ToString("D11");

            int sum = 0;
            for (int i = 0; i < 12; i++)
                sum += (body[i] - '0') * (i % 2 == 0 ? 1 : 3);
            string code = body + ((10 - sum % 10) % 10);

            if (!Exists(c, "SELECT 1 FROM products WHERE barcode = @b LIMIT 1", ("@b", code)))
                return code;
        }
    }

    private static bool Exists(MySqlConnection c, string sql, params (string, object)[] p)
    {
        using var cmd = new MySqlCommand(sql, c);
        foreach (var (name, value) in p) cmd.Parameters.AddWithValue(name, value);
        return cmd.ExecuteScalar() != null;
    }

    // Same audit_trail entry the desktop writes, marked as coming from mobile.
    private void Audit(int userId, string action, string description, string module = "Products")
    {
        try
        {
            using var c = new MySqlConnection(_connectionString);
            c.Open();

            string? username = null;
            using (var u = new MySqlCommand("SELECT username FROM users WHERE id = @id", c))
            {
                u.Parameters.AddWithValue("@id", userId);
                username = u.ExecuteScalar() as string;
            }

            using var cmd = new MySqlCommand("""
                INSERT INTO audit_trail
                    (user_id, username, action, module, description, device_name)
                VALUES (@uid, @un, @a, @m, @d, 'Mobile API')
                """, c);
            cmd.Parameters.AddWithValue("@uid", userId > 0 ? (object)userId : DBNull.Value);
            cmd.Parameters.AddWithValue("@un", (object?)username ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@a", action);
            cmd.Parameters.AddWithValue("@m", module);
            cmd.Parameters.AddWithValue("@d", description);
            cmd.ExecuteNonQuery();
        }
        catch
        {
            // Audit logging must not break the request.
        }
    }
}
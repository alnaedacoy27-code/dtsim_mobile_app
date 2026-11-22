using System.Text.RegularExpressions;
using MySqlConnector;

namespace DarwinTradingMobileAPI.Services;

public enum SupplierResult
{
    Ok,
    NotFound,
    Invalid,
    DuplicateAddress,
    NumberTaken,
    Failed
}

public record SupplierOutcome(SupplierResult Result, int Id = 0, string Message = "");

public record SupplierDto(
    int Id,
    string CompanyName,
    string ContactPerson,
    string? ContactNumber,
    string Address,
    string? Email,
    int Branches,
    int Deliveries,
    DateTime? LastDelivery,
    DateTime CreatedAt);

public record SupplierDeliveryDto(int Id, string BatchNo, DateTime DeliveryDate, string Status, int Items);

public record SupplierDetailDto(SupplierDto Supplier, List<SupplierDeliveryDto> RecentDeliveries);

/// <summary>
/// Suppliers in the same dtsims2_db database the desktop uses, with the desktop's rules:
///   company name, contact person, mobile number (11 digits starting with 09) and address are required;
///   email is optional; the same company, person and number may repeat (branches) and different
///   companies may share an address; only the same company at the same address is a duplicate
///   (unique key uq_suppliers_company_address, which the desktop app sets up when it starts).
/// The desktop's supplier triggers write to change_log, so the other laptops refresh by themselves.
/// </summary>
public class SupplierService
{
    private readonly string _connectionString;

    private static readonly Regex SpacesRx = new(@"\s+");
    // same characters as the desktop's InputRules (names of things / addresses / people)
    private static readonly Regex TitleRx = new(@"^[\p{L}\p{N} .,#'/()&\-]+$");
    private static readonly Regex PersonRx = new(@"^[\p{L} '.\-]+$");
    private static readonly Regex MobileRx = new(@"^09\d{9}$");
    private static readonly Regex EmailRx = new(
        @"^[A-Za-z0-9_%+\-]+(\.[A-Za-z0-9_%+\-]+)*@([A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,24}$");

    public const int MaxName = 100;
    public const int MaxAddress = 150;
    public const int MaxEmail = 100;

    public SupplierService(IConfiguration configuration)
    {
        _connectionString =
            configuration.GetConnectionString("Dtsims2")
            ?? throw new InvalidOperationException("Database connection string is missing.");
    }

    // ---------------------------------------------------------------
    // Read
    // ---------------------------------------------------------------
    public List<SupplierDto> List(string? search)
    {
        using var c = new MySqlConnection(_connectionString);
        c.Open();

        var sql = """
            SELECT s.id, s.company_name, s.name, s.contact_number, s.company_address, s.email, s.created_at,
                   (SELECT COUNT(*) FROM suppliers x WHERE x.company_name = s.company_name) AS branches,
                   (SELECT COUNT(*) FROM deliveries d WHERE d.supplier_id = s.id) AS deliveries,
                   (SELECT MAX(d.delivery_date) FROM deliveries d WHERE d.supplier_id = s.id) AS last_delivery
            FROM suppliers s
            """;
        using var cmd = new MySqlCommand();
        cmd.Connection = c;
        var s = (search ?? "").Trim();
        if (s.Length > 0)
        {
            sql += " WHERE s.company_name LIKE @s OR s.name LIKE @s OR s.contact_number LIKE @s " +
                   "OR s.company_address LIKE @s OR s.email LIKE @s";
            cmd.Parameters.AddWithValue("@s", "%" + EscapeLike(s) + "%");
        }
        sql += " ORDER BY s.company_name, s.company_address LIMIT 500";
        cmd.CommandText = sql;

        var list = new List<SupplierDto>();
        using var r = cmd.ExecuteReader();
        while (r.Read()) list.Add(Read(r));
        return list;
    }

    public SupplierDetailDto? Get(int id)
    {
        using var c = new MySqlConnection(_connectionString);
        c.Open();

        SupplierDto? supplier = null;
        using (var cmd = new MySqlCommand("""
            SELECT s.id, s.company_name, s.name, s.contact_number, s.company_address, s.email, s.created_at,
                   (SELECT COUNT(*) FROM suppliers x WHERE x.company_name = s.company_name) AS branches,
                   (SELECT COUNT(*) FROM deliveries d WHERE d.supplier_id = s.id) AS deliveries,
                   (SELECT MAX(d.delivery_date) FROM deliveries d WHERE d.supplier_id = s.id) AS last_delivery
            FROM suppliers s WHERE s.id = @id
            """, c))
        {
            cmd.Parameters.AddWithValue("@id", id);
            using var r = cmd.ExecuteReader();
            if (r.Read()) supplier = Read(r);
        }
        if (supplier == null) return null;

        var recent = new List<SupplierDeliveryDto>();
        using (var cmd = new MySqlCommand("""
            SELECT d.id, d.batch_no, d.delivery_date, d.status,
                   (SELECT COUNT(*) FROM delivery_items i WHERE i.delivery_id = d.id) AS items
            FROM deliveries d WHERE d.supplier_id = @id
            ORDER BY d.delivery_date DESC, d.id DESC LIMIT 5
            """, c))
        {
            cmd.Parameters.AddWithValue("@id", id);
            using var r = cmd.ExecuteReader();
            while (r.Read())
            {
                recent.Add(new SupplierDeliveryDto(
                    r.GetInt32("id"), r.GetString("batch_no"), r.GetDateTime("delivery_date"),
                    r.GetString("status"), Convert.ToInt32(r["items"])));
            }
        }
        return new SupplierDetailDto(supplier, recent);
    }

    private static SupplierDto Read(MySqlDataReader r) => new(
        r.GetInt32("id"),
        r.GetString("company_name"),
        r.GetString("name"),
        r.IsDBNull(r.GetOrdinal("contact_number")) ? null : r.GetString("contact_number"),
        r.GetString("company_address"),
        r.IsDBNull(r.GetOrdinal("email")) ? null : r.GetString("email"),
        Convert.ToInt32(r["branches"]),
        Convert.ToInt32(r["deliveries"]),
        r.IsDBNull(r.GetOrdinal("last_delivery")) ? null : r.GetDateTime("last_delivery"),
        r.GetDateTime("created_at"));

    // ---------------------------------------------------------------
    // Create / edit
    // ---------------------------------------------------------------
    public SupplierOutcome Create(string? company, string? person, string? number, string? address, string? email, int userId)
    {
        var problem = Check(company, person, number, address, email,
            out var co, out var pe, out var nu, out var ad, out var em);
        if (problem != null) return new SupplierOutcome(SupplierResult.Invalid, 0, problem);

        try
        {
            using var c = new MySqlConnection(_connectionString);
            c.Open();
            if (AddressTaken(c, co, ad, 0)) return DuplicateAddress();
            var owner = NumberOwner(c, nu, pe, 0);
            if (owner != null) return NumberTaken(nu, owner);

            using var cmd = new MySqlCommand("""
                INSERT INTO suppliers (name, company_name, contact_number, company_address, email)
                VALUES (@n, @c, @t, @a, @e)
                """, c);
            cmd.Parameters.AddWithValue("@n", pe);
            cmd.Parameters.AddWithValue("@c", co);
            cmd.Parameters.AddWithValue("@t", nu);
            cmd.Parameters.AddWithValue("@a", ad);
            cmd.Parameters.AddWithValue("@e", (object?)em ?? DBNull.Value);
            cmd.ExecuteNonQuery();
            int id = Convert.ToInt32(cmd.LastInsertedId);

            Audit(userId, "ADD", "Added supplier '" + co + "' (" + ad + ") from the mobile app");
            return new SupplierOutcome(SupplierResult.Ok, id);
        }
        catch (MySqlException ex) when (ex.Number == 1062)
        {
            return DuplicateAddress();
        }
    }

    public SupplierOutcome Update(int id, string? company, string? person, string? number, string? address, string? email, int userId)
    {
        var problem = Check(company, person, number, address, email,
            out var co, out var pe, out var nu, out var ad, out var em);
        if (problem != null) return new SupplierOutcome(SupplierResult.Invalid, 0, problem);

        try
        {
            using var c = new MySqlConnection(_connectionString);
            c.Open();
            if (AddressTaken(c, co, ad, id)) return DuplicateAddress();
            var owner = NumberOwner(c, nu, pe, id);
            if (owner != null) return NumberTaken(nu, owner);

            using var cmd = new MySqlCommand("""
                UPDATE suppliers
                SET name = @n, company_name = @c, contact_number = @t, company_address = @a, email = @e
                WHERE id = @id
                """, c);
            cmd.Parameters.AddWithValue("@n", pe);
            cmd.Parameters.AddWithValue("@c", co);
            cmd.Parameters.AddWithValue("@t", nu);
            cmd.Parameters.AddWithValue("@a", ad);
            cmd.Parameters.AddWithValue("@e", (object?)em ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@id", id);
            // MySQL counts only changed rows: check that the supplier exists instead
            cmd.ExecuteNonQuery();
            if (!Exists(c, id)) return new SupplierOutcome(SupplierResult.NotFound, 0, "This supplier no longer exists.");

            Audit(userId, "EDIT", "Edited supplier '" + co + "' (" + ad + ", id " + id + ") from the mobile app");
            return new SupplierOutcome(SupplierResult.Ok, id);
        }
        catch (MySqlException ex) when (ex.Number == 1062)
        {
            return DuplicateAddress();
        }
    }

    private static SupplierOutcome DuplicateAddress() =>
        new(SupplierResult.DuplicateAddress, 0,
            "This company is already saved at this address. Another branch needs its own address; a different company may share it.");

    // ---------------------------------------------------------------
    // Rules (the same as the desktop's supplier window)
    // ---------------------------------------------------------------
    private static string? Check(
        string? company, string? person, string? number, string? address, string? email,
        out string co, out string pe, out string nu, out string ad, out string? em)
    {
        co = Tidy(company);
        pe = Tidy(person);
        nu = (number ?? "").Trim().Replace(" ", "").Replace("-", "");
        ad = Tidy(address);
        var e = (email ?? "").Trim();
        em = e.Length == 0 ? null : e;

        if (co.Length == 0) return "Enter the company name.";
        if (co.Length < 2 || co.Length > MaxName) return "The company name must be 2 to " + MaxName + " characters.";
        if (!TitleRx.IsMatch(co) || !co.Any(char.IsLetterOrDigit))
            return "The company name can have letters, numbers and . , # ' / ( ) & - only.";

        if (pe.Length == 0) return "Enter the contact person.";
        if (pe.Length > MaxName) return "The contact person can be at most " + MaxName + " characters.";
        if (!PersonRx.IsMatch(pe) || pe.Count(char.IsLetter) < 2)
            return "The contact person must be a name (letters, space, ' . - only).";

        if (nu.Length == 0) return "Enter the contact number.";
        if (!MobileRx.IsMatch(nu)) return "The contact number must be 11 digits starting with 09, for example 09171234567.";

        if (ad.Length == 0) return "Enter the company address.";
        if (ad.Length < 2 || ad.Length > MaxAddress) return "The address must be 2 to " + MaxAddress + " characters.";
        if (!TitleRx.IsMatch(ad) || !ad.Any(char.IsLetterOrDigit))
            return "The address can have letters, numbers and . , # ' / ( ) & - only.";

        if (em != null)
        {
            if (em.Length > MaxEmail || !EmailRx.IsMatch(em) || em.IndexOf('@') > 64)
                return "The email is not valid, for example name@gmail.com.";
        }
        return null;
    }

    private static string Tidy(string? s) => SpacesRx.Replace((s ?? "").Trim(), " ");

    private static string EscapeLike(string s) =>
        s.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_");

    // A number belongs to one person: the name saved with this number under a DIFFERENT contact person,
    // or null when it is free or used by the same person (at other companies or branches).
    private static string? NumberOwner(MySqlConnection c, string number, string person, int exceptId)
    {
        if (number.Length == 0) return null;
        using var cmd = new MySqlCommand(
            "SELECT name FROM suppliers WHERE contact_number = @t AND name <> @n AND id <> @id LIMIT 1", c);
        cmd.Parameters.AddWithValue("@t", number);
        cmd.Parameters.AddWithValue("@n", person);
        cmd.Parameters.AddWithValue("@id", exceptId);
        return cmd.ExecuteScalar() as string;
    }

    private static SupplierOutcome NumberTaken(string number, string owner) =>
        new(SupplierResult.NumberTaken, 0,
            $"{number} is already the number of {owner}. One number belongs to one person; " +
            "the same person may deal with several companies.");

    // the same company already saved at this address (another company may share it)
    private static bool AddressTaken(MySqlConnection c, string company, string address, int exceptId)
    {
        using var cmd = new MySqlCommand(
            "SELECT 1 FROM suppliers WHERE company_name = @c AND company_address = @a AND id <> @id LIMIT 1", c);
        cmd.Parameters.AddWithValue("@c", company);
        cmd.Parameters.AddWithValue("@a", address);
        cmd.Parameters.AddWithValue("@id", exceptId);
        return cmd.ExecuteScalar() != null;
    }

    private static bool Exists(MySqlConnection c, int id)
    {
        using var cmd = new MySqlCommand("SELECT 1 FROM suppliers WHERE id = @id", c);
        cmd.Parameters.AddWithValue("@id", id);
        return cmd.ExecuteScalar() != null;
    }

    // Same audit_trail entry the desktop writes, marked as coming from mobile.
    private void Audit(int userId, string action, string description)
    {
        try
        {
            using var c = new MySqlConnection(_connectionString);
            c.Open();

            string? username;
            using (var u = new MySqlCommand("SELECT username FROM users WHERE id = @id", c))
            {
                u.Parameters.AddWithValue("@id", userId);
                username = u.ExecuteScalar() as string;
            }

            using var cmd = new MySqlCommand("""
                INSERT INTO audit_trail (user_id, username, action, module, description, device_name)
                VALUES (@uid, @un, @a, 'Suppliers', @d, 'Mobile API')
                """, c);
            cmd.Parameters.AddWithValue("@uid", userId > 0 ? userId : DBNull.Value);
            cmd.Parameters.AddWithValue("@un", (object?)username ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@a", action);
            cmd.Parameters.AddWithValue("@d", description);
            cmd.ExecuteNonQuery();
        }
        catch
        {
            // Audit logging must not break the request.
        }
    }
}


using MySqlConnector;
using System.Data;

namespace DarwinTradingMobileAPI.Services;

public enum BatchResult
{
    Ok,
    NotFound,
    /// <summary>The batch was already sent (or changed by someone else).</summary>
    NotDraft,
    /// <summary>Nothing in the batch yet.</summary>
    Empty,
    Failed,
    /// <summary>Delivery date in the future.</summary>
    BadDate,
    /// <summary>Quantity or price missing / zero.</summary>
    Invalid,
    /// <summary>The supplier's cost price for the item is locked.</summary>
    PriceLocked
}

public class AuthService
{
    private readonly string _connectionString;

    public AuthService(IConfiguration configuration)
    {
        _connectionString =
            configuration.GetConnectionString("Dtsims2")
            ?? throw new InvalidOperationException(
                "Database connection string is missing.");
    }

    public class LoginResult
    {
        public bool Success { get; set; }
        public string Message { get; set; } = "";
        public int UserId { get; set; }
        public string Username { get; set; } = "";
        public string FullName { get; set; } = "";
        public string Role { get; set; } = "";
    }

    public LoginResult Login(string username, string password)
    {
        username = (username ?? "").Trim();

        if (string.IsNullOrWhiteSpace(username) ||
            string.IsNullOrEmpty(password))
        {
            return new LoginResult
            {
                Message = "Enter your username and password."
            };
        }

        try
        {
            using var connection = new MySqlConnection(_connectionString);
            connection.Open();

            using var command = new MySqlCommand("""
                SELECT id, username, password_hash, full_name, role,
                       is_active, is_locked, failed_attempts,
                       COALESCE(locked_until > NOW(), 0) AS temp_locked,
                       COALESCE(TIMESTAMPDIFF(MINUTE, NOW(), locked_until), 0) AS mins_left
                FROM users
                WHERE username = @username
                """, connection);

            command.Parameters.AddWithValue("@username", username);

            using var reader = command.ExecuteReader();

            if (!reader.Read())
            {
                reader.Close();
                WriteAudit(connection, null, username,
                    "LOGIN_FAILED", "Unknown username: " + username);

                return new LoginResult
                {
                    Message = "Invalid username or password."
                };
            }

            int userId = Convert.ToInt32(reader["id"]);
            string realUsername = reader["username"].ToString()!;
            string passwordHash = reader["password_hash"].ToString()!;
            string fullName = reader["full_name"].ToString()!;
            string role = reader["role"].ToString()!;

            bool isSuperadmin =
                role.Trim().Equals("superadmin",
                    StringComparison.OrdinalIgnoreCase);

            bool isActive = Convert.ToInt32(reader["is_active"]) != 0;
            bool isLocked = Convert.ToInt32(reader["is_locked"]) != 0;
            bool tempLocked = Convert.ToInt32(reader["temp_locked"]) != 0;
            int minutesLeft = Convert.ToInt32(reader["mins_left"]);
            int failedAttempts = Convert.ToInt32(reader["failed_attempts"]);

            reader.Close();

            if (!isSuperadmin && tempLocked)
            {
                return new LoginResult
                {
                    Message = $"Too many failed attempts. Try again in about {minutesLeft + 1} minute(s)."
                };
            }

            if (!isSuperadmin && isLocked)
            {
                return new LoginResult
                {
                    Message = "This account is locked. Ask an administrator to unlock it."
                };
            }

            if (!isActive)
            {
                return new LoginResult
                {
                    Message = "This account is disabled."
                };
            }

            if (!PasswordHasher.Verify(password, passwordHash))
            {
                if (!isSuperadmin)
                {
                    using var update = new MySqlCommand("""
                        UPDATE users SET
                            locked_until = IF(
                                failed_attempts + 1 >= 5,
                                DATE_ADD(NOW(), INTERVAL 15 MINUTE),
                                locked_until
                            ),
                            failed_attempts = IF(
                                failed_attempts + 1 >= 5,
                                0,
                                failed_attempts + 1
                            )
                        WHERE id = @id
                        """, connection);

                    update.Parameters.AddWithValue("@id", userId);
                    update.ExecuteNonQuery();
                }

                WriteAudit(connection, userId, realUsername,
                    "LOGIN_FAILED", "Wrong password");

                return new LoginResult
                {
                    Message = isSuperadmin
                        ? "Invalid username or password."
                        : failedAttempts + 1 >= 5
                            ? "Too many failed attempts. This account is locked for 15 minutes."
                            : $"Invalid username or password. {4 - failedAttempts} attempt(s) left."
                };
            }

            using (var update = new MySqlCommand("""
                UPDATE users
                SET failed_attempts = 0,
                    locked_until = NULL,
                    last_login = NOW()
                WHERE id = @id
                """, connection))
            {
                update.Parameters.AddWithValue("@id", userId);
                update.ExecuteNonQuery();
            }

            WriteAudit(connection, userId, realUsername,
                "LOGIN", $"'{realUsername}' logged in");

            return new LoginResult
            {
                Success = true,
                Message = "Login successful.",
                UserId = userId,
                Username = realUsername,
                FullName = fullName,
                Role = role
            };
        }
        catch
        {
            return new LoginResult
            {
                Message = "Unable to connect to the database."
            };
        }
    }


    public Dictionary<string, bool> GetPermissions(int userId, string role)
    {
        var permissions = new Dictionary<string, bool>(
            StringComparer.OrdinalIgnoreCase);

        using var connection = new MySqlConnection(_connectionString);
        connection.Open();

        using var command = new MySqlCommand("""
        SELECT
            modules.module_key,
            CASE
                WHEN @isSuperadmin = 1 THEN 1
                ELSE COALESCE(up.is_allowed, rp.is_allowed, 0)
            END AS effective_permission
        FROM (
            SELECT module_key
            FROM role_permissions
            WHERE role = @role

            UNION

            SELECT module_key
            FROM user_permissions
            WHERE user_id = @userId
        ) AS modules
        LEFT JOIN role_permissions rp
            ON rp.module_key = modules.module_key
            AND rp.role = @role
        LEFT JOIN user_permissions up
            ON up.module_key = modules.module_key
            AND up.user_id = @userId
        """, connection);

        command.Parameters.AddWithValue("@userId", userId);
        command.Parameters.AddWithValue("@role", role);
        command.Parameters.AddWithValue(
            "@isSuperadmin",
            role.Equals("superadmin",
                StringComparison.OrdinalIgnoreCase) ? 1 : 0);

        using var reader = command.ExecuteReader();

        while (reader.Read())
        {
            string module = reader["module_key"].ToString()!;
            bool allowed =
                Convert.ToInt32(reader["effective_permission"]) != 0;

            permissions[module] = allowed;
        }

        return permissions;
    }

    public void LogAccessDenied(int userId, string username)
    {
        try
        {
            using var connection = new MySqlConnection(_connectionString);
            connection.Open();
            WriteAudit(connection, userId, username,
                "LOGIN_DENIED", "No mobile app permission");
        }
        catch
        {
            // Audit logging must not interrupt login.
        }
    }

    private static void WriteAudit(
        MySqlConnection connection,
        int? userId,
        string username,
        string action,
        string description)
    {
        try
        {
            using var command = new MySqlCommand("""
                INSERT INTO audit_trail
                    (user_id, username, action, module, description, device_name)
                VALUES
                    (@uid, @username, @action, 'Login', @description, 'Mobile API')
                """, connection);

            command.Parameters.AddWithValue("@uid",
                userId.HasValue ? userId.Value : DBNull.Value);
            command.Parameters.AddWithValue("@username", username);
            command.Parameters.AddWithValue("@action", action);
            command.Parameters.AddWithValue("@description", description);

            command.ExecuteNonQuery();
        }
        catch
        {
            // Audit logging must not interrupt login.
        }
    }

    // ---------------------------------------------------------------
    // Inventory (products, categories, stock movements)
    // ---------------------------------------------------------------
    public record ProductDto(
        int Id,
        int CategoryId,
        string CategoryName,
        string Name,
        string Measurement,
        string Barcode,
        decimal SellingPrice,
        int QtyOnHand,
        int LowStockThreshold,
        string Status);

    public record StockSummary(int Total, int Low, int Out);

    public record ProductPage(
        int Total,
        StockSummary Summary,
        List<ProductDto> Items);

    public record MovementDto(
        long Id,
        string Type,
        int QtyChange,
        int BalanceAfter,
        string? ReferenceType,
        int? ReferenceId,
        string? User,
        DateTime CreatedAt);

    public record ProductDetailDto(
        ProductDto Product,
        List<MovementDto> Movements);

    public record CategoryDto(int Id, string Name, int ProductCount);

    private const string ProductSelect = """
        SELECT p.id, p.category_id, c.name AS category_name, p.name,
               p.measurement, p.barcode, p.selling_price,
               p.qty_on_hand, p.low_stock_threshold
        FROM products p
        JOIN categories c ON c.id = p.category_id
        """;

    // ---------------------------------------------------------------
    // Product list
    // ---------------------------------------------------------------
    public ProductPage GetProducts(
        string? search, int? categoryId, string stock, int page, int pageSize)
    {
        using var connection = new MySqlConnection(_connectionString);
        connection.Open();

        var where = BuildWhere(search, categoryId, stock);

        int total;
        using (var countCmd = new MySqlCommand(
            "SELECT COUNT(*) FROM products p " + where, connection))
        {
            AddFilterParams(countCmd, search, categoryId);
            total = Convert.ToInt32(countCmd.ExecuteScalar());
        }

        var items = new List<ProductDto>();
        using (var listCmd = new MySqlCommand(
            ProductSelect + "\n" + where +
            "\nORDER BY p.name, p.measurement LIMIT @limit OFFSET @offset",
            connection))
        {
            AddFilterParams(listCmd, search, categoryId);
            listCmd.Parameters.AddWithValue("@limit", pageSize);
            listCmd.Parameters.AddWithValue("@offset", (page - 1) * pageSize);

            using var reader = listCmd.ExecuteReader();
            while (reader.Read())
            {
                items.Add(ReadProduct(reader));
            }
        }

        return new ProductPage(total, GetSummary(connection), items);
    }

    private static StockSummary GetSummary(MySqlConnection connection)
    {
        using var cmd = new MySqlCommand("""
            SELECT COUNT(*),
                   COALESCE(SUM(qty_on_hand > 0
                                AND qty_on_hand <= low_stock_threshold), 0),
                   COALESCE(SUM(qty_on_hand <= 0), 0)
            FROM products
            """, connection);

        using var reader = cmd.ExecuteReader();
        reader.Read();

        return new StockSummary(
            Convert.ToInt32(reader[0]),
            Convert.ToInt32(reader[1]),
            Convert.ToInt32(reader[2]));
    }

    private static string BuildWhere(
        string? search, int? categoryId, string stock)
    {
        var clauses = new List<string>();

        if (!string.IsNullOrWhiteSpace(search))
        {
            clauses.Add("(p.name LIKE @search OR p.barcode LIKE @search " +
                        "OR p.measurement LIKE @search)");
        }

        if (categoryId.HasValue)
        {
            clauses.Add("p.category_id = @categoryId");
        }

        if (stock == "out")
        {
            clauses.Add("(p.qty_on_hand <= 0)");
        }
        else if (stock == "low")
        {
            clauses.Add("(p.qty_on_hand > 0 " +
                        "AND p.qty_on_hand <= p.low_stock_threshold)");
        }

        return clauses.Count == 0
            ? ""
            : "WHERE " + string.Join(" AND ", clauses);
    }

    private static void AddFilterParams(
        MySqlCommand command, string? search, int? categoryId)
    {
        if (!string.IsNullOrWhiteSpace(search))
        {
            command.Parameters.AddWithValue(
                "@search", "%" + search.Trim() + "%");
        }

        if (categoryId.HasValue)
        {
            command.Parameters.AddWithValue("@categoryId", categoryId.Value);
        }
    }

    // ---------------------------------------------------------------
    // One product with its recent stock movements
    // ---------------------------------------------------------------
    public ProductDetailDto? GetProduct(int id)
    {
        using var connection = new MySqlConnection(_connectionString);
        connection.Open();

        ProductDto? product = null;

        using (var cmd = new MySqlCommand(
            ProductSelect + "\nWHERE p.id = @id", connection))
        {
            cmd.Parameters.AddWithValue("@id", id);
            using var reader = cmd.ExecuteReader();
            if (reader.Read())
            {
                product = ReadProduct(reader);
            }
        }

        if (product == null)
        {
            return null;
        }

        var movements = new List<MovementDto>();

        using (var cmd = new MySqlCommand("""
            SELECT m.id, m.movement_type, m.qty_change, m.balance_after,
                   m.reference_type, m.reference_id, u.username, m.created_at
            FROM inventory_movements m
            LEFT JOIN users u ON u.id = m.user_id
            WHERE m.product_id = @id
            ORDER BY m.created_at DESC, m.id DESC
            LIMIT 30
            """, connection))
        {
            cmd.Parameters.AddWithValue("@id", id);
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                movements.Add(new MovementDto(
                    Convert.ToInt64(reader["id"]),
                    reader["movement_type"].ToString()!,
                    Convert.ToInt32(reader["qty_change"]),
                    Convert.ToInt32(reader["balance_after"]),
                    NullableString(reader, "reference_type"),
                    NullableInt(reader, "reference_id"),
                    NullableString(reader, "username"),
                    Convert.ToDateTime(reader["created_at"])));
            }
        }

        return new ProductDetailDto(product, movements);
    }

    // ---------------------------------------------------------------
    // Categories
    // ---------------------------------------------------------------
    public List<CategoryDto> GetCategories()
    {
        using var connection = new MySqlConnection(_connectionString);
        connection.Open();

        using var cmd = new MySqlCommand("""
            SELECT c.id, c.name, COUNT(p.id) AS product_count
            FROM categories c
            LEFT JOIN products p ON p.category_id = c.id
            GROUP BY c.id, c.name
            ORDER BY c.name
            """, connection);

        var list = new List<CategoryDto>();
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            list.Add(new CategoryDto(
                Convert.ToInt32(reader["id"]),
                reader["name"].ToString()!,
                Convert.ToInt32(reader["product_count"])));
        }

        return list;
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------
    private static ProductDto ReadProduct(MySqlDataReader reader)
    {
        int qty = Convert.ToInt32(reader["qty_on_hand"]);
        int threshold = Convert.ToInt32(reader["low_stock_threshold"]);

        return new ProductDto(
            Convert.ToInt32(reader["id"]),
            Convert.ToInt32(reader["category_id"]),
            reader["category_name"].ToString()!,
            reader["name"].ToString()!,
            reader["measurement"].ToString()!,
            reader["barcode"].ToString()!,
            Convert.ToDecimal(reader["selling_price"]),
            qty,
            threshold,
            StatusOf(qty, threshold));
    }

    private static string StatusOf(int qty, int threshold) =>
        qty <= 0 ? "out" : qty <= threshold ? "low" : "in";

    private static string? NullableString(MySqlDataReader reader, string column)
    {
        var value = reader[column];
        return value is DBNull ? null : value.ToString();
    }

    private static int? NullableInt(MySqlDataReader reader, string column)
    {
        var value = reader[column];
        return value is DBNull ? null : Convert.ToInt32(value);
    }

    // ---------------------------------------------------------------
    // Dashboard
    // ---------------------------------------------------------------
    public record DashboardSummary(
        int Products, int LowStock, int OutOfStock,
        int DeliveriesToday, int Drafts);

    public DashboardSummary GetDashboardSummary()
    {
        using var connection = new MySqlConnection(_connectionString);
        connection.Open();

        using var cmd = new MySqlCommand("""
            SELECT
                (SELECT COUNT(*) FROM products),
                (SELECT COUNT(*) FROM products
                    WHERE qty_on_hand > 0
                      AND qty_on_hand <= low_stock_threshold),
                (SELECT COUNT(*) FROM products WHERE qty_on_hand <= 0),
                (SELECT COUNT(*) FROM deliveries
                    WHERE status = 'sent' AND delivery_date = CURDATE()),
                (SELECT COUNT(*) FROM deliveries WHERE status = 'draft')
            """, connection);

        using var reader = cmd.ExecuteReader();
        reader.Read();

        return new DashboardSummary(
            Convert.ToInt32(reader[0]),
            Convert.ToInt32(reader[1]),
            Convert.ToInt32(reader[2]),
            Convert.ToInt32(reader[3]),
            Convert.ToInt32(reader[4]));
    }

    // ===============================================================
    // Deliveries (same rules as the desktop DeliveryRepository)
    // ===============================================================
    public record SupplierDto(int Id, string CompanyName, string CompanyAddress, string Name);

    public record BatchDto(
        int Id, string BatchNo, string Status, DateTime DeliveryDate,
        decimal TotalCost, decimal ExpectedProfit,
        string CompanyName, string CompanyAddress, string Contact, int ItemCount);

    public record DeliveryItemDto(
        int Id, int ProductId, string Name, string Measurement, string Barcode,
        string Category, int Qty, int QtyRemaining, decimal CostPrice,
        string CostMode, int PackSize, decimal EnteredCost, decimal SellingPrice,
        decimal LineCost, decimal ExpectedProfit);

    public record BatchDetailDto(
        int Id, string BatchNo, string Status, DateTime DeliveryDate, int SupplierId,
        decimal TotalCost, decimal ExpectedProfit, DateTime? SentAt,
        string CompanyName, string CompanyAddress, string Contact,
        string? CreatedBy, string? SentBy, List<DeliveryItemDto> Items);

    public record LastPriceDto(
        decimal CostPrice, string CostMode, int PackSize, decimal EnteredCost,
        decimal SellingPrice, string BatchNo, DateTime DeliveryDate, string CompanyName);

    public record BatchOutcome(BatchResult Result, int Id = 0, string BatchNo = "");

    private MySqlConnection OpenDb()
    {
        var connection = new MySqlConnection(_connectionString);
        connection.Open();
        return connection;
    }

    private static MySqlCommand MakeCmd(
        MySqlConnection c, MySqlTransaction? tx, string sql, (string, object?)[] p)
    {
        var cmd = new MySqlCommand(sql, c, tx);
        foreach (var (name, value) in p)
        {
            cmd.Parameters.AddWithValue(name, value ?? DBNull.Value);
        }
        return cmd;
    }

    private static int Exec(
        MySqlConnection c, MySqlTransaction? tx, string sql, params (string, object?)[] p)
    {
        using var cmd = MakeCmd(c, tx, sql, p);
        return cmd.ExecuteNonQuery();
    }

    private static object? Scal(
        MySqlConnection c, MySqlTransaction? tx, string sql, params (string, object?)[] p)
    {
        using var cmd = MakeCmd(c, tx, sql, p);
        var o = cmd.ExecuteScalar();
        return o is DBNull ? null : o;
    }

    private static string? Str(MySqlDataReader r, string col)
    {
        var o = r[col];
        return o is DBNull ? null : o.ToString();
    }

    private static void RecalcTotals(MySqlConnection c, MySqlTransaction tx, int batchId)
    {
        Exec(c, tx, """
            UPDATE deliveries SET
              total_cost = (SELECT COALESCE(SUM(line_cost), 0)
                            FROM delivery_items WHERE delivery_id = @b),
              expected_profit = (SELECT COALESCE(SUM(expected_profit), 0)
                                 FROM delivery_items WHERE delivery_id = @b)
            WHERE id = @b
            """, ("@b", batchId));
    }

    private static bool IsDraft(MySqlConnection c, MySqlTransaction tx, int batchId)
    {
        var o = Scal(c, tx, "SELECT status FROM deliveries WHERE id = @b FOR UPDATE", ("@b", batchId));
        return o != null && o.ToString() == "draft";
    }

    private bool BatchExists(MySqlConnection c, int batchId) =>
        Scal(c, null, "SELECT id FROM deliveries WHERE id = @b", ("@b", batchId)) != null;

    // The same entry the desktop writes, marked as coming from the mobile app.
    private void AuditDelivery(int userId, string action, string description)
    {
        try
        {
            using var c = OpenDb();
            var username = Scal(c, null, "SELECT username FROM users WHERE id = @id", ("@id", userId)) as string;

            Exec(c, null, """
                INSERT INTO audit_trail
                    (user_id, username, action, module, description, device_name)
                VALUES (@uid, @un, @a, 'Delivery', @d, 'Mobile API')
                """,
                ("@uid", userId > 0 ? (object)userId : null),
                ("@un", username),
                ("@a", action),
                ("@d", description));
        }
        catch
        {
            // Audit logging must not break the request.
        }
    }

    // ---------------- reading ----------------
    public List<SupplierDto> GetSuppliers()
    {
        using var c = OpenDb();
        using var cmd = new MySqlCommand(
            "SELECT id, company_name, company_address, name FROM suppliers " +
            "ORDER BY company_name, company_address", c);
        using var r = cmd.ExecuteReader();

        var list = new List<SupplierDto>();
        while (r.Read())
        {
            list.Add(new SupplierDto(
                Convert.ToInt32(r["id"]),
                r["company_name"].ToString()!,
                r["company_address"].ToString()!,
                r["name"].ToString()!));
        }
        return list;
    }

    // filter: "all", "draft" or "sent". Drafts first.
    public List<BatchDto> GetBatches(string filter)
    {
        var sql = """
            SELECT d.id, d.batch_no, d.status, d.delivery_date, d.total_cost, d.expected_profit,
                   s.company_name, s.company_address, s.name AS contact,
                   (SELECT COUNT(*) FROM delivery_items i WHERE i.delivery_id = d.id) AS item_count
            FROM deliveries d
            INNER JOIN suppliers s ON s.id = d.supplier_id
            WHERE 1 = 1
            """;
        if (filter == "draft") sql += "\nAND d.status = 'draft'";
        if (filter == "sent") sql += "\nAND d.status = 'sent'";
        sql += "\nORDER BY (d.status = 'draft') DESC, d.id DESC LIMIT 300";

        using var c = OpenDb();
        using var cmd = new MySqlCommand(sql, c);
        using var r = cmd.ExecuteReader();

        var list = new List<BatchDto>();
        while (r.Read())
        {
            list.Add(new BatchDto(
                Convert.ToInt32(r["id"]),
                r["batch_no"].ToString()!,
                r["status"].ToString()!,
                Convert.ToDateTime(r["delivery_date"]),
                Convert.ToDecimal(r["total_cost"]),
                Convert.ToDecimal(r["expected_profit"]),
                r["company_name"].ToString()!,
                r["company_address"].ToString()!,
                r["contact"].ToString()!,
                Convert.ToInt32(r["item_count"])));
        }
        return list;
    }

    public BatchDetailDto? GetBatchDetail(int batchId)
    {
        using var c = OpenDb();

        int id, supplierId;
        string batchNo, status, company, address, contact;
        DateTime deliveryDate;
        DateTime? sentAt;
        decimal totalCost, expectedProfit;
        string? createdBy, sentBy;

        using (var cmd = new MySqlCommand("""
            SELECT d.id, d.batch_no, d.status, d.delivery_date, d.supplier_id,
                   d.total_cost, d.expected_profit, d.sent_at,
                   s.company_name, s.company_address, s.name AS contact,
                   (SELECT u.full_name FROM users u WHERE u.id = d.created_by) AS created_by_name,
                   (SELECT u.full_name FROM users u WHERE u.id = d.sent_by) AS sent_by_name
            FROM deliveries d
            INNER JOIN suppliers s ON s.id = d.supplier_id
            WHERE d.id = @id
            """, c))
        {
            cmd.Parameters.AddWithValue("@id", batchId);
            using var r = cmd.ExecuteReader();
            if (!r.Read()) return null;

            id = Convert.ToInt32(r["id"]);
            batchNo = r["batch_no"].ToString()!;
            status = r["status"].ToString()!;
            deliveryDate = Convert.ToDateTime(r["delivery_date"]);
            supplierId = Convert.ToInt32(r["supplier_id"]);
            totalCost = Convert.ToDecimal(r["total_cost"]);
            expectedProfit = Convert.ToDecimal(r["expected_profit"]);
            sentAt = r["sent_at"] is DBNull ? null : Convert.ToDateTime(r["sent_at"]);
            company = r["company_name"].ToString()!;
            address = r["company_address"].ToString()!;
            contact = r["contact"].ToString()!;
            createdBy = Str(r, "created_by_name");
            sentBy = Str(r, "sent_by_name");
        }

        var items = new List<DeliveryItemDto>();
        using (var cmd = new MySqlCommand("""
            SELECT i.id, i.product_id, p.name, p.measurement, p.barcode, c.name AS category,
                   i.qty, i.qty_remaining, i.cost_price, i.cost_mode, i.pack_size,
                   i.entered_cost, i.selling_price, i.line_cost, i.expected_profit
            FROM delivery_items i
            INNER JOIN products p ON p.id = i.product_id
            INNER JOIN categories c ON c.id = p.category_id
            WHERE i.delivery_id = @b
            ORDER BY i.id
            """, c))
        {
            cmd.Parameters.AddWithValue("@b", batchId);
            using var r = cmd.ExecuteReader();
            while (r.Read())
            {
                items.Add(new DeliveryItemDto(
                    Convert.ToInt32(r["id"]),
                    Convert.ToInt32(r["product_id"]),
                    r["name"].ToString()!,
                    r["measurement"].ToString()!,
                    r["barcode"].ToString()!,
                    r["category"].ToString()!,
                    Convert.ToInt32(r["qty"]),
                    Convert.ToInt32(r["qty_remaining"]),
                    Convert.ToDecimal(r["cost_price"]),
                    r["cost_mode"].ToString()!,
                    Convert.ToInt32(r["pack_size"]),
                    Convert.ToDecimal(r["entered_cost"]),
                    Convert.ToDecimal(r["selling_price"]),
                    Convert.ToDecimal(r["line_cost"]),
                    Convert.ToDecimal(r["expected_profit"])));
            }
        }

        return new BatchDetailDto(
            id, batchNo, status, deliveryDate, supplierId, totalCost, expectedProfit, sentAt,
            company, address, contact, createdBy, sentBy, items);
    }

    // What this supplier company charged the last time it delivered this item.
    private const string LastPriceSql = """
        SELECT di.cost_price, di.cost_mode, di.pack_size, di.entered_cost,
               di.selling_price, d.batch_no, d.delivery_date, s.company_name
        FROM delivery_items di
        INNER JOIN deliveries d ON d.id = di.delivery_id AND d.status = 'sent'
        INNER JOIN suppliers s ON s.id = d.supplier_id
        WHERE di.product_id = @p AND s.company_name =
              (SELECT s2.company_name FROM deliveries d2
               INNER JOIN suppliers s2 ON s2.id = d2.supplier_id WHERE d2.id = @b)
        ORDER BY d.sent_at DESC, d.id DESC
        LIMIT 1
        """;

    private static LastPriceDto? ReadLastPrice(
        MySqlConnection c, MySqlTransaction? tx, int batchId, int productId)
    {
        using var cmd = MakeCmd(c, tx, LastPriceSql, new (string, object?)[] { ("@p", productId), ("@b", batchId) });
        using var r = cmd.ExecuteReader();
        if (!r.Read()) return null;

        return new LastPriceDto(
            Convert.ToDecimal(r["cost_price"]),
            r["cost_mode"].ToString()!,
            Convert.ToInt32(r["pack_size"]),
            Convert.ToDecimal(r["entered_cost"]),
            Convert.ToDecimal(r["selling_price"]),
            r["batch_no"].ToString()!,
            Convert.ToDateTime(r["delivery_date"]),
            r["company_name"].ToString()!);
    }

    public LastPriceDto? GetLastSupplierPrice(int batchId, int productId)
    {
        using var c = OpenDb();
        return ReadLastPrice(c, null, batchId, productId);
    }

    // ---------------- batches ----------------
    public BatchOutcome CreateDeliveryBatch(int supplierId, DateTime deliveryDate, int userId)
    {
        if (deliveryDate.Date > DateTime.Today) return new BatchOutcome(BatchResult.BadDate);

        for (int attempt = 1; attempt <= 5; attempt++)
        {
            using var c = OpenDb();

            string prefix = "DEL-" + deliveryDate.Year + "-";
            var last = Scal(c, null,
                "SELECT COALESCE(MAX(CAST(SUBSTRING(batch_no, 10) AS UNSIGNED)), 0) " +
                "FROM deliveries WHERE batch_no LIKE @p",
                ("@p", prefix + "%"));
            string batchNo = prefix + (Convert.ToInt32(last) + 1).ToString("0000");

            try
            {
                using var cmd = new MySqlCommand(
                    "INSERT INTO deliveries (batch_no, supplier_id, status, delivery_date, created_by) " +
                    "VALUES (@n, @s, 'draft', @d, @u)", c);
                cmd.Parameters.AddWithValue("@n", batchNo);
                cmd.Parameters.AddWithValue("@s", supplierId);
                cmd.Parameters.AddWithValue("@d", deliveryDate.Date);
                cmd.Parameters.AddWithValue("@u", userId > 0 ? (object)userId : DBNull.Value);
                cmd.ExecuteNonQuery();
                int newId = Convert.ToInt32(cmd.LastInsertedId);

                AuditDelivery(userId, "ADD",
                    "Started delivery batch " + batchNo + " (id " + newId + ") from the mobile app");
                return new BatchOutcome(BatchResult.Ok, newId, batchNo);
            }
            catch (MySqlException ex) when (ex.Number == 1062)
            {
                // someone took this number a moment ago: try the next one
            }
            catch (MySqlException ex) when (ex.Number == 1452)
            {
                return new BatchOutcome(BatchResult.NotFound);
            }
        }
        return new BatchOutcome(BatchResult.Failed);
    }

    public BatchResult UpdateDeliveryBatch(int batchId, int supplierId, DateTime deliveryDate, int userId)
    {
        if (deliveryDate.Date > DateTime.Today) return BatchResult.BadDate;

        try
        {
            using var c = OpenDb();
            int rows = Exec(c, null,
                "UPDATE deliveries SET supplier_id = @s, delivery_date = @d " +
                "WHERE id = @id AND status = 'draft'",
                ("@s", supplierId), ("@d", deliveryDate.Date), ("@id", batchId));

            var status = Scal(c, null, "SELECT status FROM deliveries WHERE id = @id", ("@id", batchId))?.ToString();
            if (status == null) return BatchResult.NotFound;
            if (status != "draft") return BatchResult.NotDraft;

            var no = Scal(c, null, "SELECT batch_no FROM deliveries WHERE id = @id", ("@id", batchId));
            AuditDelivery(userId, "EDIT", "Changed details of batch " + no + " from the mobile app");
            return BatchResult.Ok;
        }
        catch (MySqlException ex) when (ex.Number == 1452)
        {
            return BatchResult.NotFound;
        }
    }

    public BatchResult DeleteDeliveryBatch(int batchId, int userId)
    {
        using var c = OpenDb();
        var no = Scal(c, null, "SELECT batch_no FROM deliveries WHERE id = @id", ("@id", batchId));
        int rows = Exec(c, null,
            "DELETE FROM deliveries WHERE id = @id AND status = 'draft'", ("@id", batchId));

        if (rows == 1)
        {
            AuditDelivery(userId, "DELETE", "Deleted draft batch " + no + " from the mobile app");
            return BatchResult.Ok;
        }
        return BatchExists(c, batchId) ? BatchResult.NotDraft : BatchResult.NotFound;
    }

    // ---------------- lines ----------------
    // costMode "piece": quantity is pieces, enteredCost is the cost of ONE piece.
    // costMode "pack":  quantity is packs, packSize is pieces per pack, enteredCost is the cost of ONE pack.
    public BatchResult SaveDeliveryItem(
        int batchId, int productId, int quantity, string costMode, int packSize,
        decimal enteredCost, decimal price, bool costChangeConfirmed, int userId)
    {
        bool byPack = costMode == "pack";
        if (!byPack) packSize = 1;

        if (quantity <= 0 || enteredCost <= 0m || price <= 0m || (byPack && packSize < 2))
            return BatchResult.Invalid;
        if ((long)quantity * packSize > 2000000000L) return BatchResult.Invalid;

        int pieces = quantity * packSize;
        decimal unitCost = byPack
            ? Math.Round(enteredCost / packSize, 4, MidpointRounding.AwayFromZero)
            : enteredCost;
        if (unitCost < 0.0001m) return BatchResult.Invalid;

        decimal lineCost = Math.Round(
            byPack ? quantity * enteredCost : pieces * enteredCost,
            2, MidpointRounding.AwayFromZero);
        decimal profit = pieces * price - lineCost;
        string modeText = byPack ? "pack" : "piece";

        LastPriceDto? last;
        string batchNo;

        using (var c = OpenDb())
        using (var tx = c.BeginTransaction())
        {
            try
            {
                if (!IsDraft(c, tx, batchId))
                {
                    tx.Rollback();
                    return BatchExists(c, batchId) ? BatchResult.NotDraft : BatchResult.NotFound;
                }

                // the cost is locked to what this supplier charged last time (per piece),
                // unless the change was confirmed
                last = ReadLastPrice(c, tx, batchId, productId);
                if (!costChangeConfirmed && last != null &&
                    Math.Abs(unitCost - last.CostPrice) > 0.00005m)
                {
                    tx.Rollback();
                    return BatchResult.PriceLocked;
                }

                var existing = Scal(c, tx,
                    "SELECT id FROM delivery_items WHERE delivery_id = @b AND product_id = @p LIMIT 1",
                    ("@b", batchId), ("@p", productId));

                if (existing != null)
                {
                    Exec(c, tx, """
                        UPDATE delivery_items SET qty = @q, cost_price = @c, cost_mode = @m,
                               pack_size = @k, entered_cost = @e, selling_price = @s,
                               line_cost = @lc, expected_profit = @ep
                        WHERE id = @id
                        """,
                        ("@q", pieces), ("@c", unitCost), ("@m", modeText), ("@k", packSize),
                        ("@e", enteredCost), ("@s", price), ("@lc", lineCost), ("@ep", profit),
                        ("@id", Convert.ToInt32(existing)));
                }
                else
                {
                    Exec(c, tx, """
                        INSERT INTO delivery_items
                            (delivery_id, product_id, qty, qty_remaining, cost_price, cost_mode,
                             pack_size, entered_cost, selling_price, line_cost, expected_profit)
                        VALUES (@b, @p, @q, 0, @c, @m, @k, @e, @s, @lc, @ep)
                        """,
                        ("@b", batchId), ("@p", productId), ("@q", pieces), ("@c", unitCost),
                        ("@m", modeText), ("@k", packSize), ("@e", enteredCost), ("@s", price),
                        ("@lc", lineCost), ("@ep", profit));
                }

                RecalcTotals(c, tx, batchId);
                batchNo = Scal(c, tx, "SELECT batch_no FROM deliveries WHERE id = @b", ("@b", batchId))?.ToString() ?? "";
                tx.Commit();
            }
            catch (MySqlException)
            {
                tx.Rollback();
                return BatchResult.Failed;
            }
        }

        // a confirmed supplier price change is recorded in the audit trail
        if (costChangeConfirmed && last != null && Math.Abs(unitCost - last.CostPrice) > 0.00005m)
        {
            AuditDelivery(userId, "PRICE_CHANGE",
                "Supplier price changed from " + last.CompanyName + " for product id " + productId +
                ": " + last.CostPrice.ToString("0.####") + " to " + unitCost.ToString("0.####") +
                " per piece (batch " + batchNo + ", mobile app)");
        }

        return BatchResult.Ok;
    }

    public BatchResult RemoveDeliveryItem(int batchId, int itemId)
    {
        using var c = OpenDb();
        using var tx = c.BeginTransaction();
        try
        {
            if (!IsDraft(c, tx, batchId))
            {
                tx.Rollback();
                return BatchExists(c, batchId) ? BatchResult.NotDraft : BatchResult.NotFound;
            }

            Exec(c, tx, "DELETE FROM delivery_items WHERE id = @i AND delivery_id = @b",
                ("@i", itemId), ("@b", batchId));
            RecalcTotals(c, tx, batchId);
            tx.Commit();
            return BatchResult.Ok;
        }
        catch (MySqlException)
        {
            tx.Rollback();
            return BatchResult.Failed;
        }
    }

    // Puts the batch into inventory: stock goes up, the latest cost and selling price are saved
    // on each product, every item gets a stock-in movement, and the batch is locked. All or nothing.
    public BatchResult SendDeliveryBatch(int batchId, int userId)
    {
        string batchNo = "";
        int lines = 0, units = 0;
        decimal totalCost = 0m, totalProfit = 0m;

        using (var c = OpenDb())
        using (var tx = c.BeginTransaction())
        {
            try
            {
                if (!IsDraft(c, tx, batchId))
                {
                    tx.Rollback();
                    return BatchExists(c, batchId) ? BatchResult.NotDraft : BatchResult.NotFound;
                }

                var items = new List<(int Id, int ProductId, int Qty, decimal Cost, decimal Price, decimal LineCost, decimal Profit)>();
                using (var cmd = MakeCmd(c, tx,
                    "SELECT id, product_id, qty, cost_price, selling_price, line_cost, expected_profit " +
                    "FROM delivery_items WHERE delivery_id = @b",
                    new (string, object?)[] { ("@b", batchId) }))
                using (var r = cmd.ExecuteReader())
                {
                    while (r.Read())
                    {
                        items.Add((
                            Convert.ToInt32(r["id"]),
                            Convert.ToInt32(r["product_id"]),
                            Convert.ToInt32(r["qty"]),
                            Convert.ToDecimal(r["cost_price"]),
                            Convert.ToDecimal(r["selling_price"]),
                            Convert.ToDecimal(r["line_cost"]),
                            Convert.ToDecimal(r["expected_profit"])));
                    }
                }

                if (items.Count == 0)
                {
                    tx.Rollback();
                    return BatchResult.Empty;
                }

                foreach (var it in items)
                {
                    Exec(c, tx,
                        "UPDATE products SET qty_on_hand = qty_on_hand + @q, cost_price = @c, " +
                        "selling_price = @s WHERE id = @p",
                        ("@q", it.Qty), ("@c", it.Cost), ("@s", it.Price), ("@p", it.ProductId));

                    int balance = Convert.ToInt32(Scal(c, tx,
                        "SELECT qty_on_hand FROM products WHERE id = @p", ("@p", it.ProductId)));

                    Exec(c, tx, """
                        INSERT INTO inventory_movements
                            (product_id, movement_type, qty_change, balance_after,
                             reference_type, reference_id, user_id)
                        VALUES (@p, 'delivery_in', @q, @bal, 'delivery', @b, @u)
                        """,
                        ("@p", it.ProductId), ("@q", it.Qty), ("@bal", balance),
                        ("@b", batchId), ("@u", userId > 0 ? (object)userId : null));

                    Exec(c, tx, "UPDATE delivery_items SET qty_remaining = qty WHERE id = @i", ("@i", it.Id));

                    lines++;
                    units += it.Qty;
                    totalCost += it.LineCost;
                    totalProfit += it.Profit;
                }

                RecalcTotals(c, tx, batchId);
                Exec(c, tx,
                    "UPDATE deliveries SET status = 'sent', sent_by = @u, sent_at = NOW() WHERE id = @b",
                    ("@u", userId > 0 ? (object)userId : null), ("@b", batchId));

                batchNo = Scal(c, tx, "SELECT batch_no FROM deliveries WHERE id = @b", ("@b", batchId))?.ToString() ?? "";
                tx.Commit();
            }
            catch (MySqlException)
            {
                tx.Rollback();
                return BatchResult.Failed;
            }
        }

        AuditDelivery(userId, "SEND",
            "Sent batch " + batchNo + " to inventory from the mobile app: " + lines + " items (" +
            units + " pcs), total cost " + totalCost.ToString("N2") +
            ", expected profit " + totalProfit.ToString("N2"));
        return BatchResult.Ok;
    }
}

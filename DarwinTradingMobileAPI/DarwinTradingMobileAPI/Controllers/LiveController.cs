using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MySqlConnector;

namespace DarwinTradingMobileAPI.Controllers;

/// <summary>
/// A tiny "has anything changed?" check. The desktop system writes straight to
/// the database, so the phone asks every few seconds and reloads a screen only
/// when its stamp changes.
/// </summary>
[ApiController]
[Authorize]
[Route("api/[controller]")]
public class LiveController : ControllerBase
{
    private readonly string _connectionString;

    public LiveController(IConfiguration configuration)
    {
        _connectionString =
            configuration.GetConnectionString("Dtsims2")
            ?? throw new InvalidOperationException("Database connection string is missing.");
    }

    // GET api/Live/stamp
    [HttpGet("stamp")]
    public IActionResult Stamp()
    {
        using var c = new MySqlConnection(_connectionString);
        c.Open();

        using var cmd = new MySqlCommand("""
            SELECT
                (SELECT CONCAT_WS('|', COUNT(*), COALESCE(MAX(updated_at), 0),
                                  COALESCE(SUM(qty_on_hand), 0), COALESCE(SUM(selling_price), 0))
                 FROM products),
                (SELECT CONCAT_WS('|', COUNT(*), COALESCE(MAX(id), 0)) FROM categories),
                (SELECT CONCAT_WS('|', COUNT(*), COALESCE(MAX(id), 0), COALESCE(SUM(status = 'sent'), 0),
                                  COALESCE(SUM(total_cost), 0), COALESCE(SUM(supplier_id), 0),
                                  COALESCE(SUM(TO_DAYS(delivery_date)), 0))
                 FROM deliveries),
                (SELECT CONCAT_WS('|', COUNT(*), COALESCE(SUM(qty), 0), COALESCE(SUM(cost_price), 0))
                 FROM delivery_items),
                (SELECT CONCAT_WS('|', COUNT(*), COALESCE(MAX(updated_at), 0), COALESCE(MAX(id), 0))
                 FROM suppliers)
            """, c);

        using var r = cmd.ExecuteReader();
        r.Read();

        return Ok(new
        {
            products = Convert.ToString(r[0]) + "#" + Convert.ToString(r[1]),
            deliveries = Convert.ToString(r[2]) + "#" + Convert.ToString(r[3]),
            suppliers = Convert.ToString(r[4])
        });
    }
}
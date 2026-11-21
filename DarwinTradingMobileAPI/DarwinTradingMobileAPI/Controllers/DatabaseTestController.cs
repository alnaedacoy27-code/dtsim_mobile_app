
using Microsoft.AspNetCore.Mvc;
using MySqlConnector;

namespace DarwinTradingMobileAPI.Controllers;

[ApiController]
[Route("api/diagnostics/database")]
public class DatabaseTestController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<DatabaseTestController> _logger;

    public DatabaseTestController(
        IConfiguration configuration,
        ILogger<DatabaseTestController> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [HttpGet]
    public async Task<IActionResult> TestConnection()
    {
        var connectionString =
            _configuration.GetConnectionString("Dtsims2");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return StatusCode(500, new
            {
                status = "Error",
                message = "Database connection settings are missing."
            });
        }

        try
        {
            await using var connection =
                new MySqlConnection(connectionString);

            await connection.OpenAsync();

            return Ok(new
            {
                status = "Connected",
                database = "dtsims2_db"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Database connection test failed.");

            return StatusCode(503, new
            {
                status = "Error",
                message = "Could not connect to the database. Check the API logs."
            });
        }
    }
}

using DarwinTradingMobileAPI.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;

namespace DarwinTradingMobileAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly AuthService _authService;
    private readonly SessionService _sessions;
    private readonly IConfiguration _configuration;

    public AuthController(
        AuthService authService,
        SessionService sessions,
        IConfiguration configuration)
    {
        _authService = authService;
        _sessions = sessions;
        _configuration = configuration;
    }

    // Module keys that make up the mobile app.
    private static readonly string[] MobileModules = { "dashboard", "delivery", "products" };

    public class LoginRequest
    {
        public string Username { get; set; } = "";
        public string Password { get; set; } = "";
        public string? DeviceName { get; set; }
    }

    [AllowAnonymous]
    [HttpPost("login")]
    public IActionResult Login([FromBody] LoginRequest request)
    {
        var result = _authService.Login(
            request.Username,
            request.Password);

        if (!result.Success)
        {
            return Unauthorized(new { message = result.Message });
        }
        var permissions = _authService.GetPermissions(
            result.UserId,
            result.Role);

        // The user logged in correctly, but must be allowed into at least
        // one mobile module to use this application.
        bool hasMobileAccess = MobileModules.Any(
            module => permissions.TryGetValue(module, out var allowed) && allowed);

        if (!hasMobileAccess)
        {
            _authService.LogAccessDenied(result.UserId, result.Username);

            return StatusCode(StatusCodes.Status403Forbidden, new
            {
                code = "NO_ACCESS",
                message = "You don't have access to this application."
            });
        }

        var jwtKey = _configuration["Jwt:Key"]!;
        var issuer = _configuration["Jwt:Issuer"]!;
        var audience = _configuration["Jwt:Audience"]!;

        // Record this login in user_sessions so the desktop's User Monitoring
        // can see who is using the mobile app.
        var device = "Mobile App" +
            (string.IsNullOrWhiteSpace(request.DeviceName) ? "" : " (" + request.DeviceName.Trim() + ")");

        var sessionId = _sessions.StartSession(
            result.UserId,
            result.Username,
            device,
            HttpContext.Connection.RemoteIpAddress?.MapToIPv4().ToString());

        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, result.UserId.ToString()),
            new Claim(ClaimTypes.Name, result.Username),
            new Claim(ClaimTypes.Role, result.Role)
        };

        if (sessionId != null)
        {
            claims.Add(new Claim("msid", sessionId));
        }

        var key = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(jwtKey));

        var credentials = new SigningCredentials(
            key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            expires: DateTime.UtcNow.AddHours(8),
            signingCredentials: credentials);

        return Ok(new
        {
            message = result.Message,
            token = new JwtSecurityTokenHandler().WriteToken(token),
            user = new
            {
                id = result.UserId,
                username = result.Username,
                fullName = result.FullName,
                role = result.Role
            },
            permissions = permissions
        });
    }
}
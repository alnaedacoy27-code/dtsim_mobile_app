using DarwinTradingMobileAPI.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace DarwinTradingMobileAPI.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class SessionController : ControllerBase
{
    private readonly SessionService _sessions;

    public SessionController(SessionService sessions)
    {
        _sessions = sessions;
    }

    public class ModuleRequest
    {
        public string? Module { get; set; }
    }

    // POST api/Session/heartbeat  (every request already refreshes the
    // session; the app calls this while idle so it still shows as online)
    [HttpPost("heartbeat")]
    public IActionResult Heartbeat() => Ok(new { ok = true });

    // POST api/Session/module   { module: "delivery" }
    [HttpPost("module")]
    public IActionResult SetModule([FromBody] ModuleRequest r)
    {
        if (r.Module == null ||
            !SessionService.ModuleLabels.TryGetValue(r.Module.Trim(), out var label))
            return BadRequest(new { message = "Unknown module." });

        var sid = User.FindFirstValue("msid");
        if (!string.IsNullOrEmpty(sid)) _sessions.SetModule(sid, label);
        return Ok(new { ok = true });
    }

    // POST api/Session/logout
    [HttpPost("logout")]
    public IActionResult Logout()
    {
        var sid = User.FindFirstValue("msid");
        if (!string.IsNullOrEmpty(sid)) _sessions.EndSession(sid, "Logged out");

        var username = User.FindFirstValue(ClaimTypes.Name) ?? "";
        int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId);
        _sessions.Audit(userId, username, "LOGOUT", $"'{username}' logged out");

        return Ok(new { ok = true });
    }
}
using DarwinTradingMobileAPI.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace DarwinTradingMobileAPI.Controllers;

/// <summary>
/// Suppliers for the phone app: list, details (with the last deliveries), add and edit.
/// Needs the desktop's "Suppliers" permission (File Maintenance), checked on every request.
/// Deleting stays on the desktop.
/// </summary>
[ApiController]
[Authorize]
[Route("api/[controller]")]
public class SuppliersController : ControllerBase
{
    private const string Module = "suppliers";

    private readonly AuthService _auth;
    private readonly SupplierService _suppliers;

    public SuppliersController(AuthService auth, SupplierService suppliers)
    {
        _auth = auth;
        _suppliers = suppliers;
    }

    public class SupplierRequest
    {
        public string? CompanyName { get; set; }
        public string? ContactPerson { get; set; }
        public string? ContactNumber { get; set; }
        public string? Address { get; set; }
        public string? Email { get; set; }
    }

    // GET api/Suppliers?search=
    [HttpGet]
    public IActionResult List([FromQuery] string? search)
    {
        if (!HasAccess()) return NoAccess();
        return Ok(_suppliers.List(search));
    }

    // GET api/Suppliers/5
    [HttpGet("{id:int}")]
    public IActionResult Get(int id)
    {
        if (!HasAccess()) return NoAccess();
        var s = _suppliers.Get(id);
        return s == null ? NotFound(new { message = "This supplier no longer exists." }) : Ok(s);
    }

    // POST api/Suppliers   { companyName, contactPerson, contactNumber, address, email? }
    [HttpPost]
    public IActionResult Create([FromBody] SupplierRequest r)
    {
        if (!HasAccess()) return NoAccess();
        var o = _suppliers.Create(r.CompanyName, r.ContactPerson, r.ContactNumber, r.Address, r.Email, CurrentUserId());
        return o.Result == SupplierResult.Ok ? Ok(_suppliers.Get(o.Id)) : Fail(o);
    }

    // PUT api/Suppliers/5
    [HttpPut("{id:int}")]
    public IActionResult Update(int id, [FromBody] SupplierRequest r)
    {
        if (!HasAccess()) return NoAccess();
        var o = _suppliers.Update(id, r.CompanyName, r.ContactPerson, r.ContactNumber, r.Address, r.Email, CurrentUserId());
        return o.Result == SupplierResult.Ok ? Ok(_suppliers.Get(id)) : Fail(o);
    }

    private IActionResult Fail(SupplierOutcome o) => o.Result switch
    {
        SupplierResult.Invalid => BadRequest(new { message = o.Message }),
        SupplierResult.NotFound => NotFound(new { message = o.Message }),
        SupplierResult.DuplicateAddress => Conflict(new { code = "DUPLICATE_ADDRESS", message = o.Message }),
        SupplierResult.NumberTaken => Conflict(new { code = "NUMBER_TAKEN", message = o.Message }),
        _ => StatusCode(500, new { message = "Something went wrong. Check the API logs." })
    };

    private IActionResult NoAccess() =>
        StatusCode(StatusCodes.Status403Forbidden, new
        {
            code = "NO_ACCESS",
            message = "You don't have access to suppliers."
        });

    private int CurrentUserId()
    {
        var idText =
            User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? User.FindFirstValue("nameid")
            ?? User.FindFirstValue("sub");
        return int.TryParse(idText, out var id) ? id : 0;
    }

    // Checked on every request (like ProductsController): a permission change on the desktop applies at once.
    private bool HasAccess()
    {
        var role = User.FindFirstValue(ClaimTypes.Role) ?? User.FindFirstValue("role") ?? "";
        var userId = CurrentUserId();
        if (userId <= 0) return false;

        var permissions = _auth.GetPermissions(userId, role);
        if (!MobileAccess.CanUseApp(permissions, role)) return false;
        return permissions.TryGetValue(Module, out var allowed) && allowed;
    }
}

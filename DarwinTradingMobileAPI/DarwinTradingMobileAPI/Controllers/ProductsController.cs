using DarwinTradingMobileAPI.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace DarwinTradingMobileAPI.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    private readonly AuthService _service;
    private readonly ProductService _products;

    public ProductsController(AuthService service, ProductService products)
    {
        _service = service;
        _products = products;
    }

    public class ProductRequest
    {
        public string? Name { get; set; }
        public int CategoryId { get; set; }
        public string? Measurement { get; set; }
        /// <summary>Leave empty to have the system generate one.</summary>
        public string? Barcode { get; set; }
        public int LowStockThreshold { get; set; }
    }

    public class CategoryRequest
    {
        public string? Name { get; set; }
        public string? Description { get; set; }
    }

    // GET api/Products?search=&categoryId=&stock=all|low|out&page=1&pageSize=50
    [HttpGet]
    public IActionResult GetProducts(
        [FromQuery] string? search,
        [FromQuery] int? categoryId,
        [FromQuery] string? stock,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        if (!HasAccess("products")) return NoAccess();

        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var stockFilter = (stock ?? "all").Trim().ToLowerInvariant();
        if (stockFilter != "low" && stockFilter != "out")
        {
            stockFilter = "all";
        }

        return Ok(_service.GetProducts(
            search, categoryId, stockFilter, page, pageSize));
    }

    // GET api/Products/5
    [HttpGet("{id:int}")]
    public IActionResult GetProduct(int id)
    {
        if (!HasAccess("products")) return NoAccess();

        var product = _service.GetProduct(id);
        if (product == null)
        {
            return NotFound(new { message = "Product not found." });
        }

        return Ok(product);
    }

    // POST api/Products   { name, categoryId, measurement, barcode?, lowStockThreshold }
    [HttpPost]
    public IActionResult CreateProduct([FromBody] ProductRequest r)
    {
        if (!HasAccess("products")) return NoAccess();

        var outcome = _products.CreateProduct(
            r.Name, r.CategoryId, r.Measurement, r.Barcode,
            r.LowStockThreshold, CurrentUserId());

        if (outcome.Result != ProductResult.Ok) return Fail(outcome);

        return Ok(_service.GetProduct(outcome.Id)?.Product);
    }

    // PUT api/Products/5
    [HttpPut("{id:int}")]
    public IActionResult UpdateProduct(int id, [FromBody] ProductRequest r)
    {
        if (!HasAccess("products")) return NoAccess();

        var outcome = _products.UpdateProduct(
            id, r.Name, r.CategoryId, r.Measurement, r.Barcode,
            r.LowStockThreshold, CurrentUserId());

        if (outcome.Result != ProductResult.Ok) return Fail(outcome);

        return Ok(_service.GetProduct(id)?.Product);
    }

    // GET api/Products/categories
    [HttpGet("categories")]
    public IActionResult GetCategories()
    {
        if (!HasAccess("products")) return NoAccess();

        return Ok(_service.GetCategories());
    }

    // POST api/Products/categories   { name, description? }
    [HttpPost("categories")]
    public IActionResult CreateCategory([FromBody] CategoryRequest r)
    {
        if (!HasAccess("products")) return NoAccess();

        var outcome = _products.CreateCategory(r.Name, r.Description, CurrentUserId());

        if (outcome.Result != ProductResult.Ok)
            return Fail(new ProductOutcome(outcome.Result, 0, outcome.Message));

        return Ok(new AuthService.CategoryDto(outcome.Id, outcome.Name, 0));
    }

    // GET api/Dashboard/summary (needs the "dashboard" permission)
    [HttpGet("~/api/Dashboard/summary")]
    public IActionResult GetDashboardSummary()
    {
        if (!HasAccess("dashboard")) return NoAccess();

        return Ok(_service.GetDashboardSummary());
    }

    private IActionResult Fail(ProductOutcome o) => o.Result switch
    {
        ProductResult.Invalid => BadRequest(new { message = o.Message }),
        ProductResult.BadCategory => BadRequest(new { message = o.Message }),
        ProductResult.NotFound => NotFound(new { message = o.Message }),
        ProductResult.DuplicateBarcode => Conflict(new { code = "DUPLICATE_BARCODE", message = o.Message }),
        ProductResult.DuplicateCategory => Conflict(new { code = "DUPLICATE_CATEGORY", message = o.Message }),
        ProductResult.DuplicateProduct => Conflict(new { code = "DUPLICATE_PRODUCT", message = o.Message }),
        _ => StatusCode(500, new { message = "Something went wrong. Check the API logs." })
    };

    private IActionResult NoAccess() =>
        StatusCode(StatusCodes.Status403Forbidden, new
        {
            code = "NO_ACCESS",
            message = "You don't have access to this feature."
        });

    private int CurrentUserId()
    {
        var idText =
            User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? User.FindFirstValue("nameid")
            ?? User.FindFirstValue("sub");

        return int.TryParse(idText, out var id) ? id : 0;
    }

    // Checked on every request, so a permission change in the main system
    // takes effect without waiting for the token to expire.
    private bool HasAccess(string module)
    {
        // Depending on the .NET JWT handler, claim names are either the long
        // ClaimTypes URIs or the short JWT names, so accept both.
        var role =
            User.FindFirstValue(ClaimTypes.Role)
            ?? User.FindFirstValue("role")
            ?? "";

        var userId = CurrentUserId();
        if (userId <= 0) return false;

        var permissions = _service.GetPermissions(userId, role);

        // The phone app permission is checked on every request too, so taking it away
        // in Permission Maintenance stops a phone that is already signed in.
        if (!MobileAccess.CanUseApp(permissions, role)) return false;

        return permissions.TryGetValue(module, out var allowed) && allowed;
    }
}
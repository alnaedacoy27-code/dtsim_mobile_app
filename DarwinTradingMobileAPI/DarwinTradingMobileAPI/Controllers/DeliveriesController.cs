using DarwinTradingMobileAPI.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace DarwinTradingMobileAPI.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class DeliveriesController : ControllerBase
{
    private readonly AuthService _service;

    public DeliveriesController(AuthService service)
    {
        _service = service;
    }

    // ---------------- requests ----------------
    public class BatchRequest
    {
        public int SupplierId { get; set; }
        public DateTime DeliveryDate { get; set; }
    }

    public class ItemRequest
    {
        public int ProductId { get; set; }
        public int Quantity { get; set; }
        public string CostMode { get; set; } = "piece";   // "piece" or "pack"
        public int PackSize { get; set; } = 1;
        public decimal EnteredCost { get; set; }
        public decimal Price { get; set; }
        public bool CostChangeConfirmed { get; set; }
    }

    // ---------------- suppliers ----------------
    // GET api/Deliveries/suppliers
    [HttpGet("suppliers")]
    public IActionResult GetSuppliers()
    {
        if (!HasAccess("delivery")) return NoAccess();
        return Ok(_service.GetSuppliers());
    }

    // ---------------- batches ----------------
    // GET api/Deliveries?filter=all|draft|sent
    [HttpGet]
    public IActionResult GetBatches([FromQuery] string? filter)
    {
        if (!HasAccess("delivery")) return NoAccess();

        var f = (filter ?? "all").Trim().ToLowerInvariant();
        if (f != "draft" && f != "sent") f = "all";

        return Ok(_service.GetBatches(f));
    }

    // GET api/Deliveries/5
    [HttpGet("{id:int}")]
    public IActionResult GetBatch(int id)
    {
        if (!HasAccess("delivery")) return NoAccess();

        var batch = _service.GetBatchDetail(id);
        if (batch == null) return NotFound(new { message = "Batch not found." });
        return Ok(batch);
    }

    // GET api/Deliveries/5/last-price/12   (last price from this supplier for a product)
    [HttpGet("{id:int}/last-price/{productId:int}")]
    public IActionResult GetLastPrice(int id, int productId)
    {
        if (!HasAccess("delivery")) return NoAccess();
        var last = _service.GetLastSupplierPrice(id, productId);
        if (last == null) return Ok(new { found = false });
        return Ok(last);
    }

    // POST api/Deliveries   { supplierId, deliveryDate }
    [HttpPost]
    public IActionResult CreateBatch([FromBody] BatchRequest request)
    {
        if (!HasAccess("delivery")) return NoAccess();

        var outcome = _service.CreateDeliveryBatch(
            request.SupplierId, request.DeliveryDate, CurrentUserId());

        if (outcome.Result != BatchResult.Ok) return Problem(outcome.Result);
        return Ok(new { id = outcome.Id, batchNo = outcome.BatchNo });
    }

    // PUT api/Deliveries/5   { supplierId, deliveryDate }
    [HttpPut("{id:int}")]
    public IActionResult UpdateBatch(int id, [FromBody] BatchRequest request)
    {
        if (!HasAccess("delivery")) return NoAccess();

        var result = _service.UpdateDeliveryBatch(
            id, request.SupplierId, request.DeliveryDate, CurrentUserId());

        return result == BatchResult.Ok ? Ok(new { message = "Saved." }) : Problem(result);
    }

    // DELETE api/Deliveries/5   (drafts only)
    [HttpDelete("{id:int}")]
    public IActionResult DeleteBatch(int id)
    {
        if (!HasAccess("delivery")) return NoAccess();

        var result = _service.DeleteDeliveryBatch(id, CurrentUserId());
        return result == BatchResult.Ok ? Ok(new { message = "Deleted." }) : Problem(result);
    }

    // ---------------- lines ----------------
    // POST api/Deliveries/5/items
    [HttpPost("{id:int}/items")]
    public IActionResult SaveItem(int id, [FromBody] ItemRequest r)
    {
        if (!HasAccess("delivery")) return NoAccess();

        var result = _service.SaveDeliveryItem(
            id, r.ProductId, r.Quantity, r.CostMode, r.PackSize,
            r.EnteredCost, r.Price, r.CostChangeConfirmed, CurrentUserId());

        return result == BatchResult.Ok ? Ok(new { message = "Saved." }) : Problem(result);
    }

    // DELETE api/Deliveries/5/items/9
    [HttpDelete("{id:int}/items/{itemId:int}")]
    public IActionResult RemoveItem(int id, int itemId)
    {
        if (!HasAccess("delivery")) return NoAccess();

        var result = _service.RemoveDeliveryItem(id, itemId);
        return result == BatchResult.Ok ? Ok(new { message = "Removed." }) : Problem(result);
    }

    // POST api/Deliveries/5/send   (puts the batch into inventory)
    [HttpPost("{id:int}/send")]
    public IActionResult SendBatch(int id)
    {
        if (!HasAccess("delivery")) return NoAccess();

        var result = _service.SendDeliveryBatch(id, CurrentUserId());
        return result == BatchResult.Ok ? Ok(new { message = "Sent to inventory." }) : Problem(result);
    }

    // ---------------- helpers ----------------
    private IActionResult Problem(BatchResult result)
    {
        return result switch
        {
            BatchResult.NotFound => NotFound(new { message = "Batch or supplier not found." }),
            BatchResult.NotDraft => Conflict(new { message = "This batch was already sent or changed." }),
            BatchResult.Empty => BadRequest(new { message = "The batch has no items yet." }),
            BatchResult.BadDate => BadRequest(new { message = "The delivery date cannot be in the future." }),
            BatchResult.Invalid => BadRequest(new { message = "Check the quantity, cost and selling price." }),
            BatchResult.PriceLocked => Conflict(new { code = "PRICE_LOCKED", message = "The supplier's cost price for this item is locked." }),
            _ => StatusCode(500, new { message = "Something went wrong. Check the API logs." })
        };
    }

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

    private bool HasAccess(string module)
    {`
        var role =
            User.FindFirstValue(ClaimTypes.Role)
            ?? User.FindFirstValue("role")
            ?? "";

        var userId = CurrentUserId();
        if (userId <= 0) return false;

        var permissions = _service.GetPermissions(userId, role);
        // The phone app permission is checked on every request too.
        if (!MobileAccess.CanUseApp(permissions, role)) return false;

        return permissions.TryGetValue(module, out var allowed) && allowed;
    }
}
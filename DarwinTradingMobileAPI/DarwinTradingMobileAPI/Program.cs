using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using DarwinTradingMobileAPI.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<ProductService>();
builder.Services.AddSingleton<SessionService>();
builder.Services.AddHostedService<DarwinTradingMobileAPI.MobileSessionCleaner>();
builder.Services.AddOpenApi();
builder.Services.AddSwaggerGen();

var jwtKey = builder.Configuration["Jwt:Key"];

if (string.IsNullOrWhiteSpace(jwtKey) ||
    Encoding.UTF8.GetByteCount(jwtKey) < 32)
{
    throw new InvalidOperationException(
        "JWT signing key must be configured and at least 32 bytes long.");
}

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],

            ValidateAudience = true,
            ValidAudience = builder.Configuration["Jwt:Audience"],

            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,

            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwtKey)),

            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddAuthorization();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.UseSwagger();
    app.UseSwaggerUI();
}

if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}

app.UseAuthentication();

// Mobile session tracking: refresh "last seen" on every request and reject a
// session an administrator ended in the desktop's User Monitoring.
app.Use(async (context, next) =>
{
    var sid = context.User.FindFirst("msid")?.Value;

    if (context.User.Identity?.IsAuthenticated == true && !string.IsNullOrEmpty(sid))
    {
        var sessions = context.RequestServices.GetRequiredService<SessionService>();

        if (sessions.Touch(sid) == SessionState.Ended)
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new
            {
                code = "SESSION_ENDED",
                message = "Your session was ended. Please sign in again."
            });
            return;
        }
    }

    await next();
});

app.UseAuthorization();

app.MapControllers();

app.Run();
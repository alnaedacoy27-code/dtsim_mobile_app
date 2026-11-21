using DarwinTradingMobileAPI.Services;

namespace DarwinTradingMobileAPI;

/// <summary>Closes mobile sessions whose phone stopped checking in.</summary>
public class MobileSessionCleaner : BackgroundService
{
    private readonly SessionService _sessions;

    public MobileSessionCleaner(SessionService sessions)
    {
        _sessions = sessions;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            _sessions.ExpireStale(5);

            try { await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken); }
            catch (TaskCanceledException) { }
        }
    }
}
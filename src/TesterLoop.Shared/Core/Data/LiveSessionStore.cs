using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;

namespace TesterLoop.Desktop.Core.Data;

public sealed class LiveSessionStore : IGotrueSessionPersistence<Session>
{
    private readonly object _gate = new();
    private Session? _session;

    public void SaveSession(Session session)
    {
        lock (_gate)
        {
            _session = session;
        }
    }

    public void DestroySession()
    {
        lock (_gate)
        {
            _session = null;
        }
    }

    public Session? LoadSession()
    {
        lock (_gate)
        {
            return _session;
        }
    }

    public Task SaveSessionAsync(Session session, CancellationToken cancellationToken)
    {
        SaveSession(session);
        return Task.CompletedTask;
    }

    public Task DestroySessionAsync(CancellationToken cancellationToken)
    {
        DestroySession();
        return Task.CompletedTask;
    }

    public Task<Session?> LoadSessionAsync(CancellationToken cancellationToken)
        => Task.FromResult(LoadSession());
}

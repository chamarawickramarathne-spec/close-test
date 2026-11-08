namespace TesterLoop.Desktop.Core.Notifications;

public enum NotificationTone
{
    Success,
    Error,
    Info,
}

public sealed class NotificationItem
{
    public NotificationItem(string message, NotificationTone tone)
    {
        Message = message;
        Tone = tone;
        ExpiresAt = DateTime.UtcNow.AddSeconds(5);
    }

    public string Message { get; }

    public NotificationTone Tone { get; }

    public string ToneName => Tone switch
    {
        NotificationTone.Error => "bad",
        NotificationTone.Info => "info",
        _ => "good",
    };

    public string Title => Tone switch
    {
        NotificationTone.Error => "Action failed",
        NotificationTone.Info => "Notice",
        _ => "Done",
    };

    public DateTime ExpiresAt { get; }
}

using System.Collections.ObjectModel;
using System.Windows.Threading;

namespace TesterLoop.Desktop.Core.Notifications;

public sealed class NotificationCenter : ObservableObject
{
    private const int MaxItems = 4;

    private readonly DispatcherTimer _timer;
    private TaskCompletionSource<bool>? _confirm;
    private bool _isConfirmOpen;
    private string _confirmTitle = string.Empty;
    private string _confirmMessage = string.Empty;
    private string _confirmLabel = "Confirm";
    private string _cancelLabel = "Cancel";

    public NotificationCenter()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _timer.Tick += (_, _) => RemoveExpired();
        AcceptConfirmCommand = new RelayCommand(() => CompleteConfirm(true));
        CancelConfirmCommand = new RelayCommand(() => CompleteConfirm(false));
    }

    public ObservableCollection<NotificationItem> Items { get; } = [];

    public RelayCommand AcceptConfirmCommand { get; }

    public RelayCommand CancelConfirmCommand { get; }

    public bool IsConfirmOpen
    {
        get => _isConfirmOpen;
        private set => Set(ref _isConfirmOpen, value);
    }

    public string ConfirmTitle
    {
        get => _confirmTitle;
        private set => Set(ref _confirmTitle, value);
    }

    public string ConfirmMessage
    {
        get => _confirmMessage;
        private set => Set(ref _confirmMessage, value);
    }

    public string ConfirmLabel
    {
        get => _confirmLabel;
        private set => Set(ref _confirmLabel, value);
    }

    public string CancelLabel
    {
        get => _cancelLabel;
        private set => Set(ref _cancelLabel, value);
    }

    public void Success(string message) => Add(message, NotificationTone.Success);

    public void Error(string message) => Add(message, NotificationTone.Error);

    public void Info(string message) => Add(message, NotificationTone.Info);

    public Task<bool> ConfirmAsync(
        string title,
        string message,
        string confirmLabel = "Confirm",
        string cancelLabel = "Cancel")
    {
        if (_confirm is not null)
        {
            return Task.FromResult(false);
        }

        ConfirmTitle = title;
        ConfirmMessage = message;
        ConfirmLabel = confirmLabel;
        CancelLabel = cancelLabel;
        _confirm = new TaskCompletionSource<bool>();
        IsConfirmOpen = true;
        return _confirm.Task;
    }

    private void Add(string message, NotificationTone tone)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return;
        }

        Items.Add(new NotificationItem(message.Trim(), tone));

        while (Items.Count > MaxItems)
        {
            Items.RemoveAt(0);
        }

        if (!_timer.IsEnabled)
        {
            _timer.Start();
        }
    }

    private void RemoveExpired()
    {
        var now = DateTime.UtcNow;

        for (var i = Items.Count - 1; i >= 0; i--)
        {
            if (Items[i].ExpiresAt <= now)
            {
                Items.RemoveAt(i);
            }
        }

        if (Items.Count == 0)
        {
            _timer.Stop();
        }
    }

    private void CompleteConfirm(bool accepted)
    {
        var confirm = _confirm;
        _confirm = null;
        IsConfirmOpen = false;
        confirm?.TrySetResult(accepted);
    }
}

using System.IO;
using System.Net.Http;

namespace TesterLoop.Desktop.Core;

public sealed class UpdateCoordinator : ObservableObject
{
    private readonly UpdateService _service;
    private readonly Action _startInstaller;
    private UpdateInfo? _pending;
    private string _status = string.Empty;
    private bool _isBusy;

    public UpdateCoordinator(UpdateProduct product, Action startInstaller)
    {
        _service = new UpdateService(product);
        _startInstaller = startInstaller;
        UpdateCommand = new AsyncRelayCommand(RunAsync, () => !IsBusy);
    }

    public AsyncRelayCommand UpdateCommand { get; }

    public string ButtonLabel
        => _pending is null ? "Check for updates" : $"Install update {_pending.Version}";

    public string Status
    {
        get => _status;
        private set => Set(ref _status, value);
    }

    public bool HasStatus => !string.IsNullOrWhiteSpace(Status);

    public bool IsBusy
    {
        get => _isBusy;
        private set => Set(ref _isBusy, value);
    }

    public async Task CheckOnStartupAsync()
    {
        if (IsBusy)
        {
            return;
        }

        await CheckAsync(quiet: true);
    }

    private async Task RunAsync()
    {
        if (_pending is null)
        {
            await CheckAsync(quiet: false);
            return;
        }

        await InstallAsync();
    }

    private async Task CheckAsync(bool quiet)
    {
        IsBusy = true;
        if (!quiet)
        {
            Status = "Checking for updates...";
        }

        try
        {
            var update = await _service.CheckAsync();
            _pending = update;

            Status = update is null
                ? $"You are on the latest version (v{AppConfig.AppVersion})."
                : $"Version {update.Version} is available for {_service.ArchitectureLabel}.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            if (!quiet)
            {
                Status = ex.Message;
            }
        }
        finally
        {
            IsBusy = false;
            Refresh();
        }
    }

    private async Task InstallAsync()
    {
        if (_pending is null)
        {
            return;
        }

        IsBusy = true;
        Status = "Downloading update 0%";

        try
        {
            var progress = new Progress<double>(fraction =>
                Status = $"Downloading update {fraction * 100:0}%");

            var path = await _service.DownloadAsync(_pending, progress);
            Status = "Starting the installer...";

            if (!UpdateInstaller.TryStart(path))
            {
                Status = "The installer could not be started. Download it from the releases page.";
                return;
            }

            _startInstaller();
        }
        catch (Exception ex) when (
            ex is InvalidOperationException
                or HttpRequestException
                or IOException
                or UnauthorizedAccessException)
        {
            Status = ex.Message;
        }
        finally
        {
            IsBusy = false;
            Refresh();
        }
    }

    private void Refresh()
    {
        Raise(nameof(ButtonLabel));
        Raise(nameof(HasStatus));
        UpdateCommand.RaiseCanExecuteChanged();
    }
}

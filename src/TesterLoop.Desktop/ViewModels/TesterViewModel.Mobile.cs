using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class TesterViewModel
{
    private string _mobileDevice = string.Empty;
    private DateTime? _mobileDeviceSeenAt;

    public string MobileDeviceLabel
        => string.IsNullOrWhiteSpace(_mobileDevice) ? "Not reported yet" : _mobileDevice;

    public string MobileDeviceNote
        => string.IsNullOrWhiteSpace(_mobileDevice)
            ? "Open TesterLoop Mobile and sign in with this account. The app reports this phone automatically."
            : _mobileDeviceSeenAt is null
                ? "Captured by TesterLoop Mobile on this account."
                : $"Captured by TesterLoop Mobile {Ago(_mobileDeviceSeenAt.Value)}.";

    public bool HasMobileDevice => !string.IsNullOrWhiteSpace(_mobileDevice);

    private void LoadMobileDevice(TesterDto tester)
    {
        _mobileDevice = tester.MobileDeviceName ?? string.Empty;
        _mobileDeviceSeenAt = tester.MobileDeviceSeenAt;

        if (!string.IsNullOrWhiteSpace(_mobileDevice))
        {
            ReportDevice = _mobileDevice;
        }
        else if (string.IsNullOrWhiteSpace(ReportDevice) && tester.Devices.Count > 0)
        {
            ReportDevice = tester.Devices[0];
        }

        Raise(nameof(MobileDeviceLabel));
        Raise(nameof(MobileDeviceNote));
        Raise(nameof(HasMobileDevice));
    }
}

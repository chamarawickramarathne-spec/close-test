namespace TesterLoop.Desktop.Core;

public sealed class NavigationItem : ObservableObject
{
    private bool _isActive;

    public NavigationItem(string label, Action select)
    {
        Label = label;
        Command = new RelayCommand(select);
    }

    public string Label { get; }

    public RelayCommand Command { get; }

    public bool IsActive
    {
        get => _isActive;
        private set => Set(ref _isActive, value);
    }

    public void SetActive(bool active) => IsActive = active;
}

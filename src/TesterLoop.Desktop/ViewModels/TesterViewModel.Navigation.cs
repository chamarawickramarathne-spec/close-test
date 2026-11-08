namespace TesterLoop.Desktop.ViewModels;

public sealed partial class TesterViewModel
{
    private int _selectedTabIndex;

    public int SelectedTabIndex
    {
        get => _selectedTabIndex;
        set => Set(ref _selectedTabIndex, value);
    }
}

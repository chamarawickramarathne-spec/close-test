using System.Windows;

namespace TesterLoop.Admin;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var window = new AdminWindow { DataContext = new ViewModels.AdminAppViewModel() };
        window.Show();
    }
}

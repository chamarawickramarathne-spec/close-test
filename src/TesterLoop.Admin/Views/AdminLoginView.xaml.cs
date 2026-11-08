using System.Windows;
using System.Windows.Controls;
using TesterLoop.Admin.ViewModels;

namespace TesterLoop.Admin.Views;

public partial class AdminLoginView : UserControl
{
    public AdminLoginView()
    {
        InitializeComponent();
        Loaded += (_, _) => EmailInput.Focus();
    }

    private void OnPasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is AdminLoginViewModel viewModel)
        {
            viewModel.Password = PasswordInput.Password;
        }
    }
}

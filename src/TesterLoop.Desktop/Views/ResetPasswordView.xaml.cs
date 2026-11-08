using System.Windows;
using System.Windows.Controls;
using TesterLoop.Desktop.ViewModels;

namespace TesterLoop.Desktop.Views;

public partial class ResetPasswordView : UserControl
{
    public ResetPasswordView()
    {
        InitializeComponent();
    }

    private void OnPasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is ResetPasswordViewModel viewModel)
        {
            viewModel.NewPassword = NewPasswordInput.Password;
        }
    }
}

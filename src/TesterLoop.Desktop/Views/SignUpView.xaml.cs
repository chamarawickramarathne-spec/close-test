using System.Windows;
using System.Windows.Controls;
using TesterLoop.Desktop.ViewModels;

namespace TesterLoop.Desktop.Views;

public partial class SignUpView : UserControl
{
    public SignUpView()
    {
        InitializeComponent();
    }

    private void OnPasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is SignUpViewModel viewModel)
        {
            viewModel.Password = PasswordInput.Password;
        }
    }
}

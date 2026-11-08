using System.Net;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Desktop.ViewModels;

public sealed class ResetPasswordViewModel : ObservableObject
{
    private readonly SupabaseService _service;
    private readonly Action<string> _onDone;

    private string _email = string.Empty;
    private string _token = string.Empty;
    private string _newPassword = string.Empty;
    private string _error = string.Empty;
    private string _message = string.Empty;
    private bool _codeSent;

    public ResetPasswordViewModel(
        SupabaseService service, Action<string> onDone, Action onBack)
    {
        _service = service;
        _onDone = onDone;
        SendCodeCommand = new AsyncRelayCommand(SendCodeAsync);
        ResetCommand = new AsyncRelayCommand(ResetAsync);
        BackCommand = new RelayCommand(onBack);
    }

    public AsyncRelayCommand SendCodeCommand { get; }

    public AsyncRelayCommand ResetCommand { get; }

    public RelayCommand BackCommand { get; }

    public string Email
    {
        get => _email;
        set => Set(ref _email, value);
    }

    public string Token
    {
        get => _token;
        set => Set(ref _token, value);
    }

    public string NewPassword
    {
        get => _newPassword;
        set => Set(ref _newPassword, value);
    }

    public string Error
    {
        get => _error;
        private set
        {
            if (Set(ref _error, value))
            {
                Raise(nameof(HasError));
            }
        }
    }

    public bool HasError => Error.Length > 0;

    public string Message
    {
        get => _message;
        private set
        {
            if (Set(ref _message, value))
            {
                Raise(nameof(HasMessage));
            }
        }
    }

    public bool HasMessage => Message.Length > 0;

    public bool CodeSent
    {
        get => _codeSent;
        private set
        {
            if (Set(ref _codeSent, value))
            {
                Raise(nameof(CanEnterCode));
            }
        }
    }

    public bool CanEnterCode => CodeSent;

    private async Task SendCodeAsync()
    {
        Error = string.Empty;
        Message = string.Empty;

        if (string.IsNullOrWhiteSpace(Email) || !Email.Contains('@'))
        {
            Error = "Enter the email address on your account.";
            return;
        }

        try
        {
            await _service.RequestPasswordResetAsync(Email);
            CodeSent = true;
            Message = "Check your inbox for the reset code, then enter it below.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private async Task ResetAsync()
    {
        Error = string.Empty;

        if (Token.Trim().Length < 6)
        {
            Error = "Enter the reset code from the email.";
            return;
        }

        if (NewPassword.Length < 8)
        {
            Error = "Use a new password with at least 8 characters.";
            return;
        }

        try
        {
            await _service.CompletePasswordResetAsync(Email, Token, NewPassword);
            _onDone("Password updated. Sign in with the new password.");
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }
}

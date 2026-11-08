namespace TesterLoop.Desktop.Core.Models;

public enum UserRole
{
    Developer,
    Tester,
    Admin,
}

public sealed record Account(
    Guid Id,
    string Name,
    string Email,
    UserRole Role,
    Guid? DeveloperId,
    Guid? TesterId);

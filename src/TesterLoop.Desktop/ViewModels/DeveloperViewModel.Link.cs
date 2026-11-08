namespace TesterLoop.Desktop.ViewModels;

public partial class DeveloperViewModel
{
    private string _linkActionNote = string.Empty;

    public string LinkActionNote
    {
        get => _linkActionNote;
        private set
        {
            if (Set(ref _linkActionNote, value))
            {
                Raise(nameof(HasLinkActionNote));
            }
        }
    }

    public bool HasLinkActionNote => LinkActionNote.Length > 0;

    private void ClearLinkNote() => LinkActionNote = string.Empty;

    private void LinkIssue(string message)
    {
        LinkActionNote = message;
        Error = message;
    }
}

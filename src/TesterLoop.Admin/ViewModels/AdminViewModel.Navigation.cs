namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private int _selectedTabIndex;

    public int SelectedTabIndex
    {
        get => _selectedTabIndex;
        set
        {
            if (Set(ref _selectedTabIndex, value))
            {
                CampaignPageIndex = 0;
                _selectedCampaignRow = null;
                Raise(nameof(SelectedCampaignRow));
                CampaignDetail = null;

                TesterPageIndex = 0;
                _selectedTesterRow = null;
                Raise(nameof(SelectedTesterRow));
                TesterDetail = null;
                TesterProject = null;
                _activeTesterProjectRow = null;

                DeveloperPageIndex = 0;
                _selectedDeveloperRow = null;
                Raise(nameof(SelectedDeveloperRow));
                DeveloperDetail = null;

                FeedbackPageIndex = 0;
                _selectedFeedbackRow = null;
                Raise(nameof(SelectedFeedbackRow));
                ReportDetail = null;
                _reportOrigin = ReportOrigin.Feedback;
                Raise(nameof(ReportBackLabel));
            }
        }
    }
}

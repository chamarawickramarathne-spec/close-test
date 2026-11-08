using System.Text.Json;

namespace TesterLoop.Desktop.Core.Data;

public sealed partial class SupabaseService
{
    public Task<AdminTesterDetailDto> GetAdminTesterDetailAsync(Guid testerId)
        => RpcAsync<AdminTesterDetailDto>("admin_tester_detail", Arguments(
            ("p_tester_id", testerId)));

    public Task<AdminDeveloperDetailDto> GetAdminDeveloperDetailAsync(Guid developerId)
        => RpcAsync<AdminDeveloperDetailDto>("admin_developer_detail", Arguments(
            ("p_developer_id", developerId)));

    public Task<AdminReportDetailDto> GetAdminReportDetailAsync(Guid reportId)
        => RpcAsync<AdminReportDetailDto>("admin_report_detail", Arguments(
            ("p_report_id", reportId)));

    public Task<AdminCampaignDetailDto> GetAdminCampaignDetailAsync(Guid campaignId)
        => RpcAsync<AdminCampaignDetailDto>("admin_campaign_detail", Arguments(
            ("p_campaign_id", campaignId)));

    public Task<JsonElement> ConfirmTesterPayoutAsync(
        Guid campaignId, Guid testerId, string reference)
        => RpcAsync<JsonElement>("confirm_tester_payout", Arguments(
            ("p_campaign_id", campaignId),
            ("p_tester_id", testerId),
            ("p_reference", NullIfEmpty(reference))));
}

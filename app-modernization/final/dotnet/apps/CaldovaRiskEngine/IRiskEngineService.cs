using CoreWCF;

namespace CaldovaRiskEngine
{
    [ServiceContract]
    public interface IRiskEngineService
    {
        [OperationContract]
        Task<RiskScoreResponse> ScoreLoanApplication(int applicationId);

        [OperationContract]
        Task<RiskFactorsResponse> GetRiskFactors(int customerId);

        [OperationContract]
        Task<RiskModelUpdateResponse> UpdateRiskModel(RiskModelUpdateRequest modelParams);
    }
}

using System.Collections.ObjectModel;
using CoreWCF;
using CoreWCF.Channels;
using CoreWCF.Description;
using CoreWCF.Dispatcher;

namespace CaldovaRiskEngine;

public sealed class SafeFaultBehavior(ILogger<SafeFaultBehavior> logger) : IServiceBehavior, IErrorHandler
{
    public bool HandleError(Exception error)
    {
        if (error is not FaultException)
            logger.LogError("SOAP risk operation failed ({ExceptionType}).", error.GetType().Name);
        return true;
    }

    public void ProvideFault(Exception error, MessageVersion version, ref Message fault)
    {
        if (error is FaultException)
            return;
        var safe = new FaultException("The risk operation could not be completed.");
        fault = Message.CreateMessage(version, safe.CreateMessageFault(), safe.Action);
    }

    public void ApplyDispatchBehavior(ServiceDescription serviceDescription, ServiceHostBase serviceHostBase)
    {
        foreach (var dispatcher in serviceHostBase.ChannelDispatchers.OfType<ChannelDispatcher>())
            dispatcher.ErrorHandlers.Add(this);
    }

    public void AddBindingParameters(ServiceDescription description, ServiceHostBase host,
        Collection<ServiceEndpoint> endpoints, BindingParameterCollection parameters) { }

    public void Validate(ServiceDescription description, ServiceHostBase host) { }
}

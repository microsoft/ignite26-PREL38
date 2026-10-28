FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
ARG NUGET_SOURCE=https://api.nuget.org/v3/index.json
COPY CaldovaAuthGateway.csproj packages.lock.json ./
RUN dotnet restore --locked-mode --source "$NUGET_SOURCE"
COPY . .
RUN dotnet publish -c Release --no-restore -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "CaldovaAuthGateway.dll"]

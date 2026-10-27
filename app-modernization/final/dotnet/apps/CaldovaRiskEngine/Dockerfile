FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
ARG NUGET_SOURCE=https://api.nuget.org/v3/index.json
COPY CaldovaRiskEngine.csproj packages.lock.json ./
RUN dotnet restore --locked-mode --source "$NUGET_SOURCE"
COPY . .
RUN dotnet publish -c Release --no-restore -o /out /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /out/ ./
USER $APP_UID
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "CaldovaRiskEngine.dll"]

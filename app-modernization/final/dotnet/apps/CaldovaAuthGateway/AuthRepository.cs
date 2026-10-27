using System;
using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace CaldovaAuthGateway
{
    public sealed class AuthRepository
    {
        private readonly ILogger<AuthRepository> _logger;
        private readonly Func<SqlConnection> _connections;

        public AuthRepository(ILogger<AuthRepository> logger, Func<SqlConnection> connections)
        {
            _logger = logger;
            _connections = connections;
        }

        public async Task<AuthUser?> GetUserByUsername(string username)
        {
            // Do NOT log username (PII) — the caller logs UserId after this returns
            using (var connection = _connections())
            using (var command = new SqlCommand(@"
SELECT UserID, Username, PasswordHash, Salt, IsActive, IsLockedOut, FirstName, LastName
FROM Users
WHERE Username = @Username;", connection))
            {
                command.Parameters.AddWithValue("@Username", username);
                await connection.OpenAsync();

                using (var reader = await command.ExecuteReaderAsync(CommandBehavior.SingleRow))
                {
                    if (!await reader.ReadAsync())
                    {
                        _logger.LogDebug("GetUserByUsername: no matching user found");
                        return null;
                    }

                    return new AuthUser
                    {
                        UserId = reader.GetInt32(0),
                        Username = reader.GetString(1),
                        PasswordHash = reader.GetString(2),
                        Salt = reader.GetString(3),
                        IsActive = reader.GetBoolean(4),
                        IsLockedOut = reader.GetBoolean(5),
                        FirstName = reader.IsDBNull(6) ? string.Empty : reader.GetString(6),
                        LastName = reader.IsDBNull(7) ? string.Empty : reader.GetString(7)
                    };
                }
            }
        }

        public async Task<List<string>> GetUserRoles(int userId)
        {
            var roles = new System.Collections.Generic.List<string>();
            using (var connection = _connections())
            using (var command = new SqlCommand(@"
SELECT r.RoleName
FROM Roles r
INNER JOIN UserRoles ur ON r.RoleID = ur.RoleID
WHERE ur.UserID = @UserID;", connection))
            {
                command.Parameters.AddWithValue("@UserID", userId);
                await connection.OpenAsync();

                using (var reader = await command.ExecuteReaderAsync())
                {
                    while (await reader.ReadAsync())
                    {
                        roles.Add(reader.GetString(0));
                    }
                }
            }

            // Log only the surrogate UserId and count — never role names if they encode PII
            _logger.LogDebug("Retrieved {RoleCount} role(s) for user {UserId}", roles.Count, userId);
            return roles;
        }

        public async Task CreateSessionToken(int userId, string token, string ipAddress, string userAgent)
        {
            using (var connection = _connections())
            using (var command = new SqlCommand(@"
INSERT INTO SessionTokens (UserID, Token, CreatedAt, ExpiresAt, SourceSystem, IsActive, IPAddress, UserAgent)
VALUES (@UserID, @Token, GETDATE(), DATEADD(MINUTE, 30, GETDATE()), @SourceSystem, 1, @IPAddress, @UserAgent);", connection))
            {
                command.Parameters.AddWithValue("@UserID", userId);
                command.Parameters.AddWithValue("@Token", token);
                command.Parameters.AddWithValue("@SourceSystem", "DotNet");
                command.Parameters.AddWithValue("@IPAddress", (object)(ipAddress ?? string.Empty));
                command.Parameters.AddWithValue("@UserAgent", (object)(userAgent ?? string.Empty));
                await connection.OpenAsync();
                await command.ExecuteNonQueryAsync();
            }

            // Log only UserId (surrogate) — do NOT log the token value (it is a secret)
            _logger.LogInformation("Session token created for user {UserId}", userId);
        }

        public async Task DeactivateSessionToken(string token)
        {
            using (var connection = _connections())
            using (var command = new SqlCommand(@"
UPDATE SessionTokens
SET IsActive = 0, ExpiresAt = GETDATE()
WHERE Token = @Token;", connection))
            {
                command.Parameters.AddWithValue("@Token", token);
                await connection.OpenAsync();
                await command.ExecuteNonQueryAsync();
            }

            // Do NOT log the token value (it is a secret — masked or otherwise)
            _logger.LogInformation("Session token deactivated");
        }

        public async Task<SessionValidationResult?> ValidateSessionToken(string token)
        {
            using (var connection = _connections())
            using (var command = new SqlCommand(@"
SELECT TOP 1 st.UserID, u.Username, st.ExpiresAt
FROM SessionTokens st
INNER JOIN Users u ON st.UserID = u.UserID
WHERE st.Token = @Token
  AND st.IsActive = 1
  AND st.ExpiresAt > GETDATE()
  AND u.IsActive = 1
  AND u.IsLockedOut = 0
ORDER BY st.ExpiresAt DESC;", connection))
            {
                command.Parameters.AddWithValue("@Token", token);
                await connection.OpenAsync();

                using (var reader = await command.ExecuteReaderAsync(CommandBehavior.SingleRow))
                {
                    if (!await reader.ReadAsync())
                    {
                        // Do NOT log the token value — it is a secret
                        _logger.LogDebug("ValidateSessionToken: no valid session found");
                        return null;
                    }

                    var result = new SessionValidationResult
                    {
                        UserId = reader.GetInt32(0),
                        Username = reader.GetString(1),
                        ExpiresAt = reader.GetDateTime(2)
                    };

                    // Log only the surrogate UserId — never Username or token
                    _logger.LogDebug("ValidateSessionToken: valid session found for user {UserId}", result.UserId);
                    return result;
                }
            }
        }

        public async Task UpdateLastLogin(int userId)
        {
            using (var connection = _connections())
            using (var command = new SqlCommand("UPDATE Users SET LastLoginDate = GETDATE(), ModifiedDate = GETDATE() WHERE UserID = @UserID;", connection))
            {
                command.Parameters.AddWithValue("@UserID", userId);
                await connection.OpenAsync();
                await command.ExecuteNonQueryAsync();
            }

            _logger.LogDebug("LastLoginDate updated for user {UserId}", userId);
        }
    }

    public sealed class AuthUser
    {
        public int UserId { get; set; }

        public string Username { get; set; } = string.Empty;

        public string PasswordHash { get; set; } = string.Empty;

        public string Salt { get; set; } = string.Empty;

        public bool IsActive { get; set; }

        public bool IsLockedOut { get; set; }

        public string FirstName { get; set; } = string.Empty;

        public string LastName { get; set; } = string.Empty;
    }

    public sealed class SessionValidationResult
    {
        public int UserId { get; set; }

        public string Username { get; set; } = string.Empty;

        public DateTime ExpiresAt { get; set; }
    }
}

using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Server.Kestrel.Https;

// TLS_CERT_PFX_PATH is only set for environments where this container should terminate TLS
// internally. Unset means today's plain HTTP:8080.
var certPath = Environment.GetEnvironmentVariable("TLS_CERT_PFX_PATH");
var certPassword = Environment.GetEnvironmentVariable("TLS_CERT_PFX_PASSWORD");

var builder = WebApplication.CreateBuilder(args);

if (!string.IsNullOrEmpty(certPath))
{
    builder.WebHost.ConfigureKestrel(options =>
    {
        options.ListenAnyIP(8443, listenOptions =>
        {
            listenOptions.UseHttps(new HttpsConnectionAdapterOptions
            {
                ServerCertificate = new X509Certificate2(certPath, certPassword)
            });
        });
    });
}

var app = builder.Build();

app.MapGet("/health", () => Results.Ok("OK"));
app.MapGet("/", () => Results.Ok(new { service = "task-api", status = "ok" }));

if (string.IsNullOrEmpty(certPath))
{
    app.Run("http://0.0.0.0:8080");
}
else
{
    app.Run();
}

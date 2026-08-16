var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok("OK"));
app.MapGet("/", () => Results.Ok(new { service = "task-api", status = "ok" }));

app.Run("http://0.0.0.0:8080");
using Xunit;

namespace CreateManifest.Tests;

public class FunctionTest
{
    // Stub only — matches the stub Function implementation. Real coverage (the actual
    // FunctionHandler, which calls Step Functions) needs a mocked AmazonStepFunctionsClient once
    // that's wired for dependency injection instead of a static field.
    [Fact]
    public void ParseS3Event_ExtractsBucketAndKey()
    {
        const string body = """
        {
            "Records": [
                { "s3": { "bucket": { "name": "thor-ingestion-dev-877969058937" }, "object": { "key": "uploads/scan-123.zip" } } }
            ]
        }
        """;

        var (bucket, key) = Function.ParseS3Event(body);

        Assert.Equal("thor-ingestion-dev-877969058937", bucket);
        Assert.Equal("uploads/scan-123.zip", key);
    }
}

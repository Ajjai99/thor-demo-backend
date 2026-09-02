using System.Text.Json;
using Amazon.Lambda.Core;
using Amazon.StepFunctions;
using Amazon.StepFunctions.Model;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace CreateManifest;

// EventBridge Pipes (no input transformer configured) invokes this with a JSON *array* of raw SQS
// message objects — not the {"Records": [...]} wrapper a classic SQS-triggered Lambda gets.
public record SqsMessage(string Body);

public class Function
{
    private static readonly AmazonStepFunctionsClient StepFunctionsClient = new();

    // Extracted so it's unit-testable without mocking the Step Functions call below.
    public static (string Bucket, string Key) ParseS3Event(string body)
    {
        using var s3Event = JsonDocument.Parse(body);
        var record = s3Event.RootElement.GetProperty("Records")[0].GetProperty("s3");
        var bucket = record.GetProperty("bucket").GetProperty("name").GetString()!;
        var key = record.GetProperty("object").GetProperty("key").GetString()!;
        return (bucket, key);
    }

    // Stub only — logs what it received and reports success to Step Functions. Real
    // manifest-building logic (what actually gets recorded, from where) isn't implemented yet;
    // this exists to prove the CreateManifest -> Step Functions wiring works end to end.
    public async Task<object> FunctionHandler(List<SqsMessage> messages, ILambdaContext context)
    {
        context.Logger.LogInformation($"Received {messages.Count} message(s)");

        var (bucket, key) = ParseS3Event(messages[0].Body);

        var input = JsonSerializer.Serialize(new
        {
            status = "success",
            bucket,
            key,
            retry_count = 0,
        });

        var result = await StepFunctionsClient.StartExecutionAsync(new StartExecutionRequest
        {
            StateMachineArn = Environment.GetEnvironmentVariable("STATE_MACHINE_ARN"),
            Input = input,
        });

        return new { status = "stub", executionArn = result.ExecutionArn };
    }
}

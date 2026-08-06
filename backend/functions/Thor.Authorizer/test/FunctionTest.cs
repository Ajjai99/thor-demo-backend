using Amazon.Lambda.APIGatewayEvents;
using Xunit;

namespace Thor.Authorizer.Tests;

public class FunctionTest
{
    // Stub only — matches the stub Function implementation. Replace once
    // real hash-lookup-against-Aurora logic exists.
    [Fact]
    public void FunctionHandler_DeniesByDefault()
    {
        var function = new Function();
        var request = new APIGatewayCustomAuthorizerRequest { MethodArn = "arn:aws:execute-api:us-east-1:123456789012:abc123/dev/GET/" };

        var response = function.FunctionHandler(request, null!);

        Assert.Equal("Deny", response.PolicyDocument.Statement[0].Effect);
    }
}

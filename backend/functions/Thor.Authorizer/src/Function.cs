using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Thor.Authorizer;

public class Function
{
    // !!! TEMPORARY — STUB ALLOWS EVERY REQUEST, NO KEY CHECK AT ALL !!!
    // Flipped from unconditional Deny to unconditional Allow to unblock testing the
    // API Gateway -> VPC Link -> NLB -> thor-api path end to end. This removes API-key
    // protection entirely for ANY environment that deploys this code — dev, qa, or prod —
    // since this file is the shared source for all of them.
    // MUST be replaced with the real implementation (hash the x-api-key header, look it up
    // in Aurora via RDS Data API, return Allow with the matching tenant ID in context, or
    // Deny if no match) before qa/prod ever redeploy this Lambda.
    public APIGatewayCustomAuthorizerResponse FunctionHandler(
        APIGatewayCustomAuthorizerRequest request, ILambdaContext context)
    {
        return new APIGatewayCustomAuthorizerResponse
        {
            PrincipalID = "anonymous",
            PolicyDocument = new APIGatewayCustomAuthorizerPolicy
            {
                Version = "2012-10-17",
                Statement =
                [
                    new APIGatewayCustomAuthorizerPolicy.IAMPolicyStatement
                    {
                        Action = ["execute-api:Invoke"],
                        Effect = "Allow",
                        Resource = [request.MethodArn]
                    }
                ]
            }
        };
    }
}

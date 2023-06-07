data "aws_iam_policy_document" "cloudwatch" {
  statement {
    actions = [
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "ec2:DescribeTags",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "cloudwatch" {
  name        = "CloudWatchMetrics"
  description = "A policy that allows EC2 instances to send CloudWatch metrics"
  policy      = data.aws_iam_policy_document.cloudwatch.json
}

resource "aws_iam_role" "cloudwatch" {
  name = "CloudWatchMetricsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = aws_iam_policy.cloudwatch.arn
}

resource "aws_iam_instance_profile" "cloudwatch" {
  name = "CloudWatchMetricsProfile"
  role = aws_iam_role.cloudwatch.name
}
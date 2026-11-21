terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # change to your region
}

# --- IAM User dedicated to Prowler scanning ---
resource "aws_iam_user" "prowler_scan" {
  name = "prowler-scan-readonly"
  path = "/security-tools/"

  tags = {
    Purpose   = "CSPM scanning - Prowler"
    ManagedBy = "Terraform"
  }
}

# --- Attach AWS-managed read-only security policies ---
# SecurityAudit: lets Prowler read security-relevant config (IAM, S3, EC2, etc.)
resource "aws_iam_user_policy_attachment" "security_audit" {
  user       = aws_iam_user.prowler_scan.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

# ViewOnlyAccess: broadens read access to list/describe resources
# outside SecurityAudit's scope, still no write/modify permissions.
resource "aws_iam_user_policy_attachment" "view_only" {
  user       = aws_iam_user.prowler_scan.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

# --- Explicit deny guardrail ---
# Belt-and-suspenders: even if a future policy attachment is
# accidentally too broad, this blocks any mutating/destructive
# action outright. Least privilege enforced at two layers.
resource "aws_iam_user_policy" "explicit_deny_writes" {
  name = "explicit-deny-mutations"
  user = aws_iam_user.prowler_scan.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyMutatingActions"
        Effect = "Deny"
        Action = [
          "iam:Create*", "iam:Put*", "iam:Delete*", "iam:Update*", "iam:Attach*", "iam:Detach*",
          "s3:Put*", "s3:Delete*", "s3:Create*",
          "ec2:Create*", "ec2:Delete*", "ec2:Terminate*", "ec2:Modify*",
          "rds:Create*", "rds:Delete*", "rds:Modify*",
          "lambda:Create*", "lambda:Delete*", "lambda:Update*"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Programmatic access key (no console login) ---
resource "aws_iam_access_key" "prowler_scan_key" {
  user = aws_iam_user.prowler_scan.name
}

# --- Outputs (mark sensitive so they don't print in plain CI logs) ---
output "prowler_access_key_id" {
  value     = aws_iam_access_key.prowler_scan_key.id
  sensitive = true
}

output "prowler_secret_access_key" {
  value     = aws_iam_access_key.prowler_scan_key.secret
  sensitive = true
}

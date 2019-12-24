data "aws_caller_identity" "current" {}

data "aws_iam_user" "terraform_svc_user" {
  user_name = "${var.terraform_svc_user}"
}

data "aws_iam_role" "automation_role" {
  name = "${var.tlz_org_account_access_role}"
}

data "template_file" "ses_sendmail" {
  template = "${file("${path.module}/policies/ses_sendmail.json")}"
}

data "template_file" "ses_mailbox_bucket_policy" {
  template = "${file("${path.module}/policies/ses_mailbox_bucket_policy.json")}"
  
  vars = {
    account_id  = "${data.aws_caller_identity.current.account_id}"
    bucket_name = "${local.bucket_name}"
  }
}

data "template_file" "ses_mailbox_kms_key_policy" {
  template = "${file("${path.module}/policies/ses_mailbox_kms_key_policy.json")}"

  vars = {
    terraform_svc_user_arn = "${data.aws_iam_user.terraform_svc_user.arn}"
    automation_role_arn    = "${data.aws_iam_role.automation_role.arn}"
    account_id             = "${data.aws_caller_identity.current.account_id}"
  }
}

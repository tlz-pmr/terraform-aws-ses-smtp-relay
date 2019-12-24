##########
# Locals #
##########

locals {
  ses_sendmail_credentials = {
    access_key_id     = "${aws_iam_access_key.ses_sendmail.id}"
    ses_smtp_password = "${aws_iam_access_key.ses_sendmail.ses_smtp_password}"
  }
  bucket_name = "mail-${replace(aws_ses_domain_identity.ses_sender_verification.domain,".","-")}-${data.aws_caller_identity.current.account_id}"
}

###########################################################################################################
# IAM                                                                                                     #
# |- IAM users needed because sendmail uses a transformation of IAM user credentials to provide access to #
# |  SMTP relays                                                                                          #
# |  https://docs.aws.amazon.com/ses/latest/DeveloperGuide/smtp-credentials.html#smtp-credentials-convert #
###########################################################################################################

resource "aws_iam_user" "ses_sendmail" {
  name = "ses_sendmail"
}

resource "aws_iam_access_key" "ses_sendmail" {
  user = "${aws_iam_user.ses_sendmail.name}"
}

resource "aws_iam_user_policy" "ses_sendmail" {
  name   = "ses_sendmail"
  policy = "${data.template_file.ses_sendmail.rendered}"
  user   = "${aws_iam_user.ses_sendmail.name}"
}

#######
# KMS #
#######

resource "aws_kms_key" "mailbox" {
  description = "SES mailbox key for incoming mail from ${aws_ses_domain_identity.ses_sender_verification.domain}"

  policy = "${data.template_file.ses_mailbox_kms_key_policy.rendered}"
}

###################
# Secrets Manager #
###################

resource "aws_secretsmanager_secret" "ses_sendmail_user" {
  name = "ses_sendmail_user"
}

resource "aws_secretsmanager_secret_version" "ses_sendmail_user" {
  secret_id     = "${aws_secretsmanager_secret.ses_sendmail_user.id}"
  secret_string = "${jsonencode(local.ses_sendmail_credentials)}"
}

######
# S3 #
######

resource "aws_s3_bucket" "ses_mailbox" {
  bucket = "${local.bucket_name}"

  acl    = "private"
  policy = "${data.template_file.ses_mailbox_bucket_policy.rendered}"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "${aws_kms_key.mailbox.arn}"
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ses_mailbox" {
  bucket                  = "${aws_s3_bucket.ses_mailbox.id}"

  block_public_acls       = "true"
  block_public_policy     = "true"
  restrict_public_buckets = "true"
}

#######
# SES #
#######

resource "aws_ses_domain_identity" "ses_sender_verification" {
  domain = "${var.sender_domain}"
}

resource "aws_ses_domain_mail_from" "bounces" {
  domain           = "${var.sender_domain}"
  mail_from_domain = "bounce.${aws_ses_domain_identity.ses_sender_verification.domain}"
}

resource "aws_ses_identity_notification_topic" "bounces" {
  topic_arn                = "${aws_sns_topic.ses_bounces.arn}"
  notification_type        = "Bounce"
  identity                 = "${aws_ses_domain_identity.ses_sender_verification.domain}"
  include_original_headers = "true"
}

resource "aws_ses_identity_notification_topic" "complaints" {
  topic_arn                = "${aws_sns_topic.ses_complaints.arn}"
  notification_type        = "Complaint"
  identity                 = "${aws_ses_domain_identity.ses_sender_verification.domain}"
  include_original_headers = "true"
}

#####################
# SES Receipt Rules #
#####################

resource "aws_ses_receipt_rule_set" "default" {
  rule_set_name = "default-rules"
}

resource "aws_ses_active_receipt_rule_set" "default" {
  rule_set_name = "default-rules"
}

resource "aws_ses_receipt_rule" "abuse" {
  name          = "abuse"
  rule_set_name = "default-rules"
  recipients    = ["abuse@${aws_ses_domain_identity.ses_sender_verification.domain}"]
  enabled       = "true"
  scan_enabled  = "true"

  s3_action {
    bucket_name       = "${aws_s3_bucket.ses_mailbox.id}"
    kms_key_arn       = "${aws_kms_key.mailbox.arn}"
    object_key_prefix = "abuse"
    position          = 1
  }
}

resource "aws_ses_receipt_rule" "bounce" {
  name          = "bounce"
  rule_set_name = "default-rules"
  recipients    = ["bounce@${aws_ses_domain_identity.ses_sender_verification.domain}"]
  enabled       = "true"
  scan_enabled  = "true"

  s3_action {
    bucket_name       = "${aws_s3_bucket.ses_mailbox.id}"
    kms_key_arn       = "${aws_kms_key.mailbox.arn}"
    object_key_prefix = "bounce"
    position          = 1
  }
}

resource "aws_ses_receipt_rule" "complaint" {
  name          = "complaint"
  rule_set_name = "default-rules"
  recipients    = ["complaint@${aws_ses_domain_identity.ses_sender_verification.domain}"]
  enabled       = "true"
  scan_enabled  = "true"

  s3_action {
    bucket_name       = "${aws_s3_bucket.ses_mailbox.id}"
    kms_key_arn       = "${aws_kms_key.mailbox.arn}"
    object_key_prefix = "complaint"
    position          = 1
  }
}

resource "aws_ses_receipt_rule" "postmaster" {
  name          = "postmaster"
  rule_set_name = "default-rules"
  recipients    = ["postmaster@${aws_ses_domain_identity.ses_sender_verification.domain}"]
  enabled       = "true"
  scan_enabled  = "true"

  s3_action {
    bucket_name       = "${aws_s3_bucket.ses_mailbox.id}"
    kms_key_arn       = "${aws_kms_key.mailbox.arn}"
    object_key_prefix = "postmaster"
    position          = 1
  }
}

###################################################################################
# SNS                                                                             #
# |- It should be noted that email subscriptions must be manual here since email  #
# |  subscriptions are not supported by terraform. See unsupported options below: #
# |  https://www.terraform.io/docs/providers/aws/r/sns_topic_subscription.html    #
###################################################################################

resource "aws_sns_topic" "ses_bounces" {
  name = "ses_bounce_notifications"
}

resource "aws_sns_topic" "ses_complaints" {
  name = "ses_complaint_notifications"
}

##############################################################################################
# Route53                                                                                    #
# |- Domain verification required to verify ownership of the email you are sending as        #
# |  https://docs.aws.amazon.com/ses/latest/DeveloperGuide/verify-addresses-and-domains.html #
##############################################################################################

data "aws_route53_zone" "ses_sender_verification" {
  name = "${var.sender_domain}"
}

resource "aws_route53_record" "ses_domain_mail_from_mx" {
  zone_id = "${data.aws_route53_zone.ses_sender_verification.id}"
  name    = "${aws_ses_domain_mail_from.bounces.mail_from_domain}"
  type    = "MX"
  ttl     = "${var.domain_mail_from_ttl}"
  records = ["10 feedback-smtp.${var.region}.amazonses.com"]
}

resource "aws_route53_record" "ses_domain_mx" {
  zone_id = "${data.aws_route53_zone.ses_sender_verification.id}"
  name    = "${var.sender_domain}"
  type    = "MX"
  ttl     = "${var.domain_mail_from_ttl}"
  records = ["10 inbound-smtp.${var.region}.amazonaws.com"]
}

resource "aws_route53_record" "ses_domain_mail_from_txt" {
  zone_id = "${data.aws_route53_zone.ses_sender_verification.id}"
  name    = "${aws_ses_domain_mail_from.bounces.mail_from_domain}"
  type    = "TXT"
  ttl     = "${var.domain_mail_from_ttl}"
  records = ["v=spf1 include:amazonses.com -all"]
}

resource "aws_route53_record" "ses_sender_verification" {
  zone_id = "${data.aws_route53_zone.ses_sender_verification.zone_id}"
  name    = "_amazonses.${aws_ses_domain_identity.ses_sender_verification.id}"
  type    = "TXT"
  ttl     = "${var.ses_sender_verification_txt_ttl}"
  records = ["${aws_ses_domain_identity.ses_sender_verification.verification_token}"]
}

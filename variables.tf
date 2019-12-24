variable "sender_domain" {
  description = "Domain of emails services will be using to send emails through SES (needed for SES domain verification)"
  type        = "string"
}

variable "ses_sender_verification_txt_ttl" {
  description = "TTL of the TXT record used by SES to verify domain ownership"
  type        = "string"
  default     = "600"
}

variable "domain_mail_from_ttl" {
  description = "TTL of domain_mail_from records used to validate being able to set the MAIL FROM field"
  type        = "string"
  default     = "300"
}

variable "terraform_svc_user" {
  description = "Name of the IAM user terraform uses to administer resources in this account"
  type        = "string"
  default     = "terraform_svc"
}

variable "tlz_org_account_access_role" {
  description = "Name of the IAM role used by shared services to administer cross account resources"
  type        = "string"
  default     = "tlz_avm_automation"
}

variable "region" {
  description = "Name of the region being deployed into. Used to differentiate regions in SES endpoint MX records so must be either us-east-1, us-west-2, or eu-west-1"
  type        = "string"
}

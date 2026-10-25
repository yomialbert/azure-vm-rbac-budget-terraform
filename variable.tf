#variables
variable "location" {
    description = "This will be Azure regions for all resources"
type = string
}

variable "prefix" {
    description = "this is suffix that will resource names uniques"
    type = string
}
variable "email_alert" {
description = "Email Address that will receive budget alert"
type = string
}
variable "operator_object_id" {
  description = "This is Entra Object ID of the user to grant VM read and restart access"
  type = string
}
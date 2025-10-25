variable "project_id" {
    description = "The project ID to create the VPC in"
    type = string
}

variable "name" {
    description = "The name of the VPC"
    type = string
}

variable "subnets" {
    description = "The subnets to create in the VPC"
    type = list(object({
        name = string
        ip_cidr_range = string
        region = string
    }))
}

variable "labels" {
    description = "The labels to apply to the VPC"
    type = map(string)
    default = {}
}
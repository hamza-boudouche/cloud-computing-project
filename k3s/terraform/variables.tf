//General
variable "gcp_key" {
    description = "Google Cloud service account key file"
    default = "gcp.json"
}

variable "project_id" {
    description = "Project ID"
    default = "central-cinema-402517"
}

variable "region" {
    description = "region"
    default = "europe-west6"
}

variable "zone" {
    description = "zone"
    default = "europe-west6-a"
}

//Network
variable "network_name" {
    description = "Name of the network"
    default = "k3s-vpc"
}

//instances

variable "instance_type" {
    description = "The instance type"
    default = "e2-standard-2"
}

variable "image_type" {
    description = "Image type"
    default = "ubuntu-os-cloud/ubuntu-2004-lts"
}
variable "master_instance_count" {
  description = "Number of master instances to create"
  default = 3
}

variable "nodes_instance_count" {
  description = "Number of nodes instances to create"
  default = 4
}
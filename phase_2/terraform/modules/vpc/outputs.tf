output "network_self_link" {
    value = google_compute_network.this.self_link
    description = "The self link of the VPC"
}

output "subnets" {
    value = {
        for name, subnet in google_compute_subnetwork.this :
        name => {
            self_link = subnet.self_link
            ip_cidr = subnet.ip_cidr_range
            region = subnet.region
        }
    }
    description = "The metadata of the subnets in the VPC"
}
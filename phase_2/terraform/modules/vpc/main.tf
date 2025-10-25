resource "google_compute_network" "this" {
    name = var.name
    auto_create_subnetworks = false
    routing_mode = "REGIONAL"
    project = var.project_id
}

resource "google_compute_subnetwork" "this" {
    for_each = { for subnet in var.subnets : subnet.name => subnet }
    name = each.value.name
    ip_cidr_range = each.value.ip_cidr_range
    network = google_compute_network.this.id
    region = each.value.region
    project = var.project_id
    private_ip_google_access = true
}
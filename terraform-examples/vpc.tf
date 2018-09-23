variable "cidr_block_vpc" {
    default = "10.5.228.0/22"
}
variable "cidr_block_proxy" {
    default = "10.5.228.0/24"
}
variable "cidr_block_subnet1" {
    default = "10.5.229.0/24"
}
variable "cidr_block_subnet2" {
    default = "10.5.230.0/24"
}

resource "aws_vpc" "use1-main" {
    cidr_block           = "${var.cidr_block_vpc}"
    enable_dns_hostnames = true
    enable_dns_support   = true
    instance_tenancy     = "default"

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}

data "aws_availability_zone" "use1-william" {
    name = "us-east-1b"
}
data "aws_availability_zone" "use1-alice" {
    name = "us-east-1c"
}
data "aws_availability_zone" "use1-bob" {
    name = "us-east-1d"
}

resource "aws_vpn_gateway" "use1-main" {
    vpc_id = "${aws_vpc.use1-main.id}"

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}

resource "aws_subnet" "use1-william-proxy" {
    vpc_id                  = "${aws_vpc.use1-main.id}"
    cidr_block              = "${var.cidr_block_proxy}"
    availability_zone       = "${data.aws_availability_zone.use1-william.name}"
    map_public_ip_on_launch = false

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}
resource "aws_subnet" "use1-bob-public" {
    vpc_id                  = "${aws_vpc.use1-main.id}"
    cidr_block              = "${var.cidr_block_subnet1}"
    availability_zone       = "${data.aws_availability_zone.use1-bob.name}"
    map_public_ip_on_launch = false

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}
resource "aws_subnet" "use1-alice-public" {
    vpc_id                  = "${aws_vpc.use1-main.id}"
    cidr_block              = "${var.cidr_block_subnet2}"
    availability_zone       = "${data.aws_availability_zone.use1-alice.name}"
    map_public_ip_on_launch = false

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}

resource "aws_route_table" "use1-proxy" {
    vpc_id     = "${aws_vpc.use1-main.id}"
    route {
        cidr_block = "12.23.34.45/32"
        nat_gateway_id = "${aws_nat_gateway.use1-nat-william.id}"
    }

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.use1-igw.id}"
    }

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}
resource "aws_route_table_association" "use1-proxy" {
    route_table_id = "${aws_route_table.use1-proxy.id}"
    subnet_id = "${aws_subnet.use1-william-proxy.id}"
}

resource "aws_route_table" "use1-public" {
    vpc_id     = "${aws_vpc.use1-main.id}"

    route {
        cidr_block = "192.168.0.0/16"
        gateway_id = "${aws_vpn_gateway.use1-main.id}"
    }

    route {
        cidr_block = "172.16.0.0/12"
        gateway_id = "${aws_vpn_gateway.use1-main.id}"
    }

    route {
        cidr_block = "10.0.0.0/8"
        gateway_id = "${aws_vpn_gateway.use1-main.id}"
    }

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.use1-igw.id}"
    }

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}
resource "aws_route_table_association" "use1-public-alice" {
    route_table_id = "${aws_route_table.use1-public.id}"
    subnet_id = "${aws_subnet.use1-alice-public.id}"
}
resource "aws_route_table_association" "use1-public-bob" {
    route_table_id = "${aws_route_table.use1-public.id}"
    subnet_id = "${aws_subnet.use1-bob-public.id}"
}


resource "aws_eip" "use1-nat-william" {
    vpc               = true
    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}
resource "aws_nat_gateway" "use1-nat-william" {
    allocation_id = "${aws_eip.use1-nat-william.id}"
    subnet_id = "${aws_subnet.use1-william-proxy.id}"

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}

resource "aws_internet_gateway" "use1-igw" {
    vpc_id = "${aws_vpc.use1-main.id}"

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "INFRASTRUCTURE_SHAREDSERVICES"
    }
}

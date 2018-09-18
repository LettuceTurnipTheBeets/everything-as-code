variable use1_key_name {
    default = "use1-ssh-key"
}

resource "aws_security_group" "lb" {
    name        = "lb"
    description = "Allow ports for LB"
    vpc_id      = "${aws_vpc.use1-main.id}"

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        self = true
    }

    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "web" {
    name        = "web"
    description = "Allow ports for web nodes"
    vpc_id      = "${aws_vpc.use1-main.id}"

    ingress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        self = true
    }

    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "db" {
    name        = "db"
    description = "Allow ports for DB nodes"
    vpc_id      = "${aws_vpc.use1-main.id}"

    ingress {
        from_port   = 9200
        to_port     = 9200
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/8"]
    }

    ingress {
        from_port   = 6379
        to_port     = 6379
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/8"]
    }

    ingress {
        from_port   = 3306
        to_port     = 3306
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/8"]
    }

    ingress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        self = true
    }

    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "global" {
    name        = "global"
    description = "Allow all com inside the group"
    vpc_id      = "${aws_vpc.use1-main.id}"

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/8"]
    }

    ingress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        self = true
    }

    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }
}

data "aws_ami" "debian9" {
    # https://wiki.debian.org/Cloud/AmazonEC2Image/Jessie
    most_recent = true

    filter {
        name   = "architecture"
        values = ["x86_64"]
    }
    filter {
        name   = "name"
        values = ["debian-stretch-*"]
    }
    filter {
        name   = "root-device-type"
        values = ["ebs"]
    }
    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }

    owners = ["379101102735"]
}

data "template_file" "aws_bootstrap" {
#    template = "${file("${path.module}/../bootstrap_scripts/aws_bootstrap_user_data/2018-08-16.txt")}"
}

resource "aws_instance" "haproxy" {
    ami = "${data.aws_ami.debian9.id}"
    instance_type = "m5.large"
    key_name               = "${var.use1_key_name}"
    vpc_security_group_ids = ["${aws_security_group.lb.id}", "${aws_security_group.global.id}"]
    subnet_id              = "${aws_subnet.use1-bob-public.id}"
    availability_zone      = "${aws_subnet.use1-bob-public.availability_zone}"
    user_data = "${data.template_file.aws_bootstrap.rendered}"

    root_block_device {
        volume_type = "gp2"
        volume_size = 250
        delete_on_termination = true
    }

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "ENGINEERING_SERVICES"
        Type = "haproxy"
        Name = "haproxy"
    }
    volume_tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "ENGINEERING_SERVICES"
        Type = "haproxy"
        Name = "haproxy"
    }
}
resource "aws_eip_association" "haproxy" {
    instance_id   = "${aws_instance.haproxy.id}"
    allocation_id = "${aws_eip.haproxy.id}"
}
resource "aws_eip" "haproxy" {
    vpc = true

    tags {
        Name = "haproxy"
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "ENGINEERING_SERVICES"
    }
}
output "haproxy_cluster_ip" {
    value = "${aws_instance.haproxy.public_ip}"
}
output "haproxy_cluster_dns" {
    value = "${aws_instance.haproxy.public_dns}"
}

variable "nginx_cluster_count" {
    default = 5
}
resource "aws_instance" "nginx_cluster" {
    count = "${var.nginx_cluster_count}"

    ami = "${data.aws_ami.debian9.id}"
    instance_type = "m5.2xlarge"
    key_name               = "${var.use1_key_name}"
    vpc_security_group_ids = ["${aws_security_group.web.id}", "${aws_security_group.global.id}"]
    subnet_id              = "${aws_subnet.use1-bob-public.id}"
    availability_zone      = "${aws_subnet.use1-bob-public.availability_zone}"
    user_data = "${data.template_file.aws_bootstrap.rendered}"

    root_block_device {
        volume_type = "gp2"
        volume_size = 250
        delete_on_termination = true
    }

    ebs_block_device {
        device_name = "/dev/sdb"
        volume_type = "gp2"
        volume_size = 30
        delete_on_termination = true
    }

    tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "ENGINEERING_SERVICES"
        Type = "nginx"
        Name = "${format("nginx-%03d",count.index+1)}"
    }
    volume_tags {
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "ENGINEERING_SERVICES"
        Type = "nginx"
        Name = "${format("nginx-%03d",count.index+1)}"
    }
}
resource "aws_eip_association" "nginx_cluster" {
    count = "${var.nginx_cluster_count}"

    instance_id   = "${element(aws_instance.nginx_cluster.*.id, count.index)}"
    allocation_id = "${element(aws_eip.nginx_cluster.*.id, count.index)}"
}
resource "aws_eip" "nginx_cluster" {
    vpc = true
    count = "${var.nginx_cluster_count}"

    tags {
        Name = "${format("nginx-%03d",count.index+1)}"
        DIVISION    = "INFRASTRUCTURE"
        SUBDIVISION = "ENGINEERING_SERVICES"
    }
}
output "nginx_cluster_ip" {
    value = "${aws_instance.nginx_cluster.*.public_ip}"
}
output "nginx_cluster_dns" {
    value = "${aws_instance.nginx_cluster.*.public_dns}"
}



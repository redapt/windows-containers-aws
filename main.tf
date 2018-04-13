variable "key_name" {}
variable "aws_region" {}
variable "aws_ami" {}
variable "elb_instance_size" {}
variable "access_key" {}
variable "secret_key" {}

provider "aws" {
  # access_key = "${var.access_key}"
  # secret_key = "${var.secret_key}"
  region = "${var.aws_region}"
}

resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags {
    Name = "tf_test"
  }
}

resource "aws_subnet" "tf_test_subnet" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true

  tags {
    Name = "tf_test_subnet"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "tf_test_ig"
  }
}

resource "aws_route_table" "r" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }

  tags {
    Name = "tf_test_route_table"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = "${aws_subnet.tf_test_subnet.id}"
  route_table_id = "${aws_route_table.r.id}"
}

resource "aws_security_group" "default" {
  name        = "instance_sg"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elb" {
  name        = "elb_sg"
  description = "Used in the terraform"

  vpc_id = "${aws_vpc.default.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = ["aws_internet_gateway.gw"]
}

resource "aws_elb" "web" {
  name = "example-elb"

  subnets = ["${aws_subnet.tf_test_subnet.id}"]

  security_groups = ["${aws_security_group.elb.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = ["${aws_instance.web.id}"]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
}

resource "aws_instance" "web" {
  instance_type = "${var.elb_instance_size}"
  ami = "${var.aws_ami}"

  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id              = "${aws_subnet.tf_test_subnet.id}"

  tags {
    Name = "tf_test_aws_instance"
  }

/*
  provisioner "file" {
    source      = "index.html"
    destination = "/home/ec2-user/index.html"
    connection {
      type     = "ssh"
      user = "ec2-user"
      private_key = "${file("${var.key_name}.pem")}"
      agent = false
    }
  }

  provisioner "file" {
    source      = "Dockerfile"
    destination = "/home/ec2-user/Dockerfile"
    connection {
      type     = "ssh"
      user = "ec2-user"
      private_key = "${file("${var.key_name}.pem")}"
      agent = false
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y docker",
      "sudo service docker start",
      "cd /home/ec2-user",
      "sudo docker build -t sample_nginx .",
      "sudo docker run -d -p 80:80 sample_nginx"
    ]
    connection {
      type     = "ssh"
      user = "ec2-user"
      private_key = "${file("${var.key_name}.pem")}"
      agent = false
    }
  }
*/

  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_eip" "lb" {
  instance = "${aws_instance.web.id}"
  vpc      = true
}

#------------------------------------------------------------------
# Bastion

resource "aws_subnet" "tf_test_subnet_private_a" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${var.aws_region}a"

  tags {
    Name = "tf_test_subnet_private_a"
  }
}

resource "aws_subnet" "tf_test_subnet_private_b" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${var.aws_region}b"

  tags {
    Name = "tf_test_subnet_private_b"
  }
}

resource "aws_instance" "bastion" {
  instance_type = "${var.elb_instance_size}"
  ami = "${var.aws_ami}"

  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id              = "${aws_subnet.tf_test_subnet_private_a.id}"

  tags {
    Name = "tf_test_bastion_host"
  }
}

resource "aws_eip" "bastion" {
  instance = "${aws_instance.bastion.id}"
  vpc      = true
}

resource "aws_security_group" "bastion_sg" {
  name   = "bastion-security-group"
  vpc_id = "${aws_vpc.default.id}"

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0 
    to_port     = 0 
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "db_instance" {
  allocated_storage    = 10
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "mydb"
  username             = "foo"
  password             = "foobarbaz"
  db_subnet_group_name = "${aws_db_subnet_group.db_subnet_group.id}"
  skip_final_snapshot  = "true"

  tags {
    Name = "tf_test_db_instance"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "main"
  subnet_ids = ["${aws_subnet.tf_test_subnet_private_a.id}", "${aws_subnet.tf_test_subnet_private_b.id}"]

  tags {
    Name = "tf_test_db_subnet_group"
  }
}
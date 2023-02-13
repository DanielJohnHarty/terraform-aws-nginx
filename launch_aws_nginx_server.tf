provider "aws" {
  # region and ami are interdependent
  region     = "eu-west-3"
  access_key = "<aws access key>"
  secret_key = "<aws secret key>"
}

// Create an aws keypair by passing the public key of a locally generated one
resource "aws_key_pair" "terraform-nginx-key" {
  key_name   = "terraform-nginx-key"
  public_key = "<public key as plan text for which you have a private key locally>"
}

# Create a new vpc for this exercise
resource "aws_vpc" "terraform-nginx-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "terraform-nginx-vpc"
  }
}

# Create a public subnet
resource "aws_subnet" "terraform_nginx_public_subnet" {
  vpc_id            = aws_vpc.terraform-nginx-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-3a"

  tags = {
    Name = "terraform_nginx_public_subnet"
  }
}

# Create a private subnet
resource "aws_subnet" "terraform_nginx_private_subnet" {
  vpc_id            = aws_vpc.terraform-nginx-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-3b"

  tags = {
    Name = "terraform_nginx_private_subnet"
  }
}

# We need to attach an internet gateway to the vpc or outside traffic has no mechanism to enter
resource "aws_internet_gateway" "terraform-nginx-ig" {
  vpc_id = aws_vpc.terraform-nginx-vpc.id

  tags = {
    Name = "terraform-nginx-ig"
  }
}

# Create a route table directing traffic leaving the network
resource "aws_route_table" "terraform_nginx_public_rt" {
  vpc_id = aws_vpc.terraform-nginx-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terraform-nginx-ig.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.terraform-nginx-ig.id
  }

  tags = {
    Name = "teraform_nginx_public_rt"
  }
}

# We associate the public subnet to the route table directing traffic out via the internet gateway
resource "aws_route_table_association" "nginx_public_1_rt_a" {
  subnet_id      = aws_subnet.terraform_nginx_public_subnet.id
  route_table_id = aws_route_table.terraform_nginx_public_rt.id
}

# Create security group rules to manage traffic permissions in our network
resource "aws_security_group" "terraform_ssh_and_http_sg" {
  name   = "HTTP and SSH"
  vpc_id = aws_vpc.terraform-nginx-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create the ec2 instance in our vpc
resource "aws_instance" "terraform_nginx_ec2" {
  # region and ec2 ami are interdependent
  ami                         = "ami-0ca5ef73451e16dc1"
  instance_type               = "t2.micro"
  # The aws name of the public key created earlier in this file
  key_name                    = "terraform-nginx-key"
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.terraform_nginx_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.terraform_ssh_and_http_sg.id]

  # USer user_data to execute small scripts on the remote ec2
  user_data = <<-EOF
    #!/bin/bash -ex
    echo "this is where the user data mini script is executed (as root!)"
    EOF

  # Define the ssh connection mechanism for the remote-exec step
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("<local path to the private key matching the previously referenced public key>")
    host        = self.public_ip
  }

  # Provision nginx using remote-exec within the ec2 instance
  provisioner "remote-exec" {
    inline = [
      "sudo yum install nano",
      "sudo amazon-linux-extras install  nginx1 -y",
      "sudo systemctl enable nginx",
      "sudo systemctl start nginx"
    ]
  }

  # Perform a local action using local-exec
  provisioner "local-exec" {
    # Powershell aliases mean this works on Windows and Linux
    command = "echo ${self.private_ip} >> private_ips.txt"
  }

  # Make this a destroy time provisioner with the when = destroy
  provisioner "local-exec" {
    when = destroy
    # Powershell aliases mean this works on Windows and Linux (only executed whern the resource is destroyed)
    command = "echo 'Oh my world, my world! Who would have thought this child could have destroyed my beautiful wickedness!'"
  }
}

output "terraform_nginx_ec2" {
  value = aws_instance.terraform_nginx_ec2.public_ip
}

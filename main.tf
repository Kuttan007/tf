provider "aws" {
  region = "us-east-1"
  }


 resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "test-vpc"

  }
}
resource aws_subnet "public_subnet1" {

vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.0.0/18"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
 tags = {
    Name = "test-public-subnet-1"

  }
}
resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.64.0/18"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
 tags = {
    Name = "test-public-subnet-2"

  }
}
resource "aws_subnet" "private_subnet1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.128.0/18"
  availability_zone       = "us-east-1a"
 tags = {
    Name = "test-private-subnet-1"

  }
}

resource "aws_subnet" "private_subnet2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.192.0/18"
  availability_zone       = "us-east-1b"
 tags = {
    Name = "test-private-subnet-2"

  }
}
resource "aws_internet_gateway" "ig" {
vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "test-igw"

  }
}
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig] //internetgateway
   tags = {
    Name        = "test-eip"

  }
}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id  //depends on elasticip resource
  subnet_id     = aws_subnet.public_subnet1.id // creating on public_subnet1
  depends_on    = [aws_internet_gateway.ig]
  tags = {
    Name = "test-nat"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "test-public-route-table"

  }
}
resource "aws_route" "public_internet_gateway" {      // creating public route
  route_table_id         = aws_route_table.public.id  //  creating public route
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id  // defining internetgateway here
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "test-private-route-table"

  }
}
resource "aws_route" "private_nat_gateway" {

route_table_id         = aws_route_table.private.id  //  creating public route
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_nat_gateway.nat.id
  }

  resource "aws_route_table_association" "public_subnet1" {
  subnet_id      = aws_subnet.public_subnet1.id // taken from public_subnet1 block
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_subnet2" {
  subnet_id      = aws_subnet.public_subnet2.id     // taken from public_subnet2 block
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private_subnet1" {
  subnet_id      = aws_subnet.private_subnet1.id // taken from private_subnet1 block
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_subnet2" {
  subnet_id      = aws_subnet.private_subnet2.id // taken from private_subnet2 block
  route_table_id = aws_route_table.private.id
}


data "aws_ami" "amzlinux2" {
  most_recent = var.most_recent
  #provider    = aws.oregon
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }


  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

}

resource "aws_key_pair" "terraform" {
  key_name   = "terraform"
  public_key = file("/root/.ssh/id_rsa.pub")
}

resource "aws_security_group" "albsg" {
  vpc_id =  aws_vpc.vpc.id
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "alb-sg"
  }
}



resource "aws_security_group" "ec2-sg" {
  vpc_id =  aws_vpc.vpc.id
  ingress {
    description = "Allow SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    description = "Allow SSH traffic"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ec2-sg"
  }
}





  resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amzlinux2.id
  instance_type          = var.instance_type
   subnet_id     = aws_subnet.public_subnet1.id
 vpc_security_group_ids = [aws_security_group.ec2-sg.id]


  key_name = aws_key_pair.terraform.key_name

  tags = {
    Name = "bastion"
  }
}
resource "aws_instance" "web3" {
  ami = lookup(var.ec2_ami,var.region)
  instance_type          = var.instance_type
  subnet_id     = aws_subnet.private_subnet1.id
  user_data              = file("install.sh")
  count = 2
  key_name = aws_key_pair.terraform.key_name
  vpc_security_group_ids = [aws_security_group.ec2-sg.id]

  ebs_block_device {
    device_name = "/dev/sdf"
    volume_size = 60
    volume_type = "gp2"
  }
 tags = {
    # The count.index allows you to launch a resource
    # starting with the distinct index number 0 and corresponding to this instance.
    Name = "web3-${count.index}"
  }
}

resource "aws_lb" "alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.albsg.id]
  subnets            = [aws_subnet.public_subnet1.id,aws_subnet.public_subnet2.id]
  enable_cross_zone_load_balancing = true
  tags = {
    Environment = "test"
  }
}
resource "aws_lb_target_group" "alb-tg" {
  name     = "tf-lb-tg"
  port     = 8081
  protocol = "HTTP"
  deregistration_delay = 30
  vpc_id   = aws_vpc.vpc.id
  load_balancing_cross_zone_enabled=true

  health_check {
    healthy_threshold   = "2"
    interval            = "20"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "10"
    port                = "8081"
    path                = "/"
    unhealthy_threshold = "3"
    }


  tags = {
    Name = "test-TARGET-GROUP"
  }

}
resource "aws_lb_target_group_attachment" "test" {
  count = length(aws_instance.web3)
  target_group_arn = aws_lb_target_group.alb-tg.arn
  target_id = aws_instance.web3[count.index].id
}

resource "aws_alb_listener" "ec2-listener-http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 8081
  protocol          = "HTTP"

  default_action {
    target_group_arn    = aws_lb_target_group.alb-tg.arn
    type  = "forward"
  }
}


  resource "aws_launch_template" "foobar" {
  name_prefix   = "foobar"
  image_id      = "ami-03c7d01cf4dedc891"
  instance_type = "t2.micro"
  user_data = filebase64("install.sh")
 network_interfaces {
 subnet_id = aws_subnet.private_subnet1.id
 security_groups= ["${aws_security_group.ec2-sg.id}"]
}
 key_name = aws_key_pair.terraform.key_name



  tags = {
    Name = "foobar"
  }
}


resource "aws_autoscaling_group" "bar" {
  desired_capacity   = 2
  max_size           = 2
  min_size           = 1
  target_group_arns  = ["${aws_lb_target_group.alb-tg.arn}"]
  vpc_zone_identifier       = [aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id]
 launch_template {
    id      = aws_launch_template.foobar.id
    version = "$Latest"
  }
}

data "http" "my_ip" {
  url = "http://checkip.amazonaws.com/"
}

data "aws_vpc" "default" {
  id = "vpc-048c313786f7c4c19"
  default = true
}

resource "aws_security_group" "vprofile-ELB-SG" {
  name        = "vprofile ELB-SG"
  description = "SecGroup for vprofile prod Load Balancer"
  vpc_id      = data.aws_vpc.default.id

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "vprofile ELB-SG"
    Project = "vprofile-lift-and-shift"
  }
}

resource "aws_security_group" "vprofile-app-sg" {
    name        = "vprofile-app-sg"
    description = "SecGroup for tomcat instances"
    vpc_id      = data.aws_vpc.default.id

    ingress {
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        security_groups = [aws_security_group.vprofile-ELB-SG.id]
        description = "Allow traffic from vprofile prod ELB"

    }
    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["${trimspace(data.http.my_ip.response_body)}/32"]
        description = "Allow SSH from my IP"
    }
    ingress {
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["${trimspace(data.http.my_ip.response_body)}/32"]
        description = "Allow 8080 from my IP"
    }

    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "vprofile-app-sg"
        Project = "vprofile-lift-and-shift"
    }
  
}

resource "aws_security_group" "vprofile-backend-sg" {
    name        = "vprofile-backend-sg"
    description = "SecGroup for vprofile backend instances"
    vpc_id      = data.aws_vpc.default.id

    ingress {
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        security_groups = [aws_security_group.vprofile-app-sg.id]
        description = "Allow Tomcat instances to connect to MySQL"
    } 

    ingress {
        from_port = 11211
        to_port = 11211
        protocol = "tcp"
        security_groups = [aws_security_group.vprofile-app-sg.id]
        description = "Allow Tomcat instances to connect to Memcached"
    } 

    ingress {
        from_port = 5672
        to_port = 5672
        protocol = "tcp"
        security_groups = [aws_security_group.vprofile-app-sg.id]
        description = "Allow Tomcat instances to connect to RabbitMQ"
    } 

    ingress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        self = true
        description = "Allow Internal traffic"
    } 

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["${trimspace(data.http.my_ip.response_body)}/32"]
        description = "Allow SSH from my IP"
    }

    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "vprofile-backend-sg"
        Project = "vprofile-lift-and-shift"
    }
  
}

resource "aws_instance" "vprofile-db-01" {
  ami = "ami-0427090fd1714168b"
  instance_type = "t2.micro"
  key_name = "vprofile-prod-key"

  vpc_security_group_ids = [aws_security_group.vprofile-backend-sg.id]

  user_data = <<-EOF
#!/bin/bash
DATABASE_PASS='admin123'
sudo yum update -y
#sudo yum install epel-release -y
sudo yum install git zip unzip -y
sudo dnf install mariadb105-server -y
# starting & enabling mariadb-server
sudo systemctl start mariadb
sudo systemctl enable mariadb
cd /tmp/
git clone -b main https://github.com/hkhcoder/vprofile-project.git
#restore the dump file for the application
sudo mysqladmin -u root password "$DATABASE_PASS"
sudo mysql -u root -p"$DATABASE_PASS" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DATABASE_PASS'"
sudo mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
sudo mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User=''"
sudo mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
sudo mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"
sudo mysql -u root -p"$DATABASE_PASS" -e "create database accounts"
sudo mysql -u root -p"$DATABASE_PASS" -e "grant all privileges on accounts.* TO 'admin'@'localhost' identified by 'admin123'"
sudo mysql -u root -p"$DATABASE_PASS" -e "grant all privileges on accounts.* TO 'admin'@'%' identified by 'admin123'"
sudo mysql -u root -p"$DATABASE_PASS" accounts < /tmp/vprofile-project/src/main/resources/db_backup.sql
sudo mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"
EOF

  tags = {
    Name = "vprofile-db-01"
    Project = "vprofile-lift-and-shift"
  }
  
}

resource "aws_instance" "vprofile-mc-01" {
  ami = "ami-0427090fd1714168b"
  instance_type = "t2.micro"
  key_name = "vprofile-prod-key"

  vpc_security_group_ids = [aws_security_group.vprofile-backend-sg.id]

  user_data = <<-EOF
#!/bin/bash
sudo dnf install memcached -y
sudo systemctl start memcached
sudo systemctl enable memcached
sudo systemctl status memcached
sed -i 's/127.0.0.1/0.0.0.0/g' /etc/sysconfig/memcached
sudo systemctl restart memcached
sudo yum install firewalld -y
sudo systemctl start firewalld
sudo systemctl enable firewalld
firewall-cmd --add-port=11211/tcp
firewall-cmd --runtime-to-permanent
firewall-cmd --add-port=11111/udp
firewall-cmd --runtime-to-permanent
sudo memcached -p 11211 -U 11111 -u memcached -d
EOF

  tags = {
    Name = "vprofile-mc-01"
    Project = "vprofile-lift-and-shift"
  }
  
}

resource "aws_instance" "vprofile-rmq-01" {
  ami = "ami-0427090fd1714168b"
  instance_type = "t2.micro"
  key_name = "vprofile-prod-key"

  vpc_security_group_ids = [aws_security_group.vprofile-backend-sg.id]

  user_data = <<-EOF
#!/bin/bash
## primary RabbitMQ signing key
rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc'
## modern Erlang repository
rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key'
## RabbitMQ server repository
rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key'
curl -o /etc/yum.repos.d/rabbitmq.repo https://raw.githubusercontent.com/hkhcoder/vprofile-project/aws-LiftAndShift/al2023rmq.repo
dnf update -y
## install these dependencies from standard OS repositories
dnf install socat logrotate -y
## install RabbitMQ and zero dependency Erlang
dnf install -y erlang rabbitmq-server
systemctl enable rabbitmq-server
systemctl start rabbitmq-server
sudo sh -c 'echo "[{rabbit, [{loopback_users, []}]}]." > /etc/rabbitmq/rabbitmq.config'
sudo rabbitmqctl add_user test test
sudo rabbitmqctl set_user_tags test administrator
sudo systemctl restart rabbitmq-server
EOF

  tags = {
    Name = "vprofile-rmq-01"
    Project = "vprofile-lift-and-shift"
  }
  
}


resource "aws_instance" "vprofile-app-01" {
  ami = "ami-0a0e5d9c7acc336f1"
  instance_type = "t2.micro"
  key_name = "vprofile-prod-key"

  vpc_security_group_ids = [aws_security_group.vprofile-app-sg.id]
  iam_instance_profile = aws_iam_instance_profile.vprofile-s3-instance-profile.name

  user_data = <<-EOF
#!/bin/bash
sudo apt update
sudo apt upgrade -y
sudo apt install openjdk-11-jdk -y
sudo apt install tomcat9 tomcat9-admin tomcat9-docs tomcat9-common git -y
sudo apt install awscli -y
sudo aws s3 cp s3://vprofile-lift-and-shift-123abc/vprofile-v2.war /tmp/
sudo systemctl stop tomcat9
sudo rm -rf /var/lib/tomcat9/webapps/ROOT
sudo cp /tmp/vprofile-v2.war /var/lib/tomcat9/webapps/ROOT.war
sudo systemctl start tomcat9
sudo cat /var/lib/tomcat9/webapps/ROOT/WEB-INF/classes/application.properties
EOF

  tags = {
    Name = "vprofile-app-01"
    Project = "vprofile-lift-and-shift"
  }
  
}

resource "aws_route53_zone" "vprofile-hosted-zone" {
  name = "vprofile.in"
  vpc {
    vpc_id = data.aws_vpc.default.id
    vpc_region = "us-east-1"
  }
  comment = "Private hosted zone for vprofile.in"
  tags = {
    Name = "vprofile.in"
    Project = "vprofile-lift-and-shift"
  }
}

resource "aws_route53_record" "db01" {
  zone_id = aws_route53_zone.vprofile-hosted-zone.zone_id
  name = "db01.vprofile.in"
  type = "A"
  ttl = "300"
  records = [aws_instance.vprofile-db-01.private_ip]
}

resource "aws_route53_record" "mc01" {
  zone_id = aws_route53_zone.vprofile-hosted-zone.zone_id
  name = "mc01.vprofile.in"
  type = "A"
  ttl = "300"
  records = [aws_instance.vprofile-mc-01.private_ip]
}

resource "aws_route53_record" "rmq01" {
  zone_id = aws_route53_zone.vprofile-hosted-zone.zone_id
  name = "rmq01.vprofile.in"
  type = "A"
  ttl = "300"
  records = [aws_instance.vprofile-rmq-01.private_ip]
}

resource "aws_s3_bucket" "vprofile-s3" {
  bucket = "vprofile-lift-and-shift-123abc"
  tags = {
    Name = "vprofile-lift-and-shift"
    Project = "vprofile-lift-and-shift"
  }
  
}

resource "aws_s3_object" "vprofile-s3-obj" {
  bucket = aws_s3_bucket.vprofile-s3.bucket
  key = "vprofile-v2.war"
  source = "../../116 EC2 Instance/vprofile-project/target/vprofile-v2.war"
}

resource "aws_iam_role" "vprofile-s3-role" {
  name = "vprofile-s3-role"
  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
  }
EOF
}

resource "aws_iam_role_policy_attachment" "vprofile-s3-full-access" {
  role = aws_iam_role.vprofile-s3-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "vprofile-s3-instance-profile" {
  name = "vprofile-s3-instance-profile"
  role = aws_iam_role.vprofile-s3-role.name
  
}

resource "aws_lb_target_group" "vprofile-app-tg" {
  name = "vprofile-app-tg"
  port = 8080
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check { 
    path = "/login"
    port = 8080
    protocol = "HTTP"
    healthy_threshold = 2
    unhealthy_threshold = 2
  }

  stickiness {
    type = "lb_cookie"
    cookie_duration = 86400
  }

  tags = {
    Name = "vprofile-app-tg"
    Project = "vprofile-lift-and-shift"
  }
  
}

resource "aws_lb_target_group_attachment" "vprofile-app-tg-attachment" {
  target_group_arn = aws_lb_target_group.vprofile-app-tg.arn
  target_id = aws_instance.vprofile-app-01.id
  port = 8080
  
}

resource "aws_lb" "vprofile-prod-elb" {
  name = "vprofile-prod-elb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.vprofile-ELB-SG.id]
  subnets = data.aws_subnets.all.ids

  enable_deletion_protection = false

  tags = {
    Name = "vprofile-prod-elb"
    Project = "vprofile-lift-and-shift"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.vprofile-prod-elb.arn
  port = "80"
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.vprofile-app-tg.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.vprofile-prod-elb.arn
  port = "443"
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-2016-08"
  certificate_arn = "arn:aws:acm:us-east-1:010526260632:certificate/0e73b116-7f6b-4f4b-95d7-ee512bd84279"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.vprofile-app-tg.arn
  }
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_ami_from_instance" "vprofile-app-image" {
  name = "vprofile-app-image"
  source_instance_id = aws_instance.vprofile-app-01.id
  description = "AMI of vprofile-app-01 instance"
  tags = {
    Name = "vprofile-app-image"
    Project = "vprofile-lift-and-shift"
  }
  
}

resource "aws_launch_template" "vprofile-app-LC" {
  name = "vprofile-app-LC"
  image_id = aws_ami_from_instance.vprofile-app-image.id
  instance_type = "t2.micro"
  key_name = "vprofile-prod-key"

  network_interfaces {
    security_groups = [ aws_security_group.vprofile-app-sg.id ]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "vprofile-app-LC"
      Project = "vprofile-lift-and-shift"
    }
  }

  tag_specifications{
    resource_type = "volume"
    tags = {
      Name = "vprofile-app-LC"
      Project = "vprofile-lift-and-shift"
    }
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = {
      Name = "vprofile-app-LC"
      Project = "vprofile-lift-and-shift"
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.vprofile-s3-instance-profile.name
  }

  
}

resource "aws_autoscaling_group" "vprofile-app-ASG" {
  name = "vprofile-app-ASG"
  max_size = 4
  min_size = 1
  desired_capacity = 1
  vpc_zone_identifier = data.aws_subnets.all.ids
  health_check_type = "ELB"
  target_group_arns = [aws_lb_target_group.vprofile-app-tg.arn]
  launch_template {
    id = aws_launch_template.vprofile-app-LC.id
    version = "$Latest"
  }

  tag {
    key = "Name"
    value = "vprofile-app-ASG"
    propagate_at_launch = true
  }

  tag {
    key = "Project"
    value = "vprofile-lift-and-shift"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "vprofile-app-ASG-policy" {
  name = "vprofile-app-ASG-policy"
  adjustment_type = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.vprofile-app-ASG.name
  policy_type = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
  
}
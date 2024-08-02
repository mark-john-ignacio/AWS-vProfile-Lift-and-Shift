data "http" "my_ip" {
  url = "http://checkip.amazonaws.com/"
}

data "aws_vpc" "default" {
  id = "vpc-048c313786f7c4c19"
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
    vpc_id      = "vpc-048c313786f7c4c19" 

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
    vpc_id      = "vpc-048c313786f7c4c19" 

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

  user_data = <<-EOF
#!/bin/bash
sudo apt update
sudo apt upgrade -y
sudo apt install openjdk-11-jdk -y
sudo apt install tomcat9 tomcat9-admin tomcat9-docs tomcat9-common git -y
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
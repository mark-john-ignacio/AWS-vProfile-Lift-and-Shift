data "http" "my_ip" {
  url = "http://checkip.amazonaws.com/"
}

resource "aws_security_group" "vprofile-ELB-SG" {
  name        = "vprofile ELB-SG"
  description = "SecGroup for vprofile prod Load Balancer"
  vpc_id      = "vpc-048c313786f7c4c19" 

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
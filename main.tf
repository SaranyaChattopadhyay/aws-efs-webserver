provider "aws" {
	region = "ap-south-1"
	profile = "Sara"
}


data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnet_ids" "default_subnet" {
  vpc_id = data.aws_vpc.default_vpc.id
}

//Creating Variable for AMI_ID
variable "ami_id" {
  type    = string
  default = "ami-0447a12f28fddb066"
}

//Creating Variable for AMI_Type
variable "ami_type" {
  type    = string
  default = "t2.micro"
}


//Creating Key
resource "tls_private_key" "tls_key" {
  algorithm = "RSA"
}


//Generating Key-Value Pair
resource "aws_key_pair" "generated_key" {
  key_name   = "rg-env-key"
  public_key = tls_private_key.tls_key.public_key_openssh


  depends_on = [
    tls_private_key.tls_key
  ]
}


//Saving Private Key PEM File
resource "local_file" "key-file" {
  content  = tls_private_key.tls_key.private_key_pem
  filename = "mykey.pem"


  depends_on = [
    tls_private_key.tls_key
  ]
}


//Creating Security Group for ec2 instance
resource "aws_security_group" "web-SG" {
  name        = "WEB-SG"
  description = "Web Environment Security Group"
  vpc_id      = data.aws_vpc.default_vpc.id


  //Adding Rules to Security Group
  ingress {
    description = "SSH Rule"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "HTTP Rule"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
  }
  depends_on = [tls_private_key.tls_key]
}

//Creating Security Group for efs storage
resource "aws_security_group" "efs-sg" {
  name        = "EFS-SG"
  description = "EFS security group"
  vpc_id      = data.aws_vpc.default_vpc.id
  ingress {
    to_port         = 0
    from_port       = 0
    protocol        = "-1"
    security_groups = [aws_security_group.web-SG.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
  }
  depends_on = [tls_private_key.tls_key]
}

//Creating efs cluster
resource "aws_efs_file_system" "myefs" {
  creation_token = "web-efs"
  tags = {
    Name = "Webstore"
  }
  depends_on = [aws_security_group.efs-sg]
}

resource "aws_efs_mount_target" "efs-mount" {
  for_each        = data.aws_subnet_ids.default_subnet.ids
  file_system_id  = aws_efs_file_system.myefs.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs-sg.id]
}

//Creating an S3 Bucket for Terraform Integration
resource "aws_s3_bucket" "sappy-murgi-bucket" {
  bucket = "sappy-murgi-bucket"
  acl    = "public-read"
}

//Putting Objects in S3 Bucket
resource "aws_s3_bucket_object" "web-object1" {
  bucket = aws_s3_bucket.sappy-murgi-bucket.bucket
  key    = "img.jpg"
  source = "C:/Users/saran/OneDrive/Desktop/AWS task-2/img.jpg"
  acl    = "public-read"
}

//Creating CloutFront with S3 Bucket Origin
resource "aws_cloudfront_distribution" "web-distribution" {
  origin {
    domain_name = aws_s3_bucket.sappy-murgi-bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.sappy-murgi-bucket.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront Distribution"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.sappy-murgi-bucket.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Name        = "web-distribution"
    Environment = "Production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_s3_bucket.sappy-murgi-bucket
  ]
}

//Launching First ec2 instance
resource "aws_instance" "first_instance" {
  ami             = var.ami_id
  instance_type   = var.ami_type
  key_name        = aws_key_pair.generated_key.key_name
  security_groups = [aws_security_group.web-SG.name]

  //Labelling the Instance
  tags = {
    Name = "Web-Env"
    env  = "Production"
  }
  connection {
      agent       = "false"
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.tls_key.private_key_pem
      host        = aws_instance.first_instance.public_ip
    }
    provisioner "remote-exec" {
      inline = [
      "sudo yum install httpd git -y",
      "sudo systemctl start httpd",
      "sudo yum install -y amazon-efs-utils",
      "sudo mount -t efs -o tls ${aws_efs_file_system.myefs.id}:/ /var/www/html",
      "sudo git clone https://github.com/SaranyaChattopadhyay/aws-efs-web.git /var/www/html",
      "echo '<img src='https://${aws_cloudfront_distribution.web-distribution.domain_name}/img.JPG' width='300' height='330'>' | sudo tee -a /var/www/html/Raktim.html",
    ]
 }
  depends_on = [
    aws_security_group.web-SG,
    aws_key_pair.generated_key,
    aws_efs_file_system.myefs,
    aws_efs_mount_target.efs-mount,
    aws_cloudfront_distribution.web-distribution,
  ]
}

//Launching Second ec2 instance
resource "aws_instance" "second_instance" {
  ami             = var.ami_id
  instance_type   = var.ami_type
  key_name        = aws_key_pair.generated_key.key_name
  security_groups = [aws_security_group.web-SG.name]

  //Labelling the Instance
  tags = {
    Name = "Web-Env"
    env  = "Production"
  }
   connection {
      agent       = "false"
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.tls_key.private_key_pem
      host        = aws_instance.second_instance.public_ip
    }
    provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd git amazon-efs-utils -y",
      "sudo systemctl start httpd",
      "sudo mount -t efs -o tls ${aws_efs_file_system.myefs.id}:/ /var/www/html",
    ]
}
  depends_on = [
    aws_security_group.web-SG,
    aws_key_pair.generated_key,
    aws_efs_file_system.myefs,
    aws_efs_mount_target.efs-mount,
    aws_cloudfront_distribution.web-distribution,
  ]
  
}



//Open web-page
resource "null_resource" "ChromeOpen"  {
depends_on = [
    aws_instance.first_instance,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.first_instance.public_ip}"
  	}
}
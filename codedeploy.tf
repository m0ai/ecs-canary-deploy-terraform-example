
resource "aws_ecs_cluster" "ecs_blog_app" {
  name = "ecs-linear-blog-ECSCluster-11YLDB94FDTSM"
}

resource "aws_lb_target_group" "blue" {
  name     = "blue-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.main.id}"
  target_type = "ip"
  health_check {
    enabled             = true 
    healthy_threshold   = 2 
    interval            = 6 
    matcher             = "200" 
    path                = "/" 
    port                = "traffic-port" 
    protocol            = "HTTP" 
    timeout             = 5 
    unhealthy_threshold = 2 
  }

  stickiness {
      cookie_duration = 86400 
      enabled         = false 
      type            = "lb_cookie" 
  }
  
}

resource "aws_lb_target_group" "green" {
  name     = "green-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.main.id}"

  target_type = "ip"
  health_check {
    enabled             = true 
    healthy_threshold   = 2 
    interval            = 6 
    matcher             = "200" 
    path                = "/" 
    port                = "traffic-port" 
    protocol            = "HTTP" 
    timeout             = 5 
    unhealthy_threshold = 2 
  }

  stickiness {
      cookie_duration = 86400 
      enabled         = false 
      type            = "lb_cookie" 
  }
}

resource "aws_lb" "ecs_blog_app" {
  name               = "public-elb"
  internal           = false
  load_balancer_type = "application"

  subnets            = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
  ]

  enable_deletion_protection = false 

  tags = {
    Environment = "production"
    Name = "ecs Public ALB"
  }
}

resource "aws_lb_listener" "ecs_blog_app_two" {
  load_balancer_arn = "${aws_lb.ecs_blog_app.arn}"
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.blue.arn}"
  }
}


resource "aws_lb_listener" "ecs_blog_app" {
  load_balancer_arn = "${aws_lb.ecs_blog_app.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.blue.arn}"
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.192.0.0/16"
}


resource "aws_subnet" "public_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.192.10.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public subnet 1b"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.192.11.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public subnet 1b"
  }
}



resource "aws_subnet" "private_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.192.20.0/24"
  map_public_ip_on_launch = false
  tags = {
    Name = "Main"
  }
}


resource "aws_subnet" "private_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.192.21.0/24"
  map_public_ip_on_launch = false
  tags = {
    Name = "Main"
  }
}

resource "aws_ecs_service" "ecs_blog_app" {
  name            = "ecs-blog-svc"
  cluster         = aws_ecs_cluster.ecs_blog_app.id // Done
  task_definition = aws_ecs_task_definition.ecs_linear_blog_svc.arn // done
  desired_count   = 2
  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }

  launch_type = "FARGATE"
  health_check_grace_period_seconds = 0


  deployment_controller {
      type = "CODE_DEPLOY" 
  }

  load_balancer {
    container_name   = "ecs-blog-svc"
    container_port   = 80
    target_group_arn = "${aws_lb_target_group.blue.arn}"
  }
  network_configuration {
    assign_public_ip = true
    security_groups  = [ "sg-02fd0287137558613", ] 
    subnets          = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id,
    ] 
  }
}
resource "aws_ecs_task_definition" "ecs_linear_blog_svc" {
  family                = "service"
  container_definitions = "${file("service.json")}"
cpu                      = 256
  memory                   = 512

    network_mode = "awsvpc"
    requires_compatibilities = ["FARGATE"]

}


resource "aws_iam_role" "ecs_codedeploy" {
  name = "ecs-linear-blog-EcsRoleForCodeDeploy-ZSYUX7G93KHB"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "codedeploy.amazonaws.com",
          "razorbillfrontend-gamma.amazon.com"
        ]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    tag-key = "tag-value"
  }
}
resource "aws_codedeploy_app" "ecs_blog_app" {
  compute_platform = "ECS"
  name             = "ecs-blog-app"
}

resource "aws_codedeploy_deployment_group" "ecs_blog_app_dg" {
  app_name               = "${aws_codedeploy_app.ecs_blog_app.name}"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_group_name  = "ecs-blog-app-dg"
  service_role_arn       = "${aws_iam_role.ecs_codedeploy.arn}"

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = "${aws_ecs_cluster.ecs_blog_app.name}"
    service_name = "${aws_ecs_service.ecs_blog_app.name}"
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.ecs_blog_app.arn]
      }

      target_group {
        name = aws_lb_target_group.green.name
      }

      target_group {
        name = aws_lb_target_group.blue.name
      }
      test_traffic_route {
        listener_arns = [aws_lb_listener.ecs_blog_app_two.arn]
         
      }
    }
  }
}

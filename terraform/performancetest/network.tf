resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  #   enable_dns_hostnames = true
  #   enable_dns_support   = true
  tags = {
    Name = "performancetest-vpc"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-2a"
  tags = {
    Name = "performancetest-private-subnet"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-2b"
  tags = {
    Name = "performancetest-public-subnet"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "performancetest-igw"
  }
}

resource "aws_eip" "nat_ip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]
  tags = {
    Name = "performancetest-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  subnet_id         = aws_subnet.public.id
  allocation_id     = aws_eip.nat_ip.id
  connectivity_type = "public"
  depends_on        = [aws_internet_gateway.this]
  tags = {
    Name = "performancetest-nat-gateway"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "performancetest-private-rt"
  }
}

resource "aws_route" "private_to_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "performancetest-public-rt"
  }
}

resource "aws_route" "public_to_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public.id
}

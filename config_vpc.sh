#!/bin/bash

# Resource should be created:
# vpc-12345678 | cheshi_vpc_perf
# igw-12345678 | cheshi_igw_perf
# subnet-12345678 | cheshi_subnet_perf
# rtb-12345678 | cheshi_rtb_perf
# sg-12345678 | cheshi_sg_perf


function tag2id()
{
    # Query resource by tag and show its resource-id
    [ -z "$1" ] && exit 1
    aws ec2 describe-tags --filters "Name=value,Values=$1" --output json | jq -r .Tags[].ResourceId
}


function create_vpc()
{
    # Name tag: cheshi_vpc_perf
    # IPv4 CIDR block*: 10.22.0.0/16
	# IPv6 CIDR block*: Amazon provided IPv6 CIDR block
	# Tenancy: Default
    # DNS Hostnames: Yes

    # Create VPC
    x=$(aws ec2 create-vpc --cidr-block 10.22.0.0/16 --amazon-provided-ipv6-cidr-block --tenancy default --output json)
    if [ $? -eq 0 ]; then
        vpcid=$(echo $x | jq -r .VpcId)
        echo "new vpc created, resource-id = $vpcid."
    else
        echo "$0: line $LINENO: \"aws ec2 create-vpc\" failed."
        exit 1
    fi

    # Create tag
    x=$(aws ec2 create-tags --resources $vpcid --tags Key=Name,Value=cheshi_vpc_perf --output json)
    if [ $? -eq 0 ]; then
        echo "tag created for this resource."
    else
        echo "$0: line $LINENO: \"aws ec2 create-tags\" failed."
        exit 1
    fi

    # Enable DNS
    x=$(aws ec2 modify-vpc-attribute --vpc-id $vpcid --enable-dns-hostnames --enable-dns-support --output json)
    if [ $? -eq 0 ]; then
        echo "enabled dns for this vpc."
    else
        echo "$0: line $LINENO: \"aws ec2 modify-vpc-attribute\" failed."
        exit 1
    fi
}


function describe_vpc()
{
    [ -z "$1" ] && exit 1 || vpcid=$1
    aws ec2 describe-vpcs --vpc-id $vpcid --output table
    aws ec2 describe-vpc-attribute --vpc-id $vpcid --attribute enableDnsSupport --output table
    aws ec2 describe-vpc-attribute --vpc-id $vpcid --attribute enableDnsHostnames --output table
}


function create_igw()
{
    # Name tag: cheshi_igw_perf
    # VPC: vpc-12345678 | cheshi_vpc_perf

    # Create IGW
    x=$(aws ec2 create-internet-gateway --output json)
    if [ $? -eq 0 ]; then
        igwid=$(echo $x | jq -r .InternetGateway.InternetGatewayId)
        echo "new igw created, resource-id = $igwid."
    else
        echo "$0: line $LINENO: \"aws ec2 create-internet-gateway\" failed."
        exit 1
    fi

    # Create tag
    x=$(aws ec2 create-tags --resources $igwid --tags Key=Name,Value=cheshi_igw_perf --output json)
    if [ $? -eq 0 ]; then
        echo "tag created for this resource."
    else
        echo "$0: line $LINENO: \"aws ec2 create-tags\" failed."
        exit 1
    fi

    # Attach to VPC
    vpcid=$(tag2id cheshi_vpc_perf)
    x=$(aws ec2 attach-internet-gateway --internet-gateway-id $igwid --vpc-id $vpcid --output json)
    if [ $? -eq 0 ]; then
        echo "attached igw to the vpc."
    else
        echo "$0: line $LINENO: \"aws ec2 attach-internet-gateway\" failed."
        exit 1
    fi
}


function describe_igw()
{
    [ -z "$1" ] && exit 1 || igwid=$1
    aws ec2 describe-internet-gateways --internet-gateway-ids $igwid --output table
}


function create_subnet()
{
    # Name tag: cheshi_subnet_perf
    # VPC: vpc-12345678 | cheshi_vpc_perf
    # VPC CIDRs: (2 CIDRs with status "associated" should be shown)
    # Availability Zone: us-west-2a
    # IPv4 CIDR block: 10.22.1.0/24
    # IPv6 CIDR block: Specify a custom IPv6 CIDR
    #                  xxxx:xxxx:xxxx:xx01::/64
    # Auto-assign IPs: [V] Enable auto-assign public IPv4 address
    #                  [V] Enable auto-assign IPv6 address
    #                  (Enable specified items)

    # Get VPC details
    x=$(aws ec2 describe-vpcs --vpc-id $(tag2id cheshi_vpc_perf) --output json)
    if [ $? -eq 0 ]; then
        vpcid=$(echo $x | jq -r .Vpcs[].VpcId)
        ipv4blk=$(echo $x | jq -r .Vpcs[].CidrBlock)
        ipv6blk=$(echo $x | jq -r .Vpcs[].Ipv6CidrBlockAssociationSet[].Ipv6CidrBlock)
    else
        echo "$0: line $LINENO: \"aws ec2 describe-vpcs\" failed."
        exit 1
    fi

    # Prepare subnet details
    taga="cheshi_subnet_a_perf"
    tagb="cheshi_subnet_b_perf"
    tagc="cheshi_subnet_c_perf"

    ipv4a=$(echo $ipv4blk | sed 's/0.0\/16/1.0\/24/')
    ipv6a=$(echo $ipv6blk | sed 's/00::\/56/01::\/64/')

    ipv4b=$(echo $ipv4blk | sed 's/0.0\/16/2.0\/24/')
    ipv6b=$(echo $ipv6blk | sed 's/00::\/56/02::\/64/')

    ipv4c=$(echo $ipv4blk | sed 's/0.0\/16/3.0\/24/')
    ipv6c=$(echo $ipv6blk | sed 's/00::\/56/03::\/64/')

    # Create subnets
    n=0
    zones=$(aws ec2 describe-availability-zones | jq -r .AvailabilityZones[].ZoneName | sort)
    for zone in $zones; do
        echo "creating subnet in zone: $zone"

        let n=n+1           # the range should be {1..9}
        l=${zone##*[0-9]}   # would be "a", "b", "c",...

        # Subnet parameter
        ipv4=$(echo $ipv4blk | sed "s/0.0\/16/${n}.0\/24/")
        ipv6=$(echo $ipv6blk | sed "s/00::\/56/0${n}::\/64/")
        tag="cheshi_subnet_${l}_perf"

        # Create subnet
        x=$(aws ec2 create-subnet --vpc-id $vpcid --cidr-block $ipv4 --ipv6-cidr-block $ipv6 --output json)
        if [ $? -eq 0 ]; then
            subnetid=$(echo $x | jq -r .InternetGateway.InternetGatewayId)
            echo "new subnet created, resource-id = $subnetid."
        else
            echo "$0: line $LINENO: \"aws ec2 create-subnet\" failed."
            exit 1
        fi

        # Create tag
        x=$(aws ec2 create-tags --resources $subnetid --tags Key=Name,Value=$tag --output json)
        if [ $? -eq 0 ]; then
            echo "tag created for this resource."
        else
            echo "$0: line $LINENO: \"aws ec2 create-tags\" failed."
            exit 1
        fi

        # Modify auto-assign IP settings
        x=$(aws ec2 modify-subnet-attribute --subnet-id $subnetid --map-public-ip-on-launch --output json)
        if [ $? -eq 0 ]; then
            echo "."
        else
            echo "$0: line $LINENO: \"aws ec2 modify-subnet-attribute\" failed."
            exit 1
        fi

        x=$(aws ec2 modify-subnet-attribute --subnet-id $subnetid --assign-ipv6-address-on-creation --output json)
        if [ $? -eq 0 ]; then
            echo "."
        else
            echo "$0: line $LINENO: \"aws ec2 modify-subnet-attribute\" failed."
            exit 1
        fi
    done
}


function describe_subnet()
{
    [ -z "$1" ] && exit 1 || subnetid=$1
    aws ec2 describe-subnets --subnet-ids $subnetid --output table
}


function main()
{
    date
    #describe_vpc $(tag2id cheshi_vpc_perf)
    #describe_igw $(tag2id cheshi_igw_perf)
    describe_subnet $(tag2id cheshi_subnet_a_perf)
    describe_subnet $(tag2id cheshi_subnet_b_perf)
    describe_subnet $(tag2id cheshi_subnet_c_perf)
}

main

exit 0

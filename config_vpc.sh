#!/bin/bash

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
        echo "tag created for this vpc."
    else
        echo "$0: line $LINENO: \"aws ec2 create-tags\" failed."
        exit 1
    fi

    # Enable DNS
    x=$(aws ec2 modify-vpc-attribute --vpc-id $vpcid --enable-dns-hostnames --enable-dns-support)
    if [ $? -eq 0 ]; then
        echo "enabled dns for this vpc."
    else
        echo "$0: line $LINENO: \"aws ec2 modify-vpc-attribute\" failed."
        exit 1
    fi

    exit 0
}

function describe_vpc()
{
    vpcid=$1
    aws ec2 describe-vpcs --vpc-id $vpcid --output table
    aws ec2 describe-vpc-attribute --vpc-id $vpcid --attribute enableDnsSupport --output table
    aws ec2 describe-vpc-attribute --vpc-id $vpcid --attribute enableDnsHostnames --output table

    exit 0
}


function main()
{
    date
    describe_vpc $(tag2id cheshi_vpc_perf)
}

main

exit 0

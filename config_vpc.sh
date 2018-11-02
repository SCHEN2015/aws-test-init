#!/bin/bash

# Description:
# This tool will help you creating the VPC for the further testing on AWS.
# You will need to specify whether the VPC need to support IPv6.

# History:
# v1.0.0  2017-12-07  charles.shih  Initial version
# v1.0.1  2018-11-02  charles.shih  Add description and history


# Resource to be created:
# vpc-12345678 | cheshi_vpc_perf
# igw-12345678 | cheshi_igw_perf
# subnet-12345671 | cheshi_subnet_a_perf
# subnet-12345672 | cheshi_subnet_b_perf
# subnet-12345673 | cheshi_subnet_c_perf
# subnet-......   | cheshi_subnet_......
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

    # Prepare parameter
    echo "creating vpc with CIDR block: ${ipcidr:="10.22.0.0/16"}"

    # Create VPC
    x=$(aws ec2 create-vpc --cidr-block $ipcidr --amazon-provided-ipv6-cidr-block --instance-tenancy default --output json)
    if [ $? -eq 0 ]; then
        vpcid=$(echo $x | jq -r .Vpc.VpcId)
        echo "new vpc created, resource-id = $vpcid."
    else
        echo "$0: line $LINENO: \"aws ec2 create-vpc\" failed."
        exit 1
    fi

    # Create tag
    x=$(aws ec2 create-tags --resources $vpcid --tags Key=Name,Value=${userid}_vpc_perf --output json)
    if [ $? -eq 0 ]; then
        echo "tag created for this resource."
    else
        echo "$0: line $LINENO: \"aws ec2 create-tags\" failed."
        exit 1
    fi

    # Enable DNS
    x=$(aws ec2 modify-vpc-attribute --vpc-id $vpcid --enable-dns-support --output json)
    if [ $? -eq 0 ]; then
        echo "enabled dns support for this vpc."
    else
        echo "$0: line $LINENO: \"aws ec2 modify-vpc-attribute\" failed."
        exit 1
    fi

    x=$(aws ec2 modify-vpc-attribute --vpc-id $vpcid --enable-dns-hostnames --output json)
    if [ $? -eq 0 ]; then
        echo "enabled dns hostnames for this vpc."
    else
        echo "$0: line $LINENO: \"aws ec2 modify-vpc-attribute\" failed."
        exit 1
    fi
}


function describe_vpc()
{
    [ -z "$1" ] && return 1 || vpcid=$1
    aws ec2 describe-vpcs --vpc-id $vpcid --output table || return $?
    aws ec2 describe-vpc-attribute --vpc-id $vpcid --attribute enableDnsSupport --output table || return $?
    aws ec2 describe-vpc-attribute --vpc-id $vpcid --attribute enableDnsHostnames --output table || return $?
    return 0
}


function delete_vpc()
{
    [ -z "$1" ] && return 1 || vpcid=$1
    x=$(aws ec2 delete-vpc --vpc-id $vpcid --output json)
    if [ $? -eq 0 ]; then
        echo "deleted this vpc."
    else
        echo "$0: line $LINENO: \"aws ec2 delete-vpc\" failed."
        exit 1
    fi
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
    x=$(aws ec2 create-tags --resources $igwid --tags Key=Name,Value=${userid}_igw_perf --output json)
    if [ $? -eq 0 ]; then
        echo "tag created for this resource."
    else
        echo "$0: line $LINENO: \"aws ec2 create-tags\" failed."
        exit 1
    fi

    # Attach to VPC
    vpcid=$(tag2id ${userid}_vpc_perf)
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
    [ -z "$1" ] && return 1 || igwid=$1
    aws ec2 describe-internet-gateways --internet-gateway-ids $igwid --output table
    return $?
}


function delete_igw()
{
    [ -z "$1" ] && return 1 || igwid=$1

    # Detach from VPC
    vpcid=$(tag2id ${userid}_vpc_perf)
    x=$(aws ec2 detach-internet-gateway --internet-gateway-id $igwid --vpc-id $vpcid --output json)
    if [ $? -eq 0 ]; then
        echo "detached igw from the vpc."
    else
        echo "$0: line $LINENO: \"aws ec2 detach-internet-gateway\" failed."
        exit 1
    fi

    # Delete IGW 
    x=$(aws ec2 delete-internet-gateway --internet-gateway-id $igwid --output json)
    if [ $? -eq 0 ]; then
        echo "deleted this igw."
    else
        echo "$0: line $LINENO: \"aws ec2 delete-internet-gateway\" failed."
        exit 1
    fi
}


function create_subnet()
{
    # Name tag: cheshi_subnet_x_perf
    # VPC: vpc-12345678 | cheshi_vpc_x_perf
    # VPC CIDRs: (2 CIDRs with status "associated" should be shown)
    # Availability Zone: us-west-2a
    # IPv4 CIDR block: 10.22.1.0/24
    # IPv6 CIDR block: Specify a custom IPv6 CIDR
    #                  xxxx:xxxx:xxxx:xx01::/64
    # Auto-assign IPs: [V] Enable auto-assign public IPv4 address
    #                  [V] Enable auto-assign IPv6 address
    #                  (Enable specified items)

    # Get VPC details
    x=$(aws ec2 describe-vpcs --vpc-id $(tag2id ${userid}_vpc_perf) --output json)
    if [ $? -eq 0 ]; then
        vpcid=$(echo $x | jq -r .Vpcs[].VpcId)
        ipv4blk=$(echo $x | jq -r .Vpcs[].CidrBlock)
        ipv6blk=$(echo $x | jq -r .Vpcs[].Ipv6CidrBlockAssociationSet[].Ipv6CidrBlock)
    else
        echo "$0: line $LINENO: \"aws ec2 describe-vpcs\" failed."
        exit 1
    fi

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
        tag="${userid}_subnet_${l}_perf"

        # Create subnet
        x=$(aws ec2 create-subnet --vpc-id $vpcid --availability-zone $zone --cidr-block $ipv4 --ipv6-cidr-block $ipv6 --output json)
        if [ $? -eq 0 ]; then
            subnetid=$(echo $x | jq -r .Subnet.SubnetId)
            echo "new subnet created, resource-id = $subnetid."
        else
            echo "$0: line $LINENO: \"aws ec2 create-subnet\" failed."
            echo "continue creating subnet in other zones if available."
            continue
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
            echo "configured auto assign public IP."
        else
            echo "$0: line $LINENO: \"aws ec2 modify-subnet-attribute\" failed."
            exit 1
        fi

        x=$(aws ec2 modify-subnet-attribute --subnet-id $subnetid --assign-ipv6-address-on-creation --output json)
        if [ $? -eq 0 ]; then
            echo "configured auto assign IPv6 address."
        else
            echo "$0: line $LINENO: \"aws ec2 modify-subnet-attribute\" failed."
            exit 1
        fi
    done
}


function describe_subnet()
{
    [ -z "$1" ] && return 1 || id=$1
    if [[ $id = "subnet-"* ]]; then
        aws ec2 describe-subnets --subnet-ids $id --output table
        return $?
    elif [[ $id = "vpc-"* ]]; then
        subnetids=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$id --output json | jq -r .Subnets[].SubnetId)
        for subnetid in $subnetids; do
            describe_subnet $subnetid
        done
        return 0
    fi
    return 1
}


function delete_subnet()
{
    [ -z "$1" ] && return 1 || id=$1
    if [[ $id = "subnet-"* ]]; then
        x=$(aws ec2 delete-subnet --subnet-id $id --output json)
        if [ $? -eq 0 ]; then
            echo "deleted subnet $id."
        else
            echo "$0: line $LINENO: \"aws ec2 delete-subnet\" failed."
            exit 1
        fi
    elif [[ $id = "vpc-"* ]]; then
        subnetids=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$id --output json | jq -r .Subnets[].SubnetId)
        for subnetid in $subnetids; do
            delete_subnet $subnetid
        done
    fi
}


function create_route_table()
{
    # Add default routes to the IGW:
    # | Destination    | Target         |
    # | :------------- | :------------- |
    # | 0.0.0.0/0      | igw-12345678   |
    # | ::/0           | igw-12345678   |
    #   (this tuple should be able to absence in the table)

    # Create route table
    # We don't need to create a new route table, we can use the default one.

    # Get route table information
    x=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$(tag2id ${userid}_vpc_perf) --output json)
    if [ $? -eq 0 ]; then
        vpcid=$(echo $x | jq -r .RouteTables[].VpcId)
        tableid=$(echo $x | jq -r .RouteTables[].RouteTableId)
        echo "find default route table $tableid in vpc $vpcid."
    else
        echo "$0: line $LINENO: \"aws ec2 describe-route-tables\" failed."
        exit 1
    fi

    # Create tag
    x=$(aws ec2 create-tags --resources $tableid --tags Key=Name,Value=${userid}_rtb_perf --output json)
    if [ $? -eq 0 ]; then
        echo "tag created for this resource."
    else
        echo "$0: line $LINENO: \"aws ec2 create-tags\" failed."
        exit 1
    fi

    # Create routes for the route table
    x=$(aws ec2 create-route --route-table-id $tableid --destination-cidr-block 0.0.0.0/0 --gateway-id $(tag2id ${userid}_igw_perf) --output json)
    if [ $? -eq 0 ]; then
        echo "created a route for this route table."
    else
        echo "$0: line $LINENO: \"aws ec2 create-route\" failed."
        exit 1
    fi

    x=$(aws ec2 create-route --route-table-id $tableid --destination-ipv6-cidr-block ::/0 --gateway-id $(tag2id ${userid}_igw_perf) --output json)
    if [ $? -eq 0 ]; then
        echo "created a route for this route table."
    else
        echo "$0: line $LINENO: \"aws ec2 create-route\" failed."
        exit 1
    fi

    # Associate the route table with subnets
    subnetids=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid --output json | jq -r .Subnets[].SubnetId)
    for subnetid in $subnetids; do
        x=$(aws ec2 associate-route-table --route-table-id $tableid --subnet-id $subnetid --output json)
        if [ $? -eq 0 ]; then
            echo "associated the route table with a subnet."
        else
            echo "$0: line $LINENO: \"aws ec2 associate-route-table\" failed."
            exit 1
        fi
    done
}


function describe_route_table()
{
    [ -z "$1" ] && return 1 || tableid=$1
    aws ec2 describe-route-tables --route-table-ids $tableid --output table
    return $?
}


function delete_route_table()
{
    [ -z "$1" ] && return 1 || tableid=$1

    # Disassociate the route table with subnets (non-main association only)
    assids=$(aws ec2 describe-route-tables --route-table-ids $tableid --output json | jq -r '.RouteTables[].Associations[] | select(.Main == false) | .RouteTableAssociationId')
    for assid in $assids; do
        x=$(aws ec2 disassociate-route-table --association-id $assid --output json)
        if [ $? -eq 0 ]; then
            echo "disassociated the route table with a subnet."
        else
            echo "$0: line $LINENO: \"aws ec2 disassociate-route-table\" failed."
            exit 1
        fi
    done

    # Delete routes from the route table
    # We don't need to delete them, since they will not block our processing.

    # Create tag
    x=$(aws ec2 delete-tags --resources $tableid --tags Key=Name --output json)
    if [ $? -eq 0 ]; then
        echo "tag deleted for this resource."
    else
        echo "$0: line $LINENO: \"aws ec2 delete-tags\" failed."
        exit 1
    fi

    # Delete route table
    # We haven't actually created the route table, so we don't need to delete it.
}


function create_security_group()
{
    # Name tag: cheshi_sg_perf
    # Group name: cheshi_sg_openall
    # Description: Testing purpose only, opening to the world, be careful about the security.
    # VPC: vpc-12345678 | cheshi_vpc_perf
    #      (select the VPC you just created in the drop-down list)
    #
    # Click "Add another rule" to add the following tuples (if not exist)
    # | Type            | Protocol       | Port Range     | Destination     |
    # | :-------------- | :------------- | :------------- | :-------------- |
    # | ALL Traffic     | ALL            | ALL            | 0.0.0.0/0, ::/0 |
    #   (Adding this tuple is not supported by CLI)
    # | ALL TCP         | TCP (6)        | ALL            | 0.0.0.0/0, ::/0 |
    # | ALL UDP         | UDP (17)       | ALL            | 0.0.0.0/0, ::/0 |
    # | ALL ICMP - IPv4 | ICMP (1)       | ALL            | 0.0.0.0/0       |
    # | ALL ICMP - IPv6 | IPv6-ICMP (58) | ALL            | ::/0            |

    # Create security group
    x=$(aws ec2 create-security-group --group-name ${userid}_sg_openall --description "Testing purpose only, opening to the world, be careful about the security." --vpc-id $(tag2id ${userid}_vpc_perf) --output json)
    if [ $? -eq 0 ]; then
        groupid=$(echo $x | jq -r .GroupId)
        echo "new security group created, resource-id = $groupid."
    else
        echo "$0: line $LINENO: \"aws ec2 create-security-group\" failed."
        exit 1
    fi

    # Create tag
    x=$(aws ec2 create-tags --resources $groupid --tags Key=Name,Value=${userid}_sg_perf --output json)
    if [ $? -eq 0 ]; then
        echo "tag created for this resource."
    else
        echo "$0: line $LINENO: \"aws ec2 create-tags\" failed."
        exit 1
    fi

    # Remove rules from the security group
    ipperm=$(aws ec2 describe-security-groups --group-ids $groupid --output json | jq -r .SecurityGroups[].IpPermissions)
    if [ "$ipperm" != "[]" ]; then
        x=$(aws ec2 revoke-security-group-ingress --group-id $groupid --ip-permissions "$ipperm" --output json)
        if [ $? -eq 0 ]; then
            echo "in-bound rules removed from the security group."
        else
            echo "$0: line $LINENO: \"aws ec2 revoke-security-group-ingress\" failed."
            exit 1
        fi
    fi

    ipperm=$(aws ec2 describe-security-groups --group-ids $groupid --output json | jq -r .SecurityGroups[].IpPermissionsEgress)
    if [ "$ipperm" != "[]" ]; then
        x=$(aws ec2 revoke-security-group-egress --group-id $groupid --ip-permissions "$ipperm" --output json)
        if [ $? -eq 0 ]; then
            echo "out-bound rules removed from the security group."
        else
            echo "$0: line $LINENO: \"aws ec2 revoke-security-group-egress\" failed."
            exit 1
        fi
    fi

    # Add rules to the security group
    ipperm='[
        {"IpProtocol": "tcp", "FromPort": 0, "ToPort": 65535, "IpRanges": [{"CidrIp": "0.0.0.0/0"}], "Ipv6Ranges": [{"CidrIpv6": "::/0"}]},
        {"IpProtocol": "udp", "FromPort": 0, "ToPort": 65535, "IpRanges": [{"CidrIp": "0.0.0.0/0"}], "Ipv6Ranges": [{"CidrIpv6": "::/0"}]},
        {"IpProtocol": "icmp", "FromPort": -1, "ToPort": -1, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},
        {"IpProtocol": "icmpv6", "FromPort": -1, "ToPort": -1, "Ipv6Ranges": [{"CidrIpv6": "::/0"}]}
        ]'

    x=$(aws ec2 authorize-security-group-ingress --group-id $groupid --ip-permissions "$ipperm" --output json)
    if [ $? -eq 0 ]; then
        echo "in-bound rules added to the security group."
    else
        echo "$0: line $LINENO: \"aws ec2 authorize-security-group-ingress\" failed."
        exit 1
    fi

    x=$(aws ec2 authorize-security-group-egress --group-id $groupid --ip-permissions "$ipperm" --output json)
    if [ $? -eq 0 ]; then
        echo "out-bound rules added to the security group."
    else
        echo "$0: line $LINENO: \"aws ec2 authorize-security-group-egress\" failed."
        exit 1
    fi
}


function describe_security_group()
{
    [ -z "$1" ] && return 1 || groupid=$1
    aws ec2 describe-security-groups --group-ids $groupid --output table
    return $?
}


function delete_security_group()
{
    [ -z "$1" ] && return 1 || groupid=$1
    x=$(aws ec2 delete-security-group --group-id $groupid --output json)
    if [ $? -eq 0 ]; then
        echo "deleted this security group."
    else
        echo "$0: line $LINENO: \"aws ec2 delete-security-group\" failed."
        exit 1
    fi
}


function create_vpc_network()
{
    date
    create_vpc
    create_igw
    create_subnet
    create_route_table
    create_security_group
}


function describe_vpc_network()
{
    date
    describe_vpc $(tag2id ${userid}_vpc_perf)
    describe_igw $(tag2id ${userid}_igw_perf)
    #describe_subnet $(tag2id ${userid}_subnet_a_perf)
    #describe_subnet $(tag2id ${userid}_subnet_b_perf)
    #describe_subnet $(tag2id ${userid}_subnet_c_perf)
    describe_subnet $(tag2id ${userid}_vpc_perf)
    describe_route_table $(tag2id ${userid}_rtb_perf)
    describe_security_group $(tag2id ${userid}_sg_perf)
}


function delete_vpc_network()
{
    date
    delete_security_group $(tag2id ${userid}_sg_perf)
    delete_route_table $(tag2id ${userid}_rtb_perf)
    delete_subnet $(tag2id ${userid}_vpc_perf)
    delete_igw $(tag2id ${userid}_igw_perf)
    delete_vpc $(tag2id ${userid}_vpc_perf)
}


function summary_resource()
{
    function tbprint()
    {
        #printf "%s | %s\n" "$1" "$2"
        printf "%-22s %-15s\n" "$1" "$2"
    }

    # Summary resource
    tbprint "ResourceTagName" "ResourceID"

    tbprint "${userid}_vpc_perf" "$(tag2id ${userid}_vpc_perf)"
    tbprint "${userid}_igw_perf" "$(tag2id ${userid}_igw_perf)"

    subnets=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$(tag2id ${userid}_vpc_perf) --output json)
    subnettags=$(echo $subnets | jq -r '.Subnets[].Tags[] | select(.Key == "Name") | .Value')
    for subnettag in $subnettags; do
        tbprint "$subnettag" "$(tag2id $subnettag)"
    done

    tbprint "${userid}_rtb_perf" "$(tag2id ${userid}_rtb_perf)"
    tbprint "${userid}_sg_perf" "$(tag2id ${userid}_sg_perf)"
}


# main
ipcidr=10.22.0.0/16
userid=cheshi

#create_vpc_network
#describe_vpc_network
#delete_vpc_network
summary_resource

exit 0

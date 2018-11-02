# aws-test-init
Do essential initialization for AWS testing

# VPC

```
Usage:
  config_vpc.sh -h
  config_vpc.sh -c [-i <ipv4_icdr>] [-l <label>] [-4]
  config_vpc.sh <-d|-r|-s> [-l <label>] [-4]

Params:
  -h: show this help
  -c: create a new VPC
  -d: describe a specified VPC
  -r: delete a specified VPC
  -s: summary the resources related to a specified VPC
  -i: specify an IPv4 ICDR block for creating an VPC
  -l: specify the label for an VPC
  -4: specify an IPv4 only mode for this tool

Examples:
  config_vpc.sh -c                  # creating an VPC with default options
  config_vpc.sh -c -4               # creating an VPC without IPv6 support
  config_vpc.sh -c -i 10.23.0.0/16  # creating an VPC with specified IPv4 ICDR
  config_vpc.sh -c -l cheshi        # creating an VPC with specified label
                                      it generates 'cheshi_vpc_perf' ...
  config_vpc.sh -d -l cheshi        # describe VPC 'cheshi_vpc_perf' and its resources
  config_vpc.sh -r -l cheshi        # remove VPC 'cheshi_vpc_perf' and its resources
  config_vpc.sh -s -l cheshi        # summary the resources from VPC 'cheshi_vpc_perf'
  config_vpc.sh -s                  # summary the resources from VPC 'ipv6_vpc_perf'
  config_vpc.sh -s -4               # summary the resources from VPC 'ipv4_vpc_perf'
```

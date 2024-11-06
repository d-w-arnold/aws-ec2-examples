# aws-ec2-examples

What is [AWS EC2](https://aws.amazon.com/ec2/)?

This repo is a submodule of: [aws-cdk-examples](https://github.com/d-w-arnold/aws-cdk-examples)

### User Data

Each directory contains a `user-data.sh` script, which acts as the [EC2 user data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html).

### Useful debug commands

Note: These commands are intended to be run on the EC2 instance which has the EC2 user data set.

#### Check which steps of EC2 User Data have run:

```bash
cat /var/log/cloud-init-output.log | grep "##"
```

#### Tail the last 200 lines of the output log for the EC2 User Data:

```bash
tail -f -n 200 /var/log/cloud-init-output.log
```

#### See user data passed to the EC2 instance.

```bash
curl -s http://instance-data/latest/user-data
```

For this you'll need to create a bastion manually in the public subnet.

If you want to use Guacamole, the policies and role are created by my Terraform scripts, only requiring to deploy the instance:

https://aws.amazon.com/marketplace/pp/prodview-hl2sry7k37mgq

**User:** guacadmin
**Password:** Instance ID

And to login into the private server, use the user and password from the `private.userdata.sh` file, which should be:

**User:** ec2-user
**Password:** kaiwinn

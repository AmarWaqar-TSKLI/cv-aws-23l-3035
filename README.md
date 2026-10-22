# Host Your CV on AWS - 23L-3035

Amar Waqar · 23L-3035 · Region `ap-south-1`

- EC2: http://13.232.129.253/
- Lambda: https://qzzk6phjqkxcprhhdtdgekmyeq0wmsxw.lambda-url.ap-south-1.on.aws/
- Bucket: `cv-23l-3035` (private)

## Diagram

```
 Browser --HTTP:80--> EC2 cv-ec2-23l-3035 (nginx)
                         ^
                         | sync-cv.sh every 2 min (role cv-ec2-role-23l-3035)
                         |
                 S3 bucket cv-23l-3035 (private)
                 site/index.html, site/style.css, site/cv.pdf
                         |
                         | GetObject per request (role cv-lambda-role-23l-3035)
                         v
 Browser --HTTPS--> Function URL --> Lambda cv-func-23l-3035

 Browser --> S3 URL directly --> 403 Access Denied
```

**EC2:** The request goes to the instance's public IP on port 80, and nginx serves the files that the sync script copies from the bucket every 2 minutes using the instance role.
**Lambda:** The request goes to the function URL, which runs the function; it reads the file from the bucket with its role, replaces the footer and returns it.

## Access denied from the instance

```
[ec2-user@ip-172-31-1-40 ~]$ aws s3 rm s3://cv-23l-3035/site/index.html
delete failed: s3://cv-23l-3035/site/index.html An error occurred (AccessDenied) when calling the DeleteObject operation: User: arn:aws:sts::627551519533:assumed-role/cv-ec2-role-23l-3035/i-0191d93f7c8dc061e is not authorized to perform: s3:DeleteObject on resource: "arn:aws:s3:::cv-23l-3035/site/index.html" because no identity-based policy allows the s3:DeleteObject action
[ec2-user@ip-172-31-1-40 ~]$ aws s3 cp /etc/hostname s3://cv-23l-3035/site/index.html
upload failed: ../../etc/hostname to s3://cv-23l-3035/site/index.html An error occurred (AccessDenied) when calling the PutObject operation: User: arn:aws:sts::627551519533:assumed-role/cv-ec2-role-23l-3035/i-0191d93f7c8dc061e is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::cv-23l-3035/site/index.html" because no identity-based policy allows the s3:PutObject action
```

## Last 10 lines of /var/log/cv-sync.log

```
2026-10-22T11:01:37Z sync=ok instance=i-0191d93f7c8dc061e
2026-10-22T11:02:27Z sync=ok instance=i-0191d93f7c8dc061e
2026-10-22T11:04:28Z sync=ok instance=i-0191d93f7c8dc061e
2026-10-22T11:06:28Z sync=ok instance=i-0191d93f7c8dc061e
2026-10-22T11:08:28Z sync=ok instance=i-0191d93f7c8dc061e
2026-10-22T11:11:28Z sync=ok instance=i-0191d93f7c8dc061e
2026-10-22T11:13:28Z sync=ok instance=i-0191d93f7c8dc061e
2026-10-22T11:15:28Z sync=ok instance=i-0191d93f7c8dc061e
```

## Questions

**1. Why roles instead of access keys?**
A role gives temporary credentials that AWS rotates automatically, so there is no long-lived secret to store or leak. Keys in the user data can be read by anyone who can view the instance's user data, and they would also end up in this public repository. Anyone who finds them could use them from anywhere until they are deactivated, which could mean stolen data or a large bill.

**2. What happens when someone opens the S3 address of index.html?**
They get an XML error with AccessDenied (403). The bucket has no policy or ACL that allows public access, and Block Public Access is on, so anonymous requests are refused.

**3. The permission on the function URL.**
The function has a resource-based policy that lets any principal (`*`) call `lambda:InvokeFunctionUrl` when the auth type is NONE, plus `lambda:InvokeFunction` only through the URL. This is fine for the function because the code decides what is returned: only three fixed files and a 404 for everything else, with no way to write or list. A public bucket would expose every object directly with nothing in between.

**4. Comparing the two paths.**
With no visitors, EC2 still costs money for every hour it runs, plus its public IPv4 address and disk. Lambda costs nothing when idle; you pay per request and only S3 storage remains. At 100x traffic one t3.micro would slow down or fail unless more instances and a load balancer are added. Lambda scales on its own and the cost grows with the number of requests.

**5. Deleting the EC2 instance.**
I lose the instance, its disk, the web root copy, the sync log and its public IP, so a new instance would have a different address. The bucket and its versions, both roles, the security group, the Lambda site and the scripts in this repository are still there. Launching a new instance with the same user data rebuilds the EC2 site.

## Sources

AWS documentation for S3 Block Public Access, IAM roles for EC2, IMDSv2, Lambda function URLs and CloudWatch Logs retention.

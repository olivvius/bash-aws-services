import boto3
import json
import pymysql

# RDS configuration
rds_host = "mydbinstance.cjxakc123456.us-west-2.rds.amazonaws.com"
db_user = "myuser"
db_password = "mypassword"
db_name = "mydb"

# S3 configuration
s3_bucket = "my-bucket"

# Lambda handler function
def lambda_handler(event, context):
    # Connect to RDS database
    conn = pymysql.connect(rds_host, user=db_user, passwd=db_password, db=db_name, connect_timeout=5)
    
    # Retrieve user data from RDS
    with conn.cursor() as cursor:
        cursor.execute("SELECT * FROM users")
        rows = cursor.fetchall()
    
    # Load user data into S3 bucket
    s3 = boto3.resource("s3")
    filename = f"user_data_{context.aws_request_id}.json"
    object = s3.Object(s3_bucket, filename)
    object.put(Body=json.dumps(rows))
    
    # Return success message
    return {
        "statusCode": 200,
        "body": "User data loaded into S3 bucket"
    }

#!/bin/bash

# Charger les variables d'environnement à partir du fichier .env
source .env


# Configure AWS CLI
aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set default.region $REGION
aws configure set output json

echo "AWS CLI configuration completed."


######################## BDD ##############################################


# Créer la base de données RDS et la table
aws rds create-db-instance --db-instance-identifier mydbinstance \
--db-instance-class db.t2.micro \
--engine mysql \
--master-username $DB_USER \
--master-user-password $DB_PASSWORD \
--allocated-storage 5 \
--no-publicly-accessible

aws rds wait db-instance-available --db-instance-identifier mydbinstance

aws rds create-db-instance-read-replica \
    --db-instance-identifier mydbinstancereplica \
    --source-db-instance-identifier mydbinstance \
    --db-instance-class db.t2.micro

aws rds wait db-instance-available --db-instance-identifier mydbinstancereplica

aws rds create-db-parameter-group --db-parameter-group-name mydbparametergroup \
--db-parameter-group-family "mysql8.0" \
--description "My DB parameter group"

aws rds wait db-parameter-group-available --db-parameter-group-name mydbparametergroup

aws rds modify-db-instance --db-instance-identifier mydbinstance \
--db-parameter-group-name mydbparametergroup

aws rds modify-db-instance --db-instance-identifier mydbinstancereplica \
--db-parameter-group-name mydbparametergroup

aws rds create-db-instance-automated-backup --db-instance-identifier mydbinstance \
--no-publicly-accessible

aws rds create-db-instance-automated-backup --db-instance-identifier mydbinstancereplica \
--no-publicly-accessible

aws rds create-db-snapshot --db-instance-identifier mydbinstance \
--db-snapshot-identifier mydbsnapshot



# Inserer des données dans la base de données

# variable db_instance
db_instance=$(aws rds describe-db-instances --db-instance-identifier mydbinstance)

# Extraire l'endpoint du RDS de la variable
db_endpoint=$(echo $db_instance | jq -r '.DBInstances[0].Endpoint.Address')

# Créer la base de données
mysql -h $db_endpoint -u $DB_USER -p$DB_PASSWORD -e "CREATE DATABASE mydb"

# Créer la table
mysql -h $db_endpoint -u $DB_USER -p$DB_PASSWORD mydb -e "CREATE TABLE users (id INT NOT NULL AUTO_INCREMENT, name VARCHAR(255) NOT NULL, email VARCHAR(255) NOT NULL, PRIMARY KEY (id));"

#insertion données
mysql -h $db_endpoint -u $DB_USER -p$DB_PASSWORD mydb << EOF
INSERT INTO users (name, email) VALUES ('John Doe', 'johndoe@example.com');
INSERT INTO users (name, email) VALUES ('Jane Doe', 'janedoe@example.com');
INSERT INTO users (name, email) VALUES ('Bob Smith', 'bobsmith@example.com');
EOF



########################## BUCKET ######################################################


aws s3api create-bucket --bucket $S3_BUCKET --region $REGION




######################### IAM ROLLE #####################################

aws iam create-role \
    --role-name my-lambda-role \
    --assume-role-policy-document file://lambda-trust-policy.json

aws iam attach-role-policy \
    --role-name my-lambda-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonRDSDataFullAccess




######################### PUSH LAMBDA FUNCTION INTO BUCKET ############################


# Définir le nom du fichier à envoyer
filename="lambda_handler.py"

# Définir le nom du bucket S3 dédié
bucket_name=$S3_BUCKET

# Créer sous dossier lambdas
aws s3api put-object --bucket $S3_BUCKET --key lambdas/ --metadata x-amz-meta-mkdir=true

# Envoyer le fichier vers le bucket S3
aws s3 cp lambda_handler.py s3://$S3_BUCKET/lambdas/


######################## LAMBDA #######################################################


VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=my-vpc" --query 'Vpcs[0].VpcId' --output text)



subnet_ids=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=VPC_ID" --query "Subnets[].SubnetId" --output text)

security_group_ids=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=VPC_ID" --query "SecurityGroups[].GroupId" --output text)



aws lambda create-function \
    --function-name my-function \
    --runtime python3.8 \
    --handler lambda_handler.lambda_handler \
    --role my-lambda-role-arn \
    --code S3Bucket=$S3_BUCKET,S3Key=my-lambda-code.zip \
    --environment Variables={DB_HOST=$db_instance,DB_USER=$DB_USER,DB_PASSWORD=$DB_PASSWORD,S3_BUCKET=$S3_BUCKET} \
    --timeout 30 \
    --memory-size 128 \
    --vpc-config SubnetIds=$subnet_ids,SecurityGroupIds=$security_group_ids

lambda_arn=$(aws lambda get-function --function-name my-function --query 'Configuration.FunctionArn' --output text)

#################### PERMISSIONS #######################################################




aws lambda add-permission \
    --function-name my-function \
    --statement-id my-statement-id \
    --principal s3.amazonaws.com \
    --action lambda:InvokeFunction \
    --source-arn arn:aws:s3:::my-bucket \
    --source-account 123456789012

aws lambda add-permission \
    --function-name my-function \
    --statement-id my-statement-id \
    --principal rds.amazonaws.com \
    --action lambda:InvokeFunction \
    --source-arn arn:aws:rds:us-west-2:123456789012:db:mydbinstance \
    --source-account 123456789012


############# TRIGGER #########################################################

aws events put-rule --name my-rule --schedule-expression "rate(24 hours)"

aws events put-targets --rule my-rule --targets "Id"="1","Arn"=$lambda_arn







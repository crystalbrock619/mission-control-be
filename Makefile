SHELL := bash

.SHELLFLAGS := -eu -o pipefail -c  

include .env
export

NO_COLOR		:= \x1b[0m
OK_COLOR		:= \x1b[32;01m
ERROR_COLOR	:= \x1b[31;01m
WARN_COLOR	:= \x1b[33;01m

# =================================================================
# = Utility targets ===============================================
# =================================================================

# =================================================================
# Allows a target to require environment variables to exist
# Example that will only run 'mytarget' when the environment variable named 'SERVER' has been set:
#  mytarget: env-SERVER another-dependency
# =================================================================
env-%:
	@if [ "${${*}}" = "" ]; then \
		echo "Required environment variable $* not set"; \
		echo; \
		exit 1; \
	fi

clean:
	@echo
	@echo Cleaning up
	@rm -rf apollo/dist apollo/node_modules apollo/src/generated apollo/schema/generated

init: clean
	@echo
	@echo Initializing
	@cd apollo && npm install -production && npm prune


# =================================================================
# = Prisma targets ================================================
# =================================================================

prisma-generate:
	@echo
	@echo Generating Prisma schema
	@cd prisma && \
	prisma generate

local-prisma-deploy:
	@echo
	@echo Deploying Prisma schema
	@cd prisma && \
	prisma deploy

local-prisma-token:
	@echo
	@echo Generating Prisma token
	@cd prisma && \
	prisma token


# =================================================================
# = Apollo targets ================================================
# =================================================================

apollo-docker-build: prisma-generate
	@printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Building Apollo container image"																												&& \
	 printf "%s\n"   "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd apollo && docker build -t lambdaschoollabs/missioncontrol:latest .

apollo-push: apollo-docker-build
	@printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Pushing Apollo container image"																													&& \
	 printf "%s\n"     "======================================================================================"	&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd apollo && docker push lambdaschoollabs/missioncontrol:latest

apollo-token: env-TEST_OAUTH_TOKEN_ENDPOINT env-TEST_OAUTH_CLIENT_ID env-TEST_OAUTH_CLIENT_SECRET
	@echo
	@echo Generating token that can be used for Apollo
	@curl --request POST \
		--url ${TEST_OAUTH_TOKEN_ENDPOINT}/v1/token \
		--header 'content-type: application/x-www-form-urlencoded' \
		--data 'grant_type=client_credentials&scope=groups' -u ${TEST_OAUTH_CLIENT_ID}:${TEST_OAUTH_CLIENT_SECRET}


# =================================================================
# = AWS targets ===================================================
# =================================================================

# =================================================================
# Show a banner before running stuff in AWS
# =================================================================
aws-banner: env-APPLICATION_NAME env-ENVIRONMENT_NAME
	@printf "$(WARN_COLOR)"
	@printf "%s\n" "======================================================================================"
	@printf "%s\n" "= Attention!!"
	@printf "%s\n" "= This command is going to be executed in the following AWS environment:"
	@printf "%s\n" "=   Application: $(APPLICATION_NAME)"
	@printf "%s\n" "=   Environment: $(ENVIRONMENT_NAME)"
	@printf "%s\n" "======================================================================================"
	@printf "$(NO_COLOR)"
	@( read -p "Are you sure you want to continue? [y/N]: " sure && case "$$sure" in [yY]) true;; *) false;; esac )

# =================================================================
# Provisions IAM resources for the application
# =================================================================
aws-deploy-app-iam: aws-banner
	@export AWS_STACK_NAME=$(APPLICATION_NAME)-iam 	 																														&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Deploying CloudFormation stack $${AWS_STACK_NAME}"																			&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 aws cloudformation deploy \
	  --no-fail-on-empty-changeset \
    --template-file app-iam.cf.yaml \
    --stack-name $${AWS_STACK_NAME} \
	  --capabilities CAPABILITY_IAM \
	  --parameter-overrides $$(jq -r '.[] | [.ParameterKey, .ParameterValue] | join("=")' params.json) \
	  --tags poweredby=prismatopia application=$(APPLICATION_NAME)

# =================================================================
# Deploys the application specific network resources to AWS
# =================================================================
aws-deploy-app-network: aws-banner
	@export AWS_STACK_NAME=$(APPLICATION_NAME)-network 	 																												&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Deploying CloudFormation stack $${AWS_STACK_NAME}"																			&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 aws cloudformation deploy \
	  --no-fail-on-empty-changeset \
    --template-file app-network.cf.yaml \
    --stack-name $${AWS_STACK_NAME} \
	  --capabilities CAPABILITY_IAM \
	  --parameter-overrides $$(jq -r '.[] | [.ParameterKey, .ParameterValue] | join("=")' params.json) \
	  --tags poweredby=prismatopia application=$(APPLICATION_NAME)

# ===========================================================================
# Provision DNS resources for the environment
# ===========================================================================
aws-deploy-env-dns: aws-banner
	@export AWS_STACK_NAME=$(APPLICATION_NAME)-$(ENVIRONMENT_NAME)-dns 																					&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Deploying CloudFormation stack $${AWS_STACK_NAME}"																			&& \
	 printf "$(WARN_COLOR)"																																											&& \
	 printf "%s\n"   "= Note: This will create a hosted zone for your domain. You may need to stop here and"		&& \
	 printf "%s\n"   "=       update your domain registrar with the name servers for this hosted zone."					&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 aws cloudformation deploy \
	  --no-fail-on-empty-changeset \
    --template-file env-dns.cf.yaml \
    --stack-name $${AWS_STACK_NAME} \
	  --parameter-overrides $$(jq -r '.[] | [.ParameterKey, .ParameterValue] | join("=")' params.json) \
	  --tags poweredby=prismatopia application=$(APPLICATION_NAME) environment=$(ENVIRONMENT_NAME)

# ===========================================================================
# Provision SSL certificate for the environmnet
# ===========================================================================
aws-deploy-env-certificate: aws-banner
	@export AWS_STACK_NAME=$(APPLICATION_NAME)-$(ENVIRONMENT_NAME)-certificate 	 																&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Deploying CloudFormation stack $${AWS_STACK_NAME}"																			&& \
	 printf "$(WARN_COLOR)"																																											&& \
	 printf "%s\n"   "= Note: You need to verify the certificate deployed by this step in the AWS console"			&& \
	 printf "%s\n"   "=       before you continue."																															&& \
	 printf "%s\n"   "=       TODO: https://github.com/binxio/cfn-certificate-provider"													&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 aws cloudformation deploy \
	  --no-fail-on-empty-changeset \
    --template-file env-certificate.cf.yaml \
    --stack-name $${AWS_STACK_NAME} \
	  --parameter-overrides $$(jq -r '.[] | [.ParameterKey, .ParameterValue] | join("=")' params.json) \
	  --tags poweredby=prismatopia application=$(APPLICATION_NAME) environment=$(ENVIRONMENT_NAME)

# ===========================================================================
# Provision network resources for the environment
# ===========================================================================
aws-deploy-env-network: aws-banner
	@export AWS_STACK_NAME=$(APPLICATION_NAME)-$(ENVIRONMENT_NAME)-network 	 																		&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Deploying CloudFormation stack $${AWS_STACK_NAME}"																			&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 aws cloudformation deploy \
	  --no-fail-on-empty-changeset \
    --template-file env-network.cf.yaml \
    --stack-name $${AWS_STACK_NAME} \
	  --parameter-overrides $$(jq -r '.[] | [.ParameterKey, .ParameterValue] | join("=")' params.json) \
	  --tags poweredby=prismatopia application=$(APPLICATION_NAME) environment=$(ENVIRONMENT_NAME)

# ===========================================================================
# Provision database resources for the environment
# ===========================================================================
aws-deploy-env-db: aws-banner
	@export AWS_STACK_NAME=$(APPLICATION_NAME)-$(ENVIRONMENT_NAME)-db 	 																				&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Deploying CloudFormation stack $${AWS_STACK_NAME}"		   																&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 aws cloudformation deploy \
	  --no-fail-on-empty-changeset \
    --template-file env-db.cf.yaml \
    --stack-name $${AWS_STACK_NAME} \
	  --parameter-overrides $$(jq -r '.[] | [.ParameterKey, .ParameterValue] | join("=")' params.json) \
	  --tags poweredby=prismatopia application=$(APPLICATION_NAME) environment=$(ENVIRONMENT_NAME)

# ===========================================================================
# Provisions the Prisma service for the environment
# ===========================================================================
aws-deploy-env-prisma: aws-banner
	@export AWS_STACK_NAME=$(APPLICATION_NAME)-$(ENVIRONMENT_NAME)-prisma 	 																				&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Deploying CloudFormation stack $${AWS_STACK_NAME}"		   																&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 aws cloudformation deploy \
	  --no-fail-on-empty-changeset \
	  --template-file env-prisma.cf.yaml \
	  --stack-name $${AWS_STACK_NAME} \
	  --parameter-overrides $$(jq -r '.[] | [.ParameterKey, .ParameterValue] | join("=")' params.json) \
	  --tags poweredby=prismatopia application=$(APPLICATION_NAME) environment=$(ENVIRONMENT_NAME)

# ===========================================================================
# Provisions the Apollo service for the environment
# ===========================================================================
aws-deploy-env-apollo: aws-banner
	@export AWS_STACK_NAME=$(APPLICATION_NAME)-$(ENVIRONMENT_NAME)-apollo 	 																		&& \
	 printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Deploying CloudFormation stack $${AWS_STACK_NAME}"		   																&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 aws cloudformation deploy \
	  --no-fail-on-empty-changeset \
    --template-file env-apollo.cf.yaml \
    --stack-name $${AWS_STACK_NAME} \
	  --parameter-overrides $$(jq -r '.[] | [.ParameterKey, .ParameterValue] | join("=")' params.json) \
	  --tags poweredby=prismatopia application=$(APPLICATION_NAME) environment=$(ENVIRONMENT_NAME)

# ===========================================================================
# Deploys all of the application level AWS resources in the proper order
# ===========================================================================
aws-deploy-app: aws-deploy-app-iam aws-deploy-app-network
	@echo
	@echo ======================================================================================
	@echo Finished deploying all application level AWS resources
	@echo ======================================================================================

# ===========================================================================
# Deploys all of the environment level AWS resources in the proper order
# ===========================================================================
aws-deploy-env: aws-deploy-env-dns aws-deploy-env-certificate aws-deploy-env-network aws-deploy-env-db aws-deploy-env-prisma aws-deploy-env-apollo
	@echo
	@echo ======================================================================================
	@echo Finished deploying all environment level AWS resources
	@echo ======================================================================================

# ===========================================================================
# Retrieves the Prisma secret for the AWS deployed Prisma management API
# ===========================================================================
PRISMA_MANAGEMENT_API_SECRET_ARN_EXPORT := mission-control-stage-PrismaManagementAPISecret
PRISMA_MANAGEMENT_API_SECRET_ARN := $$(aws cloudformation list-exports --query 'Exports[?Name==\`$(PRISMA_MANAGEMENT_API_SECRET_ARN_EXPORT)\`].Value' --output text)
PRISMA_MANAGEMENT_API_SECRET := $$(aws secretsmanager get-secret-value --secret-id $(PRISMA_MANAGEMENT_API_SECRET_ARN) --query 'SecretString' --output text)

aws-prisma-management-secret: aws-banner
	@echo PRISMA_MANAGEMENT_API_SECRET_ARN: $(PRISMA_MANAGEMENT_API_SECRET_ARN)
	@echo PRISMA_MANAGEMENT_API_SECRET: $(PRISMA_MANAGEMENT_API_SECRET)


# ===========================================================================
# Retrieves the Prisma secret for the AWS deployed service
# ===========================================================================
PRISMA_SERVICE_API_SECRET_ARN_EXPORT := mission-control-stage-PrismaServiceAPISecret
PRISMA_SERVICE_API_SECRET_ARN := $$(aws cloudformation list-exports --query 'Exports[?Name==`$(PRISMA_SERVICE_API_SECRET_ARN_EXPORT)`].Value' --output text)
PRISMA_SERVICE_API_SECRET := $$(aws secretsmanager get-secret-value --secret-id $(PRISMA_SERVICE_API_SECRET_ARN) --query 'SecretString' --output text)

aws-prisma-service-secret: aws-banner
	@echo PRISMA_SERVICE_API_SECRET_ARN: $(PRISMA_SERVICE_API_SECRET_ARN)
	@echo PRISMA_SERVICE_API_SECRET: $(PRISMA_SERVICE_API_SECRET)


# ===========================================================================
# Gets a token for connecting to the AWS Prisma API
# ===========================================================================
aws-prisma-token: aws-banner
	@cd prisma && \
	export PRISMA_MANAGEMENT_API_SECRET='$(PRISMA_MANAGEMENT_API_SECRET)' && \
	export PRISMA_SECRET='$(PRISMA_SERVICE_API_SECRET)' && \
	export PRISMA_ENDPOINT="https://prisma-stage.use-mission-control.com/" && \
	prisma token


# ===========================================================================
# Runs Prisma deploy against the AWS environment
# ===========================================================================
aws-prisma-deploy: aws-banner
	@cd prisma && \
	export PRISMA_MANAGEMENT_API_SECRET='$(PRISMA_MANAGEMENT_API_SECRET)' && \
	export PRISMA_SECRET='$(PRISMA_SERVICE_API_SECRET)' && \
	export PRISMA_ENDPOINT='https://prisma-stage.use-mission-control.com/' && \
	prisma deploy


# =================================================================
# Force an update of the Prisma service
# =================================================================
PRISMA_SERVICE_ARN_EXPORT := mission-control-stage-PrismaServiceArn
PRISMA_SERVICE_ARN := $$(aws cloudformation list-exports --query 'Exports[?Name==`$(PRISMA_SERVICE_ARN_EXPORT)`].Value' --output text)

aws-prisma-update-service: aws-banner
	@export PRISMA_SERVICE_ARN=$(PRISMA_SERVICE_ARN) && \
	echo PRISMA_SERVICE_ARN: $${PRISMA_SERVICE_ARN} && \
	aws ecs update-service --cluster mission-control-stage --service "$${PRISMA_SERVICE_ARN}" --force-new-deployment


# =================================================================
# Force an update of the Apollo service
# =================================================================
APOLLO_SERVICE_ARN_EXPORT := mission-control-stage-ApolloServiceArn
APOLLO_SERVICE_ARN := $$(aws cloudformation list-exports --query 'Exports[?Name==`$(APOLLO_SERVICE_ARN_EXPORT)`].Value' --output text)

aws-apollo-update-service: aws-banner
	@printf "$(OK_COLOR)"																																												&& \
	 printf "\n%s\n" "======================================================================================"		&& \
	 printf "%s\n"   "= Updating the Apollo service"													   																&& \
	 printf "%s"     "======================================================================================"		&& \
	 printf "$(NO_COLOR)"																																												&& \
	 cd aws 																																																		&& \
	 export APOLLO_SERVICE_ARN=$(APOLLO_SERVICE_ARN) && \
	 aws ecs update-service --cluster mission-control-stage --service "$${APOLLO_SERVICE_ARN}" --force-new-deployment

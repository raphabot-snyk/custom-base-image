#!/usr/bin/env bash

# Verifies if Docker, Snyk and curl are installed
if ! command -v docker &> /dev/null
then
    echo "Docker CLI could not be found"
    exit
fi
if ! command -v snyk &> /dev/null
then
    echo "Snyk CLI could not be found"
    exit
fi
if ! command -v curl &> /dev/null
then
    echo "Curl could not be found"
    exit
fi

# Asks users for their Snyk API Token
read -p "Enter your Snyk API Token: " SNYK_TOKEN

# Ask user for their Snyk org id
read -p "Enter your Snyk org id: " ORG_ID

# Ask user for their dockerhub username and alert that they need to be logged in to it in their docker cli
echo "You need to be logged in to your Dockerhub account in your Docker cli to push the image."
read -p "Enter your Dockerhub username: " DOCKERHUB_USERNAME

# Pull node:20-bookworm from Dockerhub, tag it as "$DOCKERHUB_USERNAME/node:1.0.0" and push it to Dockerhub
docker pull node:20-bookworm
docker tag node:20-bookworm $DOCKERHUB_USERNAME/node:1.0.0
docker push $DOCKERHUB_USERNAME/node:1.0.0

# Does the same for node:20-bookworm-slim, saving it as 1.0.1
docker pull node:20-bookworm-slim
docker tag node:20-bookworm-slim $DOCKERHUB_USERNAME/node:1.0.1
docker push $DOCKERHUB_USERNAME/node:1.0.1

# Replace "USERNAME" in "Dockerfile-app" with user's dockerhub username
sed -i '' "s/USERNAME/$DOCKERHUB_USERNAME/g" Dockerfile-app

# Builds the "app" container image and pushes it to Dockerhub
docker build -t $DOCKERHUB_USERNAME/node-app:1.0.0 -f ./Dockerfile-app .
docker push $DOCKERHUB_USERNAME/node-app:1.0.0

# Monitor the first base in Snyk
BASE_IMAGE_1_REQUEST=$(snyk container monitor $DOCKERHUB_USERNAME/node:1.0.0 --file=./Dockerfile-1.0.0 --project-name=custom-base-image-node:1.0.0 --org=$ORG_ID --json)

# Extracts the project uri from the response. Then, extracts the project id that lives after "project/" and after the next "/"
BASE_IMAGE_1_PROJECT_ID=$(echo $BASE_IMAGE_1_REQUEST | jq -r '.uri' | awk -F "project/" '{print $2}' | awk -F "/" '{print $1}')

# Enables the custom base image in Snyk
REQUEST_RESULT=$(curl --location 'https://api.snyk.io/rest/custom_base_images?version=2023-11-06' \
    --header 'Content-Type: application/vnd.api+json' \
    --header 'Accept: application/vnd.api+json' \
    --header "Authorization: token $SNYK_TOKEN" \
    --data "{
        \"data\": {
            \"type\": \"custom_base_image\",
            \"attributes\": {
            \"project_id\": \"$BASE_IMAGE_1_PROJECT_ID\",
            \"include_in_recommendations\": true,
            \"versioning_schema\": {
                \"type\": \"semver\"
            }
        }
    }")

# Monitor the second base in Snyk
BASE_IMAGE_2_REQUEST=$(snyk container monitor $DOCKERHUB_USERNAME/node:1.0.1 --file=./Dockerfile-1.0.1 --project-name=custom-base-image-node:1.0.1 --org=$ORG_ID --json)

# Extracts the project uri from the response. Then, extracts the project id that lives after "project/" and after the next "/"
BASE_IMAGE_2_PROJECT_ID=$(echo $BASE_IMAGE_2_REQUEST | jq -r '.uri' | awk -F "project/" '{print $2}' | awk -F "/" '{print $1}')

# Add the new version of the base image to the project
REQUEST_RESULT=$(curl --location 'https://api.snyk.io/rest/custom_base_images?version=2023-11-06' \
    --header 'Content-Type: application/vnd.api+json' \
    --header 'Accept: application/vnd.api+json' \
    --header "Authorization: token $SNYK_TOKEN" \
    --data "{
        \"data\": {
            \"type\": \"custom_base_image\",
            \"attributes\": {
            \"project_id\": \"$BASE_IMAGE_2_PROJECT_ID\",
            \"include_in_recommendations\": true
        }
    }")

# Monitor the application container image that uses the first custom base image
APP_IMAGE_REQUEST=$(snyk container monitor $DOCKERHUB_USERNAME/node-app:1.0.0 --file=./Dockerfile-app --project-name=node-app:1.0.0 --org=$ORG_ID --json)

echo "Access project at $(echo $APP_IMAGE_REQUEST | jq -r '.uri')"
#!/bin/bash
# V2VBot Docker Hub Deployment Script
set -e

# Configuration
DOCKER_USERNAME="algae514"
IMAGE_NAME="${IMAGE_NAME:-v2vbot}"
TAG="${TAG:-latest}"
FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${TAG}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo "=========================================="
echo "V2VBot Docker Hub Deployment"
echo "=========================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

print_success "Docker is running"

# Check if user is logged in to Docker Hub
if ! docker info | grep -q "Username:"; then
    print_warning "Not logged in to Docker Hub. Please log in:"
    echo "  docker login"
    echo ""
    read -p "Press Enter after logging in, or Ctrl+C to cancel..."
fi

# Check if Dockerfile exists
if [ ! -f "Dockerfile.dockerhub" ]; then
    print_error "Dockerfile.dockerhub not found!"
    exit 1
fi

print_success "Dockerfile found"

# Check if start script exists
if [ ! -f "start_docker.sh" ]; then
    print_error "start_docker.sh not found!"
    exit 1
fi

print_success "Start script found"

# Display build information
echo ""
print_info "Build Configuration:"
echo "  Docker Username: $DOCKER_USERNAME"
echo "  Image Name: $IMAGE_NAME"
echo "  Tag: $TAG"
echo "  Full Image: $FULL_IMAGE_NAME"
echo ""

# Ask for confirmation
read -p "Proceed with build and push? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Build cancelled"
    exit 0
fi

# Build the Docker image
print_info "Building Docker image..."
echo "This may take several minutes..."

if docker build -f Dockerfile.dockerhub -t "$FULL_IMAGE_NAME" .; then
    print_success "Docker image built successfully"
else
    print_error "Docker build failed"
    exit 1
fi

# Test the image locally (optional)
echo ""
read -p "Test the image locally before pushing? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Testing image locally..."
    print_warning "Starting container in background for testing..."
    
    # Start container in background
    CONTAINER_ID=$(docker run -d -p 8080:8080 -p 3478:3478 -p 5349:5349 -p 50000-50050:50000-50050/udp "$FULL_IMAGE_NAME")
    
    print_info "Container started with ID: $CONTAINER_ID"
    print_info "Waiting for container to start..."
    
    # Wait for container to be ready
    sleep 10
    
    # Check if container is running
    if docker ps | grep -q "$CONTAINER_ID"; then
        print_success "Container is running"
        print_info "You can test the application at: http://localhost:8080"
        print_info "TURN server running on ports 3478/5349"
        echo ""
        print_warning "Press Ctrl+C to stop testing and continue with push"
        echo "Or run: docker stop $CONTAINER_ID"
        
        # Wait for user input
        read -p "Press Enter to stop testing and continue..."
        
        # Stop the test container
        docker stop "$CONTAINER_ID" > /dev/null
        docker rm "$CONTAINER_ID" > /dev/null
        print_success "Test container stopped"
    else
        print_error "Container failed to start"
        docker logs "$CONTAINER_ID"
        docker rm "$CONTAINER_ID" > /dev/null
        exit 1
    fi
fi

# Push to Docker Hub
print_info "Pushing image to Docker Hub..."
echo "This may take several minutes..."

if docker push "$FULL_IMAGE_NAME"; then
    print_success "Image pushed to Docker Hub successfully!"
else
    print_error "Failed to push image to Docker Hub"
    exit 1
fi

# Display success information
echo ""
echo "=========================================="
print_success "Deployment Complete!"
echo "=========================================="
echo ""
print_info "Your image is now available at:"
echo "  Docker Hub: https://hub.docker.com/r/$DOCKER_USERNAME/$IMAGE_NAME"
echo "  Pull Command: docker pull $FULL_IMAGE_NAME"
echo ""
print_info "To run the container:"
echo "  docker run -d -p 8080:8080 -p 3478:3478 -p 5349:5349 -p 50000-50050:50000-50050/udp $FULL_IMAGE_NAME"
echo ""
print_info "To run with environment file:"
echo "  docker run -d -p 8080:8080 -p 3478:3478 -p 5349:5349 -p 50000-50050:50000-50050/udp -v \$(pwd)/.env:/home/appuser/.env $FULL_IMAGE_NAME"
echo ""
print_info "To run with GPU support:"
echo "  docker run --gpus all -d -p 8080:8080 -p 3478:3478 -p 5349:5349 -p 50000-50050:50000-50050/udp $FULL_IMAGE_NAME"
echo ""

# Create docker-compose.yml for easy deployment
print_info "Creating docker-compose.yml for easy deployment..."

cat > docker-compose.dockerhub.yml << EOF
version: '3.8'

services:
  v2vbot:
    image: $FULL_IMAGE_NAME
    container_name: v2vbot
    ports:
      - "8080:8080"      # Main application
      - "3478:3478"      # TURN server TCP
      - "3478:3478/udp"  # TURN server UDP
      - "5349:5349"      # TURNS server (TLS)
      - "50000-50050:50000-50050/udp"  # TURN relay ports
    volumes:
      - ./.env:/home/appuser/.env:ro
      - ./logs:/home/appuser/logs
      - ./models:/home/appuser/models
    environment:
      - USE_GPU=true
      - CUDA_VISIBLE_DEVICES=0
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # Uncomment for GPU support
  # v2vbot-gpu:
  #   image: $FULL_IMAGE_NAME
  #   container_name: v2vbot-gpu
  #   deploy:
  #     resources:
  #       reservations:
  #         devices:
  #           - driver: nvidia
  #             count: 1
  #             capabilities: [gpu]
  #   ports:
  #     - "8080:8080"
  #     - "3478:3478"
  #     - "3478:3478/udp"
  #     - "5349:5349"
  #     - "50000-50050:50000-50050/udp"
  #   volumes:
  #     - ./.env:/home/appuser/.env:ro
  #     - ./logs:/home/appuser/logs
  #     - ./models:/home/appuser/models
  #   environment:
  #     - USE_GPU=true
  #     - CUDA_VISIBLE_DEVICES=0
  #   restart: unless-stopped
EOF

print_success "docker-compose.dockerhub.yml created"
echo ""
print_info "To deploy with docker-compose:"
echo "  docker-compose -f docker-compose.dockerhub.yml up -d"
echo ""
print_info "To view logs:"
echo "  docker-compose -f docker-compose.dockerhub.yml logs -f"
echo ""
print_info "To stop:"
echo "  docker-compose -f docker-compose.dockerhub.yml down"
echo ""

print_success "V2VBot is now available on Docker Hub! 🚀"

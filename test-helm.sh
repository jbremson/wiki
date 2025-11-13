#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CHART_PATH="./wiki-chart"
RELEASE_NAME="wiki-test"
NAMESPACE="wiki-test"
IMAGE_NAME="wiki-service:test"

echo -e "${YELLOW}=== Helm Chart Test Script ===${NC}\n"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: Helm is not installed${NC}"
    echo "Install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi
echo -e "${GREEN}✓ Helm is installed: $(helm version --short)${NC}"

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
echo -e "${GREEN}✓ kubectl is installed: $(kubectl version --client --short 2>/dev/null)${NC}"

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    echo -e "${RED}Error: minikube is not installed${NC}"
    echo "Install minikube: brew install minikube"
    exit 1
fi
echo -e "${GREEN}✓ minikube is installed${NC}"

# Check if minikube is running, start if not
if ! minikube status &> /dev/null; then
    echo -e "${YELLOW}minikube is not running. Starting minikube...${NC}"
    minikube start --cpus=4 --memory=4096
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to start minikube${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ minikube started successfully${NC}"
else
    echo -e "${GREEN}✓ minikube is running${NC}"
fi

# Verify cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi
kubectl cluster-info | head -1
CLUSTER_AVAILABLE=true

echo ""

# Test 1: Helm Chart Lint
echo -e "${YELLOW}Test 1: Linting Helm chart...${NC}"
helm lint $CHART_PATH
test_result $?
echo ""

# Test 2: Validate Chart Structure
echo -e "${YELLOW}Test 2: Validating chart structure...${NC}"
if [ -f "$CHART_PATH/Chart.yaml" ] && [ -f "$CHART_PATH/values.yaml" ] && [ -d "$CHART_PATH/templates" ]; then
    echo "Chart.yaml: ✓"
    echo "values.yaml: ✓"
    echo "templates/: ✓"
    test_result 0
else
    echo "Missing required chart files"
    test_result 1
fi
echo ""

# Test 3: Template Rendering (Dry Run)
echo -e "${YELLOW}Test 3: Testing template rendering (dry-run)...${NC}"
helm template $RELEASE_NAME $CHART_PATH > /tmp/helm-template-output.yaml 2>&1
if [ $? -eq 0 ]; then
    echo "Generated $(wc -l < /tmp/helm-template-output.yaml) lines of Kubernetes manifests"
    test_result 0
else
    cat /tmp/helm-template-output.yaml
    test_result 1
fi
echo ""

# Test 4: Validate Generated Manifests
echo -e "${YELLOW}Test 4: Validating generated Kubernetes manifests...${NC}"
if [ "$CLUSTER_AVAILABLE" = true ]; then
    kubectl apply --dry-run=client -f /tmp/helm-template-output.yaml > /dev/null 2>&1
    test_result $?
else
    echo "Skipping (no cluster available)"
fi
echo ""

# Test 5: Check for required resources in templates
echo -e "${YELLOW}Test 5: Checking for required Kubernetes resources...${NC}"
REQUIRED_RESOURCES=("Deployment" "Service" "ConfigMap")
ALL_FOUND=true
for resource in "${REQUIRED_RESOURCES[@]}"; do
    if grep -q "kind: $resource" /tmp/helm-template-output.yaml; then
        echo "  ✓ $resource found"
    else
        echo "  ✗ $resource not found"
        ALL_FOUND=false
    fi
done
if [ "$ALL_FOUND" = true ]; then
    test_result 0
else
    test_result 1
fi
echo ""

if [ "$CLUSTER_AVAILABLE" = false ]; then
    echo -e "${YELLOW}=== Cluster Tests Skipped ===${NC}"
    echo "Start a Kubernetes cluster to run deployment tests"
    echo ""
    # Jump to summary
else
    # Cluster is available, continue with deployment tests

    # Test 6: Build Docker image for the chart
    echo -e "${YELLOW}Test 6: Building Docker image for deployment...${NC}"
    cd wiki-service
    docker build -t $IMAGE_NAME . > /dev/null 2>&1
    BUILD_RESULT=$?
    cd ..
    if [ $BUILD_RESULT -eq 0 ]; then
        echo "Image built: $IMAGE_NAME"
        test_result 0
    else
        echo "Failed to build image"
        test_result 1
    fi
    echo ""

    # Load image into minikube
    echo -e "${BLUE}Loading image into minikube...${NC}"
    minikube image load $IMAGE_NAME
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Image loaded into minikube${NC}"
    else
        echo -e "${RED}✗ Failed to load image${NC}"
    fi
    echo ""

    # Test 7: Create namespace
    echo -e "${YELLOW}Test 7: Creating namespace...${NC}"
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
    test_result $?
    echo ""

    # Test 8: Install Helm chart
    echo -e "${YELLOW}Test 8: Installing Helm chart...${NC}"
    helm upgrade --install $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --set fastapi.image_name=$IMAGE_NAME \
        --wait --timeout 3m 2>&1 | tee /tmp/helm-install.log

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        test_result 0
    else
        test_result 1
        echo "Install logs saved to /tmp/helm-install.log"
    fi
    echo ""

    # Test 9: Verify all pods are running
    echo -e "${YELLOW}Test 9: Verifying pods are running...${NC}"
    sleep 10
    kubectl get pods -n $NAMESPACE

    NOT_RUNNING=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
    if [ $NOT_RUNNING -eq 0 ]; then
        test_result 0
    else
        echo "$NOT_RUNNING pod(s) not running"
        test_result 1
    fi
    echo ""

    # Test 10: Check services
    echo -e "${YELLOW}Test 10: Checking services are created...${NC}"
    kubectl get services -n $NAMESPACE
    SVC_COUNT=$(kubectl get services -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
    if [ $SVC_COUNT -gt 0 ]; then
        echo "Found $SVC_COUNT service(s)"
        test_result 0
    else
        test_result 1
    fi
    echo ""

    # Test 11: Test API endpoint (if possible)
    echo -e "${YELLOW}Test 11: Testing API endpoint...${NC}"

    # Try to port-forward to the FastAPI service
    kubectl port-forward -n $NAMESPACE svc/fastapi-service 8000:8000 > /dev/null 2>&1 &
    PF_PID=$!
    sleep 3

    # Test the health endpoint
    HEALTH_RESPONSE=$(curl -s http://localhost:8000/health 2>/dev/null)
    if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
        echo "API Response: $HEALTH_RESPONSE"
        test_result 0
    else
        echo "Could not reach API or invalid response"
        test_result 1
    fi

    # Cleanup port-forward
    kill $PF_PID 2>/dev/null
    wait $PF_PID 2>/dev/null
    echo ""

    # Show Helm release info
    echo -e "${BLUE}Helm Release Information:${NC}"
    helm list -n $NAMESPACE
    echo ""

    # Get service URLs
    echo -e "${GREEN}=== Service URLs ===${NC}"
    echo -e "${BLUE}Getting service URLs from minikube...${NC}"

    # Get minikube IP
    MINIKUBE_IP=$(minikube ip)

    # Get NodePorts for services
    FASTAPI_NODEPORT=$(kubectl get svc fastapi-service -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')

    if [ -n "$FASTAPI_NODEPORT" ]; then
        FASTAPI_URL="http://${MINIKUBE_IP}:${FASTAPI_NODEPORT}"
        echo -e "${GREEN}FastAPI Service:${NC} $FASTAPI_URL"
        echo -e "${GREEN}Available endpoints:${NC}"
        echo "  - Root:    $FASTAPI_URL/"
        echo "  - Health:  $FASTAPI_URL/health"
        echo "  - Users:   $FASTAPI_URL/users/"
        echo "  - Posts:   $FASTAPI_URL/posts/"
        echo "  - Metrics: $FASTAPI_URL/metrics"
    fi

    # Check if Grafana service exists
    if kubectl get svc grafana-service -n $NAMESPACE &> /dev/null; then
        GRAFANA_NODEPORT=$(kubectl get svc grafana-service -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
        if [ -n "$GRAFANA_NODEPORT" ]; then
            echo -e "${GREEN}Grafana:${NC} http://${MINIKUBE_IP}:${GRAFANA_NODEPORT} (admin/admin)"
        fi
    fi

    # Check if Prometheus service exists
    if kubectl get svc prometheus-service -n $NAMESPACE &> /dev/null; then
        PROMETHEUS_NODEPORT=$(kubectl get svc prometheus-service -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
        if [ -n "$PROMETHEUS_NODEPORT" ]; then
            echo -e "${GREEN}Prometheus:${NC} http://${MINIKUBE_IP}:${PROMETHEUS_NODEPORT}"
        fi
    fi
    echo ""

    # Offer to start port-forwards
    echo -e "${BLUE}=== Port Forwarding (Alternative Access) ===${NC}"
    echo -e "${YELLOW}Note: minikube tunnel requires sudo for ports 80/443${NC}"
    read -p "Start port-forwards to localhost instead? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Starting port-forwards...${NC}"
        echo "FastAPI will be available at: http://localhost:8000"

        # Start port-forwards in background
        kubectl port-forward -n $NAMESPACE svc/fastapi-service 8000:8000 > /dev/null 2>&1 &
        PF1=$!

        if kubectl get svc grafana-service -n $NAMESPACE &> /dev/null; then
            echo "Grafana will be available at: http://localhost:3000"
            kubectl port-forward -n $NAMESPACE svc/grafana-service 3000:3000 > /dev/null 2>&1 &
            PF2=$!
        fi

        if kubectl get svc prometheus-service -n $NAMESPACE &> /dev/null; then
            echo "Prometheus will be available at: http://localhost:9090"
            kubectl port-forward -n $NAMESPACE svc/prometheus-service 9090:9090 > /dev/null 2>&1 &
            PF3=$!
        fi

        echo ""
        echo -e "${GREEN}Port-forwards running! Press Ctrl+C to stop them.${NC}"
        echo "To stop port-forwards later, run: pkill -f 'port-forward.*$NAMESPACE'"
        echo ""

        # Wait for user interrupt
        trap "echo 'Stopping port-forwards...'; kill $PF1 $PF2 $PF3 2>/dev/null; exit" INT
        wait
    fi

    # Cleanup prompt
    echo -e "${YELLOW}=== Cleanup ===${NC}"
    read -p "Do you want to uninstall the Helm release? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstalling Helm release..."
        helm uninstall $RELEASE_NAME -n $NAMESPACE
        echo "Deleting namespace..."
        kubectl delete namespace $NAMESPACE
        echo -e "${GREEN}Cleanup complete${NC}"
    else
        echo -e "${BLUE}Keeping deployment. To cleanup later, run:${NC}"
        echo "  helm uninstall $RELEASE_NAME -n $NAMESPACE"
        echo "  kubectl delete namespace $NAMESPACE"
    fi
    echo ""
fi

# Summary
echo -e "${YELLOW}=== Test Summary ===${NC}"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed! ✗${NC}"
    exit 1
fi

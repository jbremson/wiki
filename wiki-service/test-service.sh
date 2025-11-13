#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
POSTGRES_CONTAINER="wiki-test-postgres"
SERVICE_CONTAINER="wiki-test-service"
NETWORK="wiki-test-network"
SERVICE_PORT=8000

echo -e "${YELLOW}=== Wiki Service Test Script ===${NC}\n"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    docker stop $SERVICE_CONTAINER 2>/dev/null
    docker rm $SERVICE_CONTAINER 2>/dev/null
    docker stop $POSTGRES_CONTAINER 2>/dev/null
    docker rm $POSTGRES_CONTAINER 2>/dev/null
    docker network rm $NETWORK 2>/dev/null
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Clean up any existing containers
echo -e "${YELLOW}Cleaning up existing containers...${NC}"
docker stop $SERVICE_CONTAINER $POSTGRES_CONTAINER 2>/dev/null
docker rm $SERVICE_CONTAINER $POSTGRES_CONTAINER 2>/dev/null
docker network rm $NETWORK 2>/dev/null

# Create network
echo -e "\n${YELLOW}Creating Docker network...${NC}"
docker network create $NETWORK

# Start PostgreSQL
echo -e "\n${YELLOW}Starting PostgreSQL container...${NC}"
docker run -d \
    --name $POSTGRES_CONTAINER \
    --network $NETWORK \
    -e POSTGRES_USER=admin \
    -e POSTGRES_PASSWORD=admin \
    -e POSTGRES_DB=wikidb \
    postgres:15-alpine

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
sleep 5
for i in {1..30}; do
    if docker exec $POSTGRES_CONTAINER pg_isready -U admin > /dev/null 2>&1; then
        echo -e "${GREEN}PostgreSQL is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Build the service image
echo -e "\n${YELLOW}Building wiki-service image...${NC}"
docker build -t wiki-service:test .

# Start the service
echo -e "\n${YELLOW}Starting wiki-service container...${NC}"
docker run -d \
    --name $SERVICE_CONTAINER \
    --network $NETWORK \
    -p $SERVICE_PORT:8000 \
    -e DATABASE_URL="postgresql+asyncpg://admin:admin@$POSTGRES_CONTAINER:5432/wikidb" \
    wiki-service:test

# Wait for service to be ready
echo -e "${YELLOW}Waiting for wiki-service to be ready...${NC}"
sleep 3
for i in {1..30}; do
    if curl -s http://localhost:$SERVICE_PORT/health > /dev/null 2>&1; then
        echo -e "${GREEN}Wiki-service is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

echo -e "\n${YELLOW}=== Running API Tests ===${NC}\n"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to generate short UUID
generate_short_uuid() {
    head -c 16 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8
}

# Helper function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local expected_status=$4
    local description=$5

    echo -e "${YELLOW}Testing: $description${NC}"

    if [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X $method \
            -H "Content-Type: application/json" \
            -d "$data" \
            "http://localhost:$SERVICE_PORT$endpoint")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method \
            "http://localhost:$SERVICE_PORT$endpoint")
    fi

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASSED${NC} (Status: $http_code)"
        echo "Response: $body"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC} (Expected: $expected_status, Got: $http_code)"
        echo "Response: $body"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: Root endpoint
test_endpoint "GET" "/" "" "200" "Root endpoint"
echo ""

# Test 2: Health check
test_endpoint "GET" "/health" "" "200" "Health check"
echo ""

# Test 3: List all existing users
echo -e "${YELLOW}Test 3: Listing all existing users...${NC}"
USERS_RESPONSE=$(curl -s http://localhost:$SERVICE_PORT/users/)
echo -e "${GREEN}Existing users:${NC}"
echo "$USERS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$USERS_RESPONSE"
echo ""

# Test 4: Create user
UUID=$(generate_short_uuid)
USER_RESPONSE=$(test_endpoint "POST" "/users/" "{\"username\":\"testuser_${UUID}\",\"email\":\"test_${UUID}@example.com\"}" "200" "Create user")
USER_ID=$(echo "$USER_RESPONSE" | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)
echo ""

# Test 5: Get user by ID
if [ -n "$USER_ID" ]; then
    test_endpoint "GET" "/users/$USER_ID" "" "200" "Get user by ID"
    echo ""
fi

# Test 6: List users
test_endpoint "GET" "/users/" "" "200" "List users"
echo ""

# Test 7: Create post
if [ -n "$USER_ID" ]; then
    POST_RESPONSE=$(test_endpoint "POST" "/posts/" "{\"title\":\"Test Post\",\"content\":\"This is a test post\",\"author_id\":$USER_ID}" "200" "Create post")
    POST_ID=$(echo "$POST_RESPONSE" | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)
    echo ""
fi

# Test 8: Get post by ID
if [ -n "$POST_ID" ]; then
    test_endpoint "GET" "/posts/$POST_ID" "" "200" "Get post by ID"
    echo ""
fi

# Test 9: List posts
test_endpoint "GET" "/posts/" "" "200" "List posts"
echo ""

# Test 10: Metrics endpoint
test_endpoint "GET" "/metrics" "" "200" "Metrics endpoint"
echo ""

# Test 11: Non-existent user (should return 404)
test_endpoint "GET" "/users/99999" "" "404" "Non-existent user (404 expected)"
echo ""

# Test 12: Async concurrency test - create multiple users simultaneously
echo -e "${YELLOW}Test 12: Async concurrency test - creating 5 users in parallel...${NC}"
START_TIME=$(date +%s%N)

# Create 5 users in parallel using background processes
PIDS=()
for i in {1..5}; do
    UUID=$(generate_short_uuid)
    (curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"concurrent_user_${UUID}\",\"email\":\"concurrent_${UUID}@example.com\"}" \
        "http://localhost:$SERVICE_PORT/users/" > /tmp/user_response_$i.json) &
    PIDS+=($!)
done

# Wait for all background processes to complete
for pid in "${PIDS[@]}"; do
    wait $pid
done

END_TIME=$(date +%s%N)
DURATION=$(( (END_TIME - START_TIME) / 1000000 ))

# Check results
SUCCESS_COUNT=0
for i in {1..5}; do
    if grep -q '"id"' /tmp/user_response_$i.json 2>/dev/null; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
    rm -f /tmp/user_response_$i.json
done

if [ $SUCCESS_COUNT -eq 5 ]; then
    echo -e "${GREEN}✓ PASSED${NC} - Created 5 users concurrently in ${DURATION}ms"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAILED${NC} - Only created $SUCCESS_COUNT out of 5 users"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify total user count
TOTAL_USERS=$(curl -s "http://localhost:$SERVICE_PORT/users/?limit=100" | grep -o '"id"' | wc -l | tr -d ' ')
echo "Total users in database: $TOTAL_USERS"
echo ""

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

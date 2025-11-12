# Wiki Service Helm Chart

This Helm chart deploys a complete Wikipedia-like API service with the following components:

## Components

1. **FastAPI Service**: Business logic layer with REST API endpoints
2. **PostgreSQL**: Database for storing users and posts
3. **Prometheus**: Metrics collection from FastAPI `/metrics` endpoint
4. **Grafana**: Visualization dashboard for user and post creation rates

## Architecture

- FastAPI exposes endpoints: `/users/*` and `/posts/*`
- Prometheus scrapes metrics from FastAPI `/metrics` endpoint
- Grafana displays dashboards at `/d/creation-dashboard-678/creation`
- All components are orchestrated via Kubernetes/Helm

## Prerequisites

- Kubernetes cluster (requires at most 2 CPUs, 4GB RAM, 5GB disk)
- Helm 3.x installed
- Docker (for building the FastAPI image)

## Building the FastAPI Docker Image

```bash
cd wiki-service
docker build -t fastapi-wiki-service:latest .
```

## Installing the Helm Chart

```bash
helm install wiki-release ./wiki-chart
```

## Customizing the Installation

You can customize the installation by modifying `values.yaml` or using `--set` flags:

```bash
helm install wiki-release ./wiki-chart --set fastapi.image_name=my-custom-image:tag
```

## Accessing the Services

After installation, the services are exposed through the Ingress controller:

- **FastAPI**: `http://wiki-service.local/users/*` and `http://wiki-service.local/posts/*`
- **Grafana Dashboard**: `http://wiki-service.local/grafana/d/creation-dashboard-678/creation`
  - Default credentials: admin/admin

## Metrics

The following Prometheus metrics are exposed:

- `users_created_total`: Total number of users created
- `posts_created_total`: Total number of posts created

## Testing the API

Create a user:
```bash
curl -X POST http://wiki-service.local/users/ \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "email": "test@example.com"}'
```

Create a post:
```bash
curl -X POST http://wiki-service.local/posts/ \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Post", "content": "This is a test", "author_id": 1}'
```

## Uninstalling

```bash
helm uninstall wiki-release
```

## Resource Requirements

The entire Kubernetes cluster requires:
- CPU: 2 cores maximum
- Memory: 4GB maximum
- Storage: 5GB maximum

## Directory Structure

```
/
├── wiki-service/
│   ├── Dockerfile
│   ├── main.py
│   ├── requirements.txt
│   └── ...
└── wiki-chart/
    ├── Chart.yaml
    ├── values.yaml
    ├── .helmignore
    └── templates/
        ├── fastapi-deployment.yaml
        ├── fastapi-service.yaml
        ├── postgres-deployment.yaml
        ├── postgres-service.yaml
        ├── postgres-pvc.yaml
        ├── prometheus-deployment.yaml
        ├── prometheus-service.yaml
        ├── prometheus-configmap.yaml
        ├── grafana-deployment.yaml
        ├── grafana-service.yaml
        ├── grafana-configmap.yaml
        └── ingress.yaml
```

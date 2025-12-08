# ClimbIt Development Guide

A rock climbing companion app that helps climbers find safe crags based on recent precipitation data.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Repository Structure](#repository-structure)
4. [Backend API](#backend-api)
5. [Infrastructure (Terraform)](#infrastructure-terraform)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [iOS App](#ios-app)
8. [Local Development Setup](#local-development-setup)
9. [Deployment](#deployment)

---

## Project Overview

**ClimbIt** helps rock climbers determine if a crag is safe to climb based on recent weather conditions. Wet rock is dangerous—this app warns climbers when precipitation has made conditions unsafe.

### Core Features

- **Crag Discovery**: Search and browse climbing areas sourced from Mountain Project
- **Safety Status**: Real-time safety ratings (Safe/Caution/Unsafe) based on precipitation
- **Saved Crags**: Track your favorite climbing spots
- **Navigation**: Direct links to Google Maps, Apple Maps, and Mountain Project

### Data Flow

```
Mountain Project ──[Crawler]──> AWS RDS MySQL ──[API]──> iOS App
                                      ↑
                            Weather API ──[Scheduled Job]
```

---

## Architecture

### Current State (POC)

```
┌─────────────────┐     HTTP (hardcoded IP)     ┌─────────────────┐
│   iOS App       │ ──────────────────────────> │  EC2 (manual)   │
│   (SwiftUI)     │                             │  Port 8000      │
└─────────────────┘                             └────────┬────────┘
                                                         │
                                                         ▼
┌─────────────────┐                             ┌─────────────────┐
│  Crawler        │ ───────────────────────────>│  RDS MySQL      │
│  (Selenium)     │      Direct connection      │  (manual)       │
└─────────────────┘                             └─────────────────┘
```

**Issues:**
- Hardcoded IP address in iOS app
- No HTTPS/TLS
- Credentials in `.env` file
- No CI/CD
- No Infrastructure as Code
- API server code missing from repo

### Target State (Production)

```
┌─────────────────┐         HTTPS          ┌──────────────────────┐
│   iOS App       │ ─────────────────────> │  API Gateway         │
│   (SwiftUI)     │                        │  (api.climbit.app)   │
└─────────────────┘                        └──────────┬───────────┘
                                                      │
                                                      ▼
                                           ┌──────────────────────┐
                                           │  ECS Fargate         │
                                           │  (FastAPI container) │
                                           └──────────┬───────────┘
                                                      │
                    ┌─────────────────────────────────┼─────────────────┐
                    │                                 │                 │
                    ▼                                 ▼                 ▼
          ┌─────────────────┐              ┌─────────────────┐  ┌──────────────┐
          │  RDS MySQL      │              │  Secrets Manager│  │  CloudWatch  │
          │  (Multi-AZ)     │              │                 │  │  (Logs)      │
          └─────────────────┘              └─────────────────┘  └──────────────┘

┌─────────────────┐    Scheduled (EventBridge)    ┌──────────────────────┐
│  Weather Updater│ <──────────────────────────── │  Lambda / ECS Task   │
│  (precipitation)│                               │  (daily job)         │
└─────────────────┘                               └──────────────────────┘
```

---

## Repository Structure

```
climb-it/
├── DEVELOPMENT.md              # This file
├── .github/
│   └── workflows/
│       ├── api-ci.yml          # Backend CI/CD
│       └── crawler-ci.yml      # Crawler CI
│
├── api/                        # NEW: FastAPI backend
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py                 # FastAPI app entry
│   ├── routers/
│   │   └── crags.py            # /crags endpoints
│   ├── models/
│   │   └── crag.py             # Pydantic models
│   ├── db/
│   │   ├── database.py         # SQLAlchemy setup
│   │   └── models.py           # ORM models
│   └── tests/
│       └── test_crags.py
│
├── crawler/                    # Renamed from cllimb-it
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── crawler.py
│   ├── models.py
│   ├── models_ods.py
│   ├── db_writer.py
│   ├── page_parser.py
│   └── alembic/
│
├── terraform/                  # NEW: Infrastructure as Code
│   ├── environments/
│   │   ├── prod/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── terraform.tfvars
│   │   └── dev/
│   │       └── ...
│   └── modules/
│       ├── vpc/
│       ├── rds/
│       ├── ecs/
│       ├── api-gateway/
│       └── secrets/
│
└── Climbate/                   # iOS App (existing)
    ├── Climbate.xcodeproj/
    └── Climbate/
        ├── ClimbateApp.swift
        ├── Models/
        │   └── Crag.swift
        ├── Views/
        │   ├── ContentView.swift
        │   ├── HomeView.swift
        │   ├── SearchView.swift
        │   ├── CragDetailView.swift
        │   └── AlternateAdventureView.swift
        ├── Services/
        │   ├── APIClient.swift
        │   └── Configuration.swift
        └── Resources/
            └── Info.plist
```

---

## Backend API

### Technology Stack

- **Framework**: FastAPI (Python 3.11)
- **ORM**: SQLAlchemy 2.0
- **Database**: MySQL 8.0 (AWS RDS)
- **Containerization**: Docker
- **Deployment**: AWS ECS Fargate

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/crags` | List all crags (paginated) |
| GET | `/crags/{id}` | Get single crag with precipitation data |
| GET | `/crags/search?q={query}` | Search crags by name/location |
| GET | `/crags/nearby?lat={lat}&lon={lon}&radius={km}` | Find nearby crags |

### Response Models

```python
# Crag list response
{
    "id": "uuid",
    "name": "Yosemite Valley",
    "location": "California > Yosemite",
    "latitude": 37.7456,
    "longitude": -119.5936,
    "safety_status": "SAFE",  # SAFE | CAUTION | UNSAFE
    "google_maps_url": "https://...",
    "mountain_project_url": "https://..."
}

# Crag detail response (includes precipitation)
{
    ...crag_fields,
    "precipitation": {
        "last_7_days_mm": 0.0,
        "last_rain_date": "2025-02-28",
        "days_since_rain": 7
    }
}
```

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | MySQL connection string | `mysql+pymysql://user:pass@host/db` |
| `ENVIRONMENT` | Runtime environment | `production` |
| `LOG_LEVEL` | Logging verbosity | `INFO` |
| `CORS_ORIGINS` | Allowed origins | `*` (dev) or specific domains |

---

## Infrastructure (Terraform)

### AWS Resources

| Resource | Purpose |
|----------|---------|
| **VPC** | Isolated network with public/private subnets |
| **RDS MySQL** | Database (existing, import into Terraform state) |
| **ECS Cluster** | Container orchestration |
| **ECS Service** | FastAPI container (Fargate) |
| **ECR** | Docker image registry |
| **API Gateway** | HTTPS endpoint with custom domain |
| **Secrets Manager** | Database credentials |
| **CloudWatch** | Logs and monitoring |
| **EventBridge** | Scheduled jobs (weather updates) |

### Module Structure

```hcl
# terraform/environments/prod/main.tf

module "vpc" {
  source = "../../modules/vpc"
  environment = "prod"
  cidr_block  = "10.0.0.0/16"
}

module "rds" {
  source = "../../modules/rds"
  # Import existing RDS instance
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  instance_class    = "db.t3.micro"
  allocated_storage = 20
}

module "ecs" {
  source = "../../modules/ecs"
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.vpc.ecs_security_group_id
  db_secret_arn     = module.secrets.db_secret_arn
}

module "api_gateway" {
  source = "../../modules/api-gateway"
  ecs_alb_dns = module.ecs.alb_dns_name
  domain_name = "api.climbit.app"  # Optional custom domain
}
```

### State Management

```hcl
# terraform/environments/prod/backend.tf
terraform {
  backend "s3" {
    bucket         = "climbit-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "climbit-terraform-locks"
    encrypt        = true
  }
}
```

---

## CI/CD Pipeline

### GitHub Actions Workflows

#### Backend API (`api-ci.yml`)

```yaml
name: API CI/CD

on:
  push:
    branches: [main]
    paths: ['api/**']
  pull_request:
    branches: [main]
    paths: ['api/**']

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install -r api/requirements.txt
      - run: pytest api/tests/

  build-and-deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - uses: aws-actions/amazon-ecr-login@v2
      - run: |
          docker build -t climbit-api api/
          docker tag climbit-api:latest ${{ secrets.ECR_REGISTRY }}/climbit-api:latest
          docker push ${{ secrets.ECR_REGISTRY }}/climbit-api:latest
      - run: |
          aws ecs update-service --cluster climbit --service climbit-api --force-new-deployment
```

#### Terraform (`terraform-ci.yml`)

```yaml
name: Terraform

on:
  push:
    branches: [main]
    paths: ['terraform/**']
  pull_request:
    paths: ['terraform/**']

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
        working-directory: terraform/environments/prod
      - run: terraform plan -out=tfplan
        working-directory: terraform/environments/prod

  apply:
    needs: plan
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init && terraform apply -auto-approve
        working-directory: terraform/environments/prod
```

---

## iOS App

### Current Issues & Fixes

| Issue | Current | Fix |
|-------|---------|-----|
| Hardcoded API URL | `http://18.205.113.228:8000` | Environment-based configuration |
| Hardcoded coordinates | SF placeholder | Use crag's actual lat/lon |
| Hardcoded weather | `68°F, 10%` | Fetch from API |
| Missing fields | No lat/lon/url in model | Expand Crag model |
| Insecure HTTP | `NSAllowsArbitraryLoads` | Use HTTPS only |
| No persistence | In-memory only | UserDefaults or SwiftData |

### Updated Data Model

```swift
// Crag.swift
struct Crag: Identifiable, Codable {
    let id: UUID
    let name: String
    let location: String
    let latitude: Double
    let longitude: Double
    let safetyStatus: SafetyStatus
    let googleMapsUrl: String?
    let mountainProjectUrl: String?
    let precipitation: PrecipitationData?

    enum SafetyStatus: String, Codable {
        case safe = "SAFE"
        case caution = "CAUTION"
        case unsafe = "UNSAFE"
    }

    struct PrecipitationData: Codable {
        let last7DaysMm: Double
        let lastRainDate: String?
        let daysSinceRain: Int?
    }

    // Computed property for display
    var locationDisplay: String {
        // Parse location_hierarchy_json into readable string
        location
    }
}
```

### API Client

```swift
// Services/APIClient.swift
import Foundation

class APIClient {
    static let shared = APIClient()

    private let baseURL: URL

    private init() {
        #if DEBUG
        baseURL = URL(string: "http://localhost:8000")!
        #else
        baseURL = URL(string: "https://api.climbit.app")!
        #endif
    }

    func fetchCrags() async throws -> [Crag] {
        let url = baseURL.appendingPathComponent("crags")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Crag].self, from: data)
    }

    func searchCrags(query: String) async throws -> [Crag] {
        var components = URLComponents(url: baseURL.appendingPathComponent("crags/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Crag].self, from: data)
    }
}

enum APIError: Error {
    case invalidResponse
    case networkError(Error)
}
```

### Persistence

```swift
// Services/CragStore.swift
import Foundation

class CragStore: ObservableObject {
    @Published var savedCrags: [Crag] = []

    private let userDefaultsKey = "savedCrags"

    init() {
        load()
    }

    func save(_ crag: Crag) {
        guard !savedCrags.contains(where: { $0.id == crag.id }) else { return }
        savedCrags.append(crag)
        persist()
    }

    func remove(_ crag: Crag) {
        savedCrags.removeAll { $0.id == crag.id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let crags = try? JSONDecoder().decode([Crag].self, from: data) else { return }
        savedCrags = crags
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedCrags) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
```

### App Structure with StateObject

```swift
// ClimbateApp.swift
import SwiftUI

@main
struct ClimbateApp: App {
    @StateObject private var cragStore = CragStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cragStore)
        }
    }
}
```

---

## Local Development Setup

### Prerequisites

- Python 3.11+
- Docker & Docker Compose
- Xcode 15+ (for iOS development)
- Terraform 1.5+
- AWS CLI configured

### Backend Setup

```bash
# 1. Clone and setup
cd climb-it

# 2. Create Python virtual environment
cd api
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 3. Set environment variables
export DATABASE_URL="mysql+pymysql://user:pass@localhost:3306/climbate"
export ENVIRONMENT="development"

# 4. Run locally
uvicorn main:app --reload --port 8000
```

### Docker Compose (Full Stack)

```yaml
# docker-compose.yml
version: '3.8'

services:
  api:
    build: ./api
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=mysql+pymysql://climbate:localpass@db:3306/climbate
      - ENVIRONMENT=development
    depends_on:
      - db

  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: climbate
      MYSQL_USER: climbate
      MYSQL_PASSWORD: localpass
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql

volumes:
  mysql_data:
```

```bash
# Run full stack locally
docker-compose up -d

# Run migrations
docker-compose exec api alembic upgrade head
```

### iOS Setup

```bash
# Open in Xcode
open Climbate/Climbate.xcodeproj

# For local development, the app will connect to localhost:8000
# Build and run on simulator (Cmd+R)
```

---

## Deployment

### Initial Setup (One-time)

```bash
# 1. Create Terraform state bucket
aws s3 mb s3://climbit-terraform-state --region us-east-1

# 2. Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name climbate-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# 3. Initialize Terraform
cd terraform/environments/prod
terraform init

# 4. Import existing RDS (if applicable)
terraform import module.rds.aws_db_instance.main climbit-production-database

# 5. Plan and apply
terraform plan
terraform apply
```

### Deploying Updates

```bash
# Backend API - push to main triggers deployment
git push origin main

# Manual deployment
cd api
docker build -t climbit-api .
docker tag climbit-api:latest <ECR_URI>/climbit-api:latest
docker push <ECR_URI>/climbit-api:latest
aws ecs update-service --cluster climbit --service climbit-api --force-new-deployment
```

### iOS App Store Deployment

1. Update version in Xcode (General > Version)
2. Archive: Product > Archive
3. Distribute via App Store Connect
4. Submit for review

---

## Security Considerations

### Secrets Management

- **Never commit secrets** to git (`.env`, credentials, API keys)
- Use AWS Secrets Manager for production secrets
- Use GitHub Secrets for CI/CD credentials

### Network Security

- RDS in private subnet (no public access)
- ECS tasks in private subnet with NAT gateway
- API Gateway as the only public entry point
- HTTPS only (no HTTP)

### iOS App Transport Security

```xml
<!-- Info.plist - Production (remove NSAllowsArbitraryLoads) -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

---

## Roadmap

### Phase 1: Foundation (Current)
- [x] Database schema
- [x] Mountain Project crawler
- [x] Basic iOS UI
- [ ] FastAPI backend
- [ ] Terraform infrastructure
- [ ] CI/CD pipelines

### Phase 2: Core Features
- [ ] Precipitation data integration (weather API)
- [ ] Safety status calculation logic
- [ ] Real weather display in iOS app
- [ ] Crag search with filters
- [ ] Nearby crags feature

### Phase 3: Polish
- [ ] Push notifications for weather alerts
- [ ] Offline mode (cached crags)
- [ ] User accounts (optional)
- [ ] Alternate Adventure recommendations
- [ ] App Store submission

---

## Contributing

1. Create a feature branch: `git checkout -b feature/my-feature`
2. Make changes and test locally
3. Submit a pull request
4. Wait for CI checks to pass
5. Request review

## Support

For questions or issues, open a GitHub issue or contact the maintainers.

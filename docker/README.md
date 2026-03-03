# DevFlow Docker Services

Runs **Hindsight** (memory) and **Langfuse** (observability) locally.

## Setup

```bash
cp .env.example .env
# Edit .env and add your ANTHROPIC_API_KEY
```

## Commands

```bash
# Start all services
docker compose up -d

# Check status
docker compose ps

# View logs (all services)
docker compose logs -f

# View logs (single service)
docker compose logs -f hindsight
docker compose logs -f langfuse-web

# Stop services
docker compose down

# Reset all data (destroys volumes)
docker compose down -v
```

## Service URLs

| Service       | URL                   | Purpose          |
| ------------- | --------------------- | ---------------- |
| Hindsight API | http://localhost:8888 | Memory API       |
| Hindsight UI  | http://localhost:9999 | Memory dashboard |
| Langfuse UI   | http://localhost:3100 | Observability    |

## First-time Langfuse setup

1. Open http://localhost:3100 and create an account
2. Create a new project and copy the API keys
3. Add `LANGFUSE_SECRET_KEY` and `LANGFUSE_PUBLIC_KEY` to your `.env`

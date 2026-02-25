# Part 1: Test Audit (20-30 minutes)

## Context

You're the first QA hire at Gumloop, an AI-powered workflow automation platform. Our backend is Python/Flask, frontend is TypeScript/Next.js. Engineers have been writing tests ad hoc — there's no consistent style, and we suspect many of these tests aren't catching real bugs.

Below is a simplified version of our **Template Gallery** feature — the system that lets users browse, search, and clone workflow templates. It spans backend (Python) and frontend (React/TypeScript).

## Your Task

**You are encouraged to use any tools you want** — Google, AI assistants, whatever helps you work faster. Part of what we're evaluating is how effectively you use modern tooling.

- **Audit all 5 test files** (3 Python, 2 TypeScript). Identify what's wrong — bad patterns, missing coverage, tests that would pass even if the code was broken, etc.
- **Fix test files** so they are the way you think they should be done. These rewrites represent the standard you'd set for the team.

## Structure

```
backend/                            # Python backend
    src/
        models.py                   # Data models (Node, Edge, Flow, Template)
        template_service.py         # Template CRUD, search, clone, rate limiting
        flow_validator.py           # Flow graph validation
        node_executor.py            # Individual node execution with retry/timeout
    tests/                          # Python tests (AUDIT THESE)
        test_template_service.py    # ← 5 test classes, 18 tests
        test_flow_validator.py      # ← 11 tests
        test_node_executor.py       # ← 14 tests
    pyproject.toml
frontend/
    src/
        api/templates.ts            # API client
        hooks/useTemplates.ts       # React hook for template state
        components/
            TemplateCard.tsx         # Single template display + clone/delete modals
            TemplateGallery.tsx      # Browse/search/filter + pagination
    __tests__/                      # Frontend tests (AUDIT THESE)
        TemplateCard.test.tsx       # ← 12 tests
        TemplateGallery.test.tsx    # ← 13 tests
```

## Dev Environment Setup

### Prerequisites

- **Python 3.11+** — check with `python3 --version`
- **Bun** — install if you don't have it:
  ```bash
  curl -fsSL https://bun.sh/install | bash
  ```
  Then restart your terminal (or run `source ~/.bashrc` / `source ~/.zshrc`).

### Backend (Python)

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install flask pytest
```

### Frontend (TypeScript)

```bash
cd frontend
bun install
```

## Running the App

### Backend

```bash
cd backend
source venv/bin/activate
flask --app app run --port 5001
```

The API will be available at `http://localhost:5001`. The app seeds sample templates on startup.

### Frontend

```bash
cd frontend
bun run dev
```

The frontend will be available at `http://localhost:3000`.

## Running Tests

### Backend

```bash
cd backend
source venv/bin/activate
pytest -v
```

### Frontend

```bash
cd frontend
bun run test
```

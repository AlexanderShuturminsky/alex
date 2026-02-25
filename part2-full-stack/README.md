# Part 2: Write the Full Test Stack (30-40 minutes)

## Context

You're looking at Gumloop's **Template Gallery + Flow Execution** feature. Users browse workflow templates, clone them into personal flows, and execute those flows. The feature spans a Python/Flask backend and a React/TypeScript frontend.

Your job: **write the test suite from scratch, at every layer.**

## You Must Write Tests At ALL of These Layers

### 1. Backend Unit Tests (`backend/tests/test_flow_runner.py`)
Test the `FlowRunner` class in isolation. Mock external deps (LLM, HTTP clients).

### 2. Backend Integration Tests (`backend/tests/test_api.py`)
Test the Flask API endpoints. Use Flask's test client. Verify HTTP status codes, response shapes, error handling, auth, and that the endpoints correctly orchestrate the service layer.

### 3. Frontend Component Tests (`frontend/__tests__/FlowExecutionPanel.test.tsx`)
Test the `FlowExecutionPanel` React component using React Testing Library. Verify rendering, user interactions, state transitions, and error display.

### 4. E2E Tests (`frontend/e2e/template-flow.spec.ts`)
Write Playwright tests for complete user flows. These can be pseudo-code / well-structured outlines if you run out of time — we care about what you'd test and how you'd structure it.

## What's Provided

Each test file has a skeleton with imports, helper functions, and fixtures already set up. You just need to write the actual tests.

## Tools & AI

**Use whatever tools you want.** Google, Claude, ChatGPT, Copilot — all fair game. Part of what we're evaluating is how effectively you leverage modern tools to move fast while maintaining quality.

## What We're Evaluating

1. **Coverage breadth** — Do you test the important paths at each layer?
2. **Test quality** — Are assertions meaningful? Do you test behavior, not implementation?
3. **Layer awareness** — Do you know what belongs in a unit test vs integration test vs E2E?
4. **Error path coverage** — Do you test failure modes, not just happy paths?
5. **AI testing awareness** — The AI node produces non-deterministic output. How do you handle that?
6. **Prioritization** — With limited time, do you focus on what matters most?
7. **Code quality** — Would you be comfortable with engineers using your tests as a template?

## Repo Structure

```
backend/
    src/
        models.py               # All data models (Node, Edge, Flow, FlowRun, Template)
        flow_runner.py          # Flow execution engine (validation, topo sort, dispatch)
        template_service.py     # Template CRUD, search, clone, rate limiting
        app.py                  # Flask API (templates + execution endpoints)
    tests/
        test_flow_runner.py     # ← Write unit tests here
        test_api.py             # ← Write integration tests here
frontend/
    src/
        api/client.ts           # API client (templates + execution)
        hooks/useFlowExecution.ts  # React hook for execution state
        components/
            FlowExecutionPanel.tsx  # Run panel with results display
    __tests__/
        FlowExecutionPanel.test.tsx  # ← Write component tests here
    e2e/
        template-flow.spec.ts       # ← Write Playwright E2E tests here
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
flask --app src.app:create_app run --port 5001
```

The API will be available at `http://localhost:5001`. The app seeds sample templates on startup.

### Frontend

```bash
cd frontend
bun run dev
```

The frontend will be available at `http://localhost:3000`. API requests are proxied to the backend at `http://localhost:5001`.

## Running Tests

### Backend

```bash
cd backend
source venv/bin/activate
pytest -v
```

### Frontend Component Tests

```bash
cd frontend
bun run test
```

### E2E Tests (Playwright)

```bash
cd frontend
bunx playwright install
bunx playwright test
```

## Time Guidance

You have ~30-40 minutes. A reasonable allocation:
- **Unit tests**: 10 min (~10-15 tests)
- **Integration tests**: 12 min (~10-15 tests)
- **Component tests**: 10 min (~8-12 tests)
- **E2E tests**: 8 min (~5-8 tests, can be pseudo-code)

You will not finish everything perfectly. That's intentional. We want to see how you prioritize.

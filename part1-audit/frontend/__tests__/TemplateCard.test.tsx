import { render, screen } from "@testing-library/react";
import { TemplateCard } from "../src/components/TemplateCard";
import type { FlowTemplate } from "../src/api/templates";

const mockTemplate: FlowTemplate = {
  templateId: "tmpl-1",
  name: "Email Automation",
  description: "Automate your email outreach with AI",
  category: "marketing",
  nodes: [
    { nodeId: "n1", nodeType: "trigger", label: "Gmail", params: {}, position: { x: 0, y: 0 } },
    { nodeId: "n2", nodeType: "ai_transform", label: "AI", params: {}, position: { x: 200, y: 0 } },
  ],
  edges: [{ sourceNodeId: "n1", targetNodeId: "n2", sourceOutput: "default", targetInput: "default" }],
  authorId: "user-1",
  isPublic: true,
  useCount: 1234,
  tags: ["email", "outreach", "ai"],
  createdAt: "2025-01-15T00:00:00Z",
};

const mockOnClone = jest.fn().mockResolvedValue({ flowId: "new-flow" });
const mockOnDelete = jest.fn().mockResolvedValue(true);

describe("TemplateCard", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("renders the template name", () => {
    render(<TemplateCard template={mockTemplate} onClone={mockOnClone} />);
    expect(screen.getByText("Email Automation")).toBeTruthy();
  });

  it("renders the description", () => {
    render(<TemplateCard template={mockTemplate} onClone={mockOnClone} />);
    expect(screen.getByText("Automate your email outreach with AI")).toBeTruthy();
  });

  it("renders all tags", () => {
    render(<TemplateCard template={mockTemplate} onClone={mockOnClone} />);
    expect(screen.getByText("email")).toBeTruthy();
    expect(screen.getByText("outreach")).toBeTruthy();
    expect(screen.getByText("ai")).toBeTruthy();
  });

  it("renders the node count", () => {
    render(<TemplateCard template={mockTemplate} onClone={mockOnClone} />);
    expect(screen.getByText("2 nodes")).toBeTruthy();
  });

  it("renders the use count", () => {
    render(<TemplateCard template={mockTemplate} onClone={mockOnClone} />);
    expect(screen.getByText("1,234 uses")).toBeTruthy();
  });

  it("renders the category badge with correct class", () => {
    const { container } = render(
      <TemplateCard template={mockTemplate} onClone={mockOnClone} />
    );
    const badge = container.querySelector(".bg-purple-100");
    expect(badge).not.toBeNull();
    expect(badge?.textContent).toBe("marketing");
  });

  it("renders the clone button", () => {
    render(<TemplateCard template={mockTemplate} onClone={mockOnClone} />);
    expect(screen.getByTestId("clone-button")).toBeTruthy();
    expect(screen.getByTestId("clone-button").textContent).toBe("Use Template");
  });

  it("does not render delete button when not owner", () => {
    render(
      <TemplateCard
        template={mockTemplate}
        onClone={mockOnClone}
        isOwner={false}
      />
    );
    expect(screen.queryByTestId("delete-button")).toBeNull();
  });

  it("renders delete button when owner", () => {
    render(
      <TemplateCard
        template={mockTemplate}
        onClone={mockOnClone}
        onDelete={mockOnDelete}
        isOwner={true}
      />
    );
    expect(screen.queryByTestId("delete-button")).not.toBeNull();
  });

  it("shows cloning state", () => {
    render(
      <TemplateCard template={mockTemplate} onClone={mockOnClone} isCloning={true} />
    );
    expect(screen.getByTestId("clone-button").textContent).toBe("Cloning...");
    expect(screen.getByTestId("clone-button")).toBeDisabled();
  });

  it("matches snapshot", () => {
    const { container } = render(
      <TemplateCard template={mockTemplate} onClone={mockOnClone} />
    );
    expect(container.innerHTML).toMatchSnapshot();
  });

  it("matches snapshot with owner controls", () => {
    const { container } = render(
      <TemplateCard
        template={mockTemplate}
        onClone={mockOnClone}
        onDelete={mockOnDelete}
        isOwner={true}
      />
    );
    expect(container.innerHTML).toMatchSnapshot();
  });
});

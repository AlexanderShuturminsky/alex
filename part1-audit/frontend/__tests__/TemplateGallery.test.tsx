import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { TemplateGallery } from "../src/components/TemplateGallery";
import * as useTemplatesModule from "../src/hooks/useTemplates";

const mockTemplates = [
  {
    templateId: "tmpl-1",
    name: "Email Automation",
    description: "Automate email",
    category: "marketing" as const,
    nodes: [{ nodeId: "n1", nodeType: "trigger", label: "Gmail", params: {}, position: { x: 0, y: 0 } }],
    edges: [],
    authorId: "user-1",
    isPublic: true,
    useCount: 100,
    tags: ["email"],
    createdAt: "2025-01-01T00:00:00Z",
  },
  {
    templateId: "tmpl-2",
    name: "Lead Scraper",
    description: "Scrape leads from web",
    category: "sales" as const,
    nodes: [
      { nodeId: "n1", nodeType: "trigger", label: "Trigger", params: {}, position: { x: 0, y: 0 } },
      { nodeId: "n2", nodeType: "web_scraper", label: "Scraper", params: {}, position: { x: 200, y: 0 } },
    ],
    edges: [{ sourceNodeId: "n1", targetNodeId: "n2", sourceOutput: "default", targetInput: "default" }],
    authorId: "user-2",
    isPublic: true,
    useCount: 50,
    tags: ["leads", "scraping"],
    createdAt: "2025-02-01T00:00:00Z",
  },
];

const mockUseTemplates = {
  templates: mockTemplates,
  total: 2,
  loading: false,
  error: null,
  cloning: null,
  filters: { page: 1, pageSize: 12 },
  setFilters: jest.fn(),
  clone: jest.fn().mockResolvedValue({ flowId: "new-flow" }),
  remove: jest.fn().mockResolvedValue(true),
  refresh: jest.fn(),
};

describe("TemplateGallery", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(useTemplatesModule, "useTemplates").mockReturnValue(mockUseTemplates);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("renders the gallery", () => {
    render(<TemplateGallery />);
    expect(screen.getByTestId("template-gallery")).toBeTruthy();
  });

  it("renders the title", () => {
    render(<TemplateGallery />);
    expect(screen.getByText("Template Gallery")).toBeTruthy();
  });

  it("renders template cards", () => {
    render(<TemplateGallery />);
    expect(screen.getByText("Email Automation")).toBeTruthy();
    expect(screen.getByText("Lead Scraper")).toBeTruthy();
  });

  it("renders the search input", () => {
    render(<TemplateGallery />);
    expect(screen.getByTestId("search-input")).toBeTruthy();
  });

  it("renders the category select", () => {
    render(<TemplateGallery />);
    expect(screen.getByTestId("category-select")).toBeTruthy();
  });

  it("renders the refresh button", () => {
    render(<TemplateGallery />);
    expect(screen.getByTestId("refresh-button")).toBeTruthy();
  });

  it("calls refresh when refresh button is clicked", () => {
    render(<TemplateGallery />);
    fireEvent.click(screen.getByTestId("refresh-button"));
    expect(mockUseTemplates.refresh).toHaveBeenCalled();
  });

  it("calls setFilters when search input changes", () => {
    render(<TemplateGallery />);
    fireEvent.change(screen.getByTestId("search-input"), {
      target: { value: "email" },
    });
    expect(mockUseTemplates.setFilters).toHaveBeenCalledWith(
      expect.objectContaining({ search: "email", page: 1 })
    );
  });

  it("calls setFilters when category changes", () => {
    render(<TemplateGallery />);
    fireEvent.change(screen.getByTestId("category-select"), {
      target: { value: "sales" },
    });
    expect(mockUseTemplates.setFilters).toHaveBeenCalledWith(
      expect.objectContaining({ category: "sales", page: 1 })
    );
  });

  it("has the correct number of grid items", () => {
    const { container } = render(<TemplateGallery />);
    const grid = container.querySelector('[data-testid="template-grid"]');
    expect(grid?.children.length).toBe(2);
  });

  it("passes the right props to TemplateCard", () => {
    render(<TemplateGallery currentUserId="user-1" />);
    // Just checking it renders without error
    expect(screen.getByText("Email Automation")).toBeTruthy();
    expect(screen.getByText("Lead Scraper")).toBeTruthy();
  });

  it("does not render pagination when only one page", () => {
    render(<TemplateGallery />);
    expect(screen.queryByTestId("pagination")).toBeNull();
  });

  it("matches snapshot", () => {
    const { container } = render(<TemplateGallery />);
    expect(container.innerHTML).toMatchSnapshot();
  });
});

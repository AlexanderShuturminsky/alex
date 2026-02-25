import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Gumloop — Flow Execution",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <script src="https://cdn.tailwindcss.com" />
      </head>
      <body className="bg-gray-50 min-h-screen">{children}</body>
    </html>
  );
}

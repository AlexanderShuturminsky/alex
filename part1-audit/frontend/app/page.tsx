"use client";

import { TemplateGallery } from "../src/components/TemplateGallery";

export default function Home() {
  return (
    <main className="py-8">
      <TemplateGallery
        currentUserId="user-dev"
        onFlowCreated={(flowId) => alert(`Flow created: ${flowId}`)}
      />
    </main>
  );
}

import React from "react";
import ReactDOM from "react-dom/client";

// Minimal skeleton window. Event wiring to the Rust backend (transport events
// via Tauri events) lands in Phase 1 (Task 6+).
function App() {
  return (
    <main style={{ fontFamily: "system-ui", padding: "2rem" }}>
      <h1>Agentic Keyboard Companion</h1>
      <p>Skeleton window. Transport / protocol wiring comes in Phase 1.</p>
    </main>
  );
}

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
